--[[
Integration Guide - Complete Application Structure

This document shows how to structure a complete application that uses
the Reactor Controller library, including peripheral management, display,
safety features, and data logging.

This is a production-ready template for reactor control software.
]]

-- ============================================================================
-- MODULE: PeripheralManager.lua
-- Handles all peripheral access in one place
-- ============================================================================

local PeripheralManager = {}
PeripheralManager.__index = PeripheralManager

function PeripheralManager.initialize()
    local pm = {
        reactor = nil,
        inputFluxGate = nil,
        outputFluxGate = nil,
        monitor = nil,
    }

    -- Find peripherals with error handling
    pm.reactor = ({ peripheral.find("draconic_reactor") })[1]
    if not pm.reactor then
        error("Draconic reactor not found!")
    end

    pm.inputFluxGate = peripheral.wrap("flow_gate_0")
    if not pm.inputFluxGate then
        error("Input flux gate not found at 'flow_gate_0'!")
    end

    pm.outputFluxGate = peripheral.wrap("flow_gate_1")
    if not pm.outputFluxGate then
        error("Output flux gate not found at 'flow_gate_1'!")
    end

    pm.monitor = ({ peripheral.find("monitor") })[1]
    if not pm.monitor then
        pm.monitor = term  -- Fall back to console
        print("Warning: Monitor not found, using console output.")
    end

    setmetatable(pm, PeripheralManager)
    return pm
end

-- ============================================================================
-- MODULE: DisplayManager.lua
-- Handles UI display and updates
-- ============================================================================

local DisplayManager = {}
DisplayManager.__index = DisplayManager

function DisplayManager.new(monitor)
    local dm = {
        monitor = monitor,
        lines = {},
        dirty = true,
    }
    setmetatable(dm, DisplayManager)
    return dm
end

function DisplayManager.clear(dm)
    dm.monitor.clear()
    dm.monitor.setCursorPos(1, 1)
    dm.lines = {}
    dm.dirty = true
end

function DisplayManager.addLine(dm, text)
    table.insert(dm.lines, text or "")
end

function DisplayManager.render(dm)
    if not dm.dirty and #dm.lines == 0 then
        return
    end

    dm.monitor.clear()
    dm.monitor.setCursorPos(1, 1)

    for i, line in ipairs(dm.lines) do
        dm.monitor.write(line)
        if i < #dm.lines then
            dm.monitor.write("\n")
        end
    end

    dm.dirty = false
end

function DisplayManager.formatValue(label, value, unit)
    unit = unit or ""
    return string.format("%-25s %12s %s", label .. ":", tostring(value), unit)
end

-- ============================================================================
-- MODULE: SafetyMonitor.lua
-- Tracks safety metrics and logs events
-- ============================================================================

local SafetyMonitor = {}
SafetyMonitor.__index = SafetyMonitor

function SafetyMonitor.new()
    local sm = {
        events = {},
        emergencyShutdowns = 0,
        lastEventTime = os.clock(),
    }
    setmetatable(sm, SafetyMonitor)
    return sm
end

function SafetyMonitor.logEvent(sm, severity, message)
    local event = {
        time = os.clock(),
        severity = severity,  -- "INFO", "WARNING", "ERROR", "CRITICAL"
        message = message,
    }
    table.insert(sm.events, event)
    sm.lastEventTime = event.time

    -- Keep only last 100 events
    if #sm.events > 100 then
        table.remove(sm.events, 1)
    end
end

function SafetyMonitor.getRecentEvents(sm, count)
    count = count or 10
    local recent = {}
    for i = math.max(1, #sm.events - count + 1), #sm.events do
        table.insert(recent, sm.events[i])
    end
    return recent
end

-- ============================================================================
-- MODULE: ReactorMonitor.lua
-- Main application controller
-- ============================================================================

local ReactorController = require("controller")

local ReactorMonitor = {}
ReactorMonitor.__index = ReactorMonitor

function ReactorMonitor.new(config, peripherals)
    local rm = {
        controller = nil,
        peripherals = peripherals,
        config = config,
        state = {
            running = true,
            paused = false,
            lastUpdateTime = os.clock(),
            updateCount = 0,
        },
        safety = SafetyMonitor.new(),
        display = DisplayManager.new(peripherals.monitor),
    }

    -- Create controller
    local controller, err = ReactorController.new(config)
    if not controller then
        rm.safety:logEvent("CRITICAL", "Controller creation failed: " .. err)
        return nil, err
    end
    rm.controller = controller

    rm.safety:logEvent("INFO", "Reactor Monitor initialized")
    setmetatable(rm, ReactorMonitor)
    return rm
end

function ReactorMonitor.update(rm)
    if rm.state.paused then
        return
    end

    local currentTime = os.clock()
    local deltaTime = currentTime - rm.state.lastUpdateTime
    rm.state.lastUpdateTime = currentTime
    rm.state.updateCount = rm.state.updateCount + 1

    -- Cap deltaTime to prevent huge jumps (e.g., if computer stopped)
    deltaTime = math.min(deltaTime, 0.1)

    -- Read reactor state
    local reactorInfo
    local success, err = pcall(function()
        reactorInfo = rm.peripherals.reactor.getReactorInfo()
    end)

    if not success then
        rm.safety:logEvent("ERROR", "Failed to read reactor: " .. tostring(err))
        return
    end

    -- Read flux gate values
    local inputFlux = rm.peripherals.inputFluxGate.getFlow()
    local outputFlux = rm.peripherals.outputFluxGate.getFlow()

    -- Update controller
    local result = rm.controller:update(deltaTime, reactorInfo, inputFlux, outputFlux)

    -- Apply commands
    if not rm.state.paused then
        rm.peripherals.inputFluxGate.setFlowOverride(result.inputFlux)
        rm.peripherals.outputFluxGate.setFlowOverride(result.outputFlux)
    end

    -- Safety check: ignore emergency shutdown if reactor is cold
    if reactorInfo.status == "cold" and result.emergencyShutdown then
        --rm.safety:logEvent("INFO", "Emergency shutdown requested while reactor is cold; ignoring.")
        result.emergencyShutdown = false
    end

    -- Handle emergency shutdown
    if result.emergencyShutdown then
        rm:handleEmergencyShutdown()
    end

    -- Update diagnostics every 20 cycles (1 second at 20 Hz)
    if rm.state.updateCount % 20 == 0 then
        rm:updateDisplay()
    end
end

function ReactorMonitor.updateDisplay(rm)
    local diags = rm.controller:getDiagnostics()

    rm.display:clear()
    rm.display:addLine("=== Reactor Controller ===")
    rm.display:addLine("")

    -- State
    rm.display:addLine(DisplayManager.formatValue("State", diags.state))
    if diags.emergencyShutdown then
        rm.display:addLine(">>>>> EMERGENCY SHUTDOWN <<<<<")
        rm.display:addLine(diags.shutdownReason)
    end
    rm.display:addLine("")

    -- Field
    rm.display:addLine(DisplayManager.formatValue(
        "Field Strength",
        string.format("%.1f%%", diags.fieldPercent * 100),
        string.format("(target: %.0f%%)", diags.fieldTarget * 100)
    ))
    rm.display:addLine(DisplayManager.formatValue(
        "Field Velocity",
        string.format("%.4f", diags.fieldVelocity),
        "pp/update"
    ))
    rm.display:addLine("")

    -- Temperature
    rm.display:addLine(DisplayManager.formatValue(
        "Temperature",
        string.format("%.0f°C", diags.temperature),
        string.format("/ %.0f°C", diags.maximumTemperature)
    ))
    rm.display:addLine("")

    -- Input
    rm.display:addLine(DisplayManager.formatValue(
        "Input Command",
        string.format("%.0f", diags.commandedInput),
        "RF/t"
    ))
    if diags.maximumInput then
        rm.display:addLine(DisplayManager.formatValue(
            "Input Limit",
            string.format("%.0f", diags.maximumInput),
            "RF/t"
        ))
    end
    rm.display:addLine("")

    -- Output
    rm.display:addLine(DisplayManager.formatValue(
        "Output Command",
        string.format("%.0f", diags.commandedOutput),
        "RF/t"
    ))
    rm.display:addLine(DisplayManager.formatValue(
        "Output Allowed",
        string.format("%.0f", diags.allowedOutput),
        "RF/t"
    ))
    rm.display:addLine(DisplayManager.formatValue(
        "Output Safe",
        string.format("%.0f", diags.safeOutput),
        "RF/t"
    ))
    rm.display:addLine("")

    -- Saturation
    rm.display:addLine(DisplayManager.formatValue(
        "Saturation",
        string.format("%.0f%%", diags.saturationConfidence * 100)
    ))
    if diags.isSaturated then
        rm.display:addLine("  Status: INPUT-LIMITED")
    end

    rm.display:render()
end

function ReactorMonitor.handleEmergencyShutdown(rm)
    rm.safety:logEvent("CRITICAL", "Emergency shutdown triggered: " .. rm.controller:getEmergencyShutdownReason())
    rm.safety.emergencyShutdowns = rm.safety.emergencyShutdowns + 1

    -- Emergency shutdown
    rm.peripherals.reactor.stopReactor()
    --rm.state.running = false

    -- Alert
    print("REACTOR EMERGENCY SHUTDOWN")
    print(rm.controller:getEmergencyShutdownReason())
end

function ReactorMonitor.pause(rm)
    rm.state.paused = not rm.state.paused
    if rm.state.paused then
        rm.safety:logEvent("INFO", "Reactor monitoring paused")
    else
        rm.safety:logEvent("INFO", "Reactor monitoring resumed")
    end
end

function ReactorMonitor.run(rm)
    while rm.state.running do
        rm:update()
        sleep(0.05)  -- 20 Hz update rate
    end
end

-- ============================================================================
-- MAIN APPLICATION
-- ============================================================================

local function main()
    print("Draconic Evolution Reactor Control System v1.0")
    print("")

    -- Configuration (adjust for your setup)
    local config = {
        minimumFieldPercent = 0.15,
        targetFieldPercent = 0.50,
        maximumTemperature = 8000,
        targetOutputFlux = 15000,
        outputRampSpeed = 0.05,
        autoInputFlux = true,
        maximumInputFlux = 50000,
    }

    -- Initialize peripherals
    print("Initializing peripherals...")
    local peripherals, err = PeripheralManager.initialize()
    if not peripherals then
        print("ERROR: " .. err)
        return
    end
    print("Peripherals initialized OK")
    print("")

    -- Create monitor
    print("Starting reactor monitor...")
    local monitor, err = ReactorMonitor.new(config, peripherals)
    if not monitor then
        print("ERROR: " .. err)
        return
    end

    print("Reactor monitor running!")
    print("Press Ctrl+T to terminate")
    print("")

    -- Run main loop
    monitor:run()

    print("")
    print("Reactor monitoring stopped")
    print(string.format("Total shutdowns: %d", monitor.safety.emergencyShutdowns))
end

-- Run if this is the main file
if ... == nil then
    main()
end

return ReactorMonitor


-- ============================================================================
-- EXAMPLE: Standalone Usage
-- ============================================================================

--[[
To use this as a complete application:

1. Place in a file like "reactor_control.lua"

2. Run: lua reactor_control.lua

3. Or use in another script:

local ReactorMonitor = require("reactor_control")

local config = {
    minimumFieldPercent = 0.15,
    targetFieldPercent = 0.50,
    -- ... other config
}

local peripherals = PeripheralManager.initialize()
local monitor = ReactorMonitor.new(config, peripherals)

-- Simulate some updates
for i = 1, 100 do
    monitor:update()
    sleep(0.05)
end
]]

