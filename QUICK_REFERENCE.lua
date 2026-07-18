--[[
QUICK REFERENCE - Reactor Controller Library

A one-page cheat sheet for common tasks.
]]

-- ============================================================================
-- MINIMAL EXAMPLE
-- ============================================================================

local ReactorController = require("controller")
local controller = ReactorController.new({})  -- Uses all defaults

-- Per update cycle (call 20x per second):
local result = controller:update(
    deltaTime,
    reactor.getReactorInfo(),
    inputFluxGate.getFlow(),
    outputFluxGate.getFlow()
)

inputFluxGate.setFlowOverride(result.inputFlux)
outputFluxGate.setFlowOverride(result.outputFlux)
if result.emergencyShutdown then
    reactor.stopReactor()
end


-- ============================================================================
-- RETURN VALUE
-- ============================================================================

-- result = {
--     inputFlux = number,              -- RF/t to set input flux gate to
--     outputFlux = number,             -- RF/t to set output flux gate to
--     emergencyShutdown = boolean      -- If true, STOP REACTOR IMMEDIATELY
-- }


-- ============================================================================
-- CONFIGURATION REFERENCE
-- ============================================================================

-- All fields are optional; defaults are provided
local config = {
    -- SAFETY LIMITS (set these first!)
    minimumFieldPercent = 0.15,      -- Shutdown if below (default: 0.15)
    targetFieldPercent = 0.50,       -- Try to maintain (default: 0.50)
    maximumTemperature = 8000,       -- Shutdown if above (default: 8000)

    -- OUTPUT CONTROL
    targetOutputFlux = 15000,        -- RF/t desired (default: nil = off)
    outputRampSpeed = 0.05,          -- Max 5% increase/sec (default: 0.05)

    -- INPUT CONTROL
    autoInputFlux = true,            -- Auto calc from field error (default: true)
    targetInputFlux = 10000,         -- Used if autoInputFlux=false
    maximumInputFlux = 50000,        -- Optional max (default: nil = no limit)
}


-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Create controller
local controller = ReactorController.new(config)  -- or (nil, error)

-- Main update (call every 0.05 seconds for 20Hz)
local result = controller:update(deltaTime, reactorInfo, inputFlux, outputFlux)

-- Get diagnostics for UI
local diags = controller:getDiagnostics()
-- Fields: state, fieldPercent, fieldVelocity, commandedInput, allowedOutput,
--         saturationConfidence, temperature, shutdownReason, etc.

-- Get shutdown reason
local reason = controller:getEmergencyShutdownReason()

-- Reset to initial state
controller:reset()


-- ============================================================================
-- TYPICAL INTEGRATION PATTERN
-- ============================================================================

local ReactorController = require("controller")
local reactor = peripheral.find("draconic_reactor")
local inputGate = peripheral.wrap("flux_gate_0")
local outputGate = peripheral.wrap("flux_gate_1")

-- Create with your config
local controller = ReactorController.new({
    minimumFieldPercent = 0.15,
    targetFieldPercent = 0.50,
    maximumTemperature = 8000,
    targetOutputFlux = 15000,
    outputRampSpeed = 0.05,
    autoInputFlux = true,
    maximumInputFlux = 50000,
})

-- Main loop
local lastTime = os.clock()
while true do
-- Timing
    local now = os.clock()
    local deltaTime = now - lastTime
    lastTime = now

    -- Read hardware
    local reactorInfo = reactor.getReactorInfo()
    local inputFlow = inputGate.getFlow()
    local outputFlow = outputGate.getFlow()

    -- Control
    local result = controller:update(deltaTime, reactorInfo, inputFlow, outputFlow)

    -- Write hardware
    inputGate.setFlowOverride(result.inputFlux)
    outputGate.setFlowOverride(result.outputFlux)

    -- Handle emergency
    if result.emergencyShutdown then
        reactor.stopReactor()
        print("SHUTDOWN: " .. controller:getEmergencyShutdownReason())
        break
    end

    sleep(0.05)  -- 20 Hz
end


-- ============================================================================
-- PRESETS
-- ============================================================================

-- CONSERVATIVE: Safe for expensive reactors
local conservativeConfig = {
    minimumFieldPercent = 0.20,
    targetFieldPercent = 0.60,
    maximumTemperature = 7000,
    targetOutputFlux = 8000,
    outputRampSpeed = 0.02,
    autoInputFlux = true,
    maximumInputFlux = 40000,
}

-- BALANCED: Default safe operation
local balancedConfig = {
    minimumFieldPercent = 0.15,
    targetFieldPercent = 0.50,
    maximumTemperature = 8000,
    targetOutputFlux = 15000,
    outputRampSpeed = 0.05,
    autoInputFlux = true,
    maximumInputFlux = 50000,
}

-- AGGRESSIVE: High output, accept more risk
local aggressiveConfig = {
    minimumFieldPercent = 0.10,
    targetFieldPercent = 0.40,
    maximumTemperature = 8500,
    targetOutputFlux = 25000,
    outputRampSpeed = 0.10,
    autoInputFlux = true,
    maximumInputFlux = 80000,
}


-- ============================================================================
-- STATE MACHINE
-- ============================================================================

-- Controller operates in clear states:
-- STABLE        - Field healthy, can increase output
-- RECOVERING    - Field below target, focus on recovery
-- LIMITED       - Output at user limit or safety limit
-- SATURATED     - Input power is the limit
-- EMERGENCY     - Shutdown condition triggered

-- Check state:
local diags = controller:getDiagnostics()
if diags.state == "EMERGENCY" then
    print("Reactor in emergency!")
end


-- ============================================================================
-- TUNING GUIDELINES
-- ============================================================================

-- Field percent
-- - Lower minimumField = riskier, more output possible
-- - Higher targetField = more stable, less output
-- - Difference between them = margin for error

-- Temperature
-- - Lower = safer but less output
-- - 8000 = standard limit
-- - 8500+ = risky

-- Output ramp speed
-- - 0.02 = very conservative (slow discovery)
-- - 0.05 = balanced (default)
-- - 0.10 = aggressive (fast discovery)

-- Maximum input flux
-- - Set based on your power input capacity
-- - Prevents over-commanding flux gates
-- - nil = no limit (auto mode discovers it)


-- ============================================================================
-- DEBUGGING
-- ============================================================================

-- Print diagnostics
local diags = controller:getDiagnostics()
print(string.format(
    "State: %s, Field: %.1f%%, Temp: %.0f°C, Sat: %.1f%%",
    diags.state,
    diags.fieldPercent * 100,
    diags.temperature,
    diags.saturationConfidence * 100
))

-- Check if input-limited
if diags.saturationConfidence > 0.5 then
    print("Input may be saturated, consider higher maximumInputFlux")
end

-- Check field velocity
print("Field velocity: " .. diags.fieldVelocity .. " pp/update")

-- Check safe output
print("Safe output achieved: " .. diags.safeOutput .. " RF/t")


-- ============================================================================
-- COMMON ISSUES
-- ============================================================================

-- Q: Field won't increase
-- A: Check maximumInputFlux isn't too low, or reactor.fieldDrainRate is accurate

-- Q: Output won't reach target
-- A: Field might be low, or saturation detected. Check diagnostics.

-- Q: Reactor keeps shutting down
-- A: minimumFieldPercent too high, or temperature too close to limit

-- Q: Weird state changes
-- A: Check deltaTime is consistent (not huge jumps or zeroes)
-- A: Verify reactor responds to flux gate commands quickly enough

-- Q: Performance issues
-- A: Controller is minimal, issue likely elsewhere
-- A: Try adjusting STATE_CHANGE_DELAY in Constants.lua

