--[[
Example: Draconic Evolution Reactor Controller Integration

This example shows how to use the ReactorController library in a real application.
The application is responsible for:
1. Reading reactor data
2. Reading flux gate states
3. Writing commands to flux gates
4. Handling emergency shutdown

This keeps the controller pure logic - it never touches peripherals.
]]

-- Example 1: Basic usage
-- ============================================================================

local ReactorController = require("controller")

-- Create controller with configuration
local config = {
	-- Field strength control (0-1 range)
	minimumFieldPercent = 0.15,     -- Shutdown if below this
	targetFieldPercent = 0.50,      -- Try to maintain this

	-- Temperature safety
	maximumTemperature = 8000,      -- Celsius

	-- Output control
	targetOutputFlux = 15000,       -- RF/t desired output
	outputRampSpeed = 0.05,         -- Max 5% increase per second

	-- Input control
	autoInputFlux = true,           -- Calculate input from field error
	targetInputFlux = 10000,        -- Ignored if autoInputFlux=true
	maximumInputFlux = 50000,       -- Optional: max input power
}

local reactor = peripheral.find("draconic_reactor")
local inputFluxGate = peripheral.wrap("flux_gate_0")
local outputFluxGate = peripheral.wrap("flux_gate_1")

-- Create the controller
local controller, err = ReactorController.new(config)
if not controller then
	error("Failed to create controller: " .. err)
end

-- Main loop
local lastTime = os.clock()
while true do
	local currentTime = os.clock()
	local deltaTime = currentTime - lastTime
	lastTime = currentTime

	-- Read reactor state
	local reactorInfo = reactor.getReactorInfo()

	-- Read current flux gate outputs
	local currentInputFlux = inputFluxGate.getFlow()
	local currentOutputFlux = outputFluxGate.getFlow()

	-- Update controller (this is where the magic happens)
	local result = controller:update(deltaTime, reactorInfo, currentInputFlux, currentOutputFlux)

	-- Apply the control commands
	inputFluxGate.setFlowOverride(result.inputFlux)
	outputFluxGate.setFlowOverride(result.outputFlux)

	-- Handle emergency shutdown
	if result.emergencyShutdown then
		reactor.stopReactor()
		local reason = controller:getEmergencyShutdownReason()
		print("EMERGENCY SHUTDOWN: " .. reason)
		break
	end

	-- Optional: display diagnostics
	if controller.updateCount % 20 == 0 then
		local diags = controller:getDiagnostics()
		print(Diagnostics.format(diags))
	end

	sleep(0.05)  -- 20 Hz update rate
end


-- Example 2: Manual control with diagnostics display
-- ============================================================================

--[[
This example shows a more interactive setup with a display
]]

local Diagnostics = require("controller.Diagnostics")

local config = {
	minimumFieldPercent = 0.15,
	targetFieldPercent = 0.50,
	maximumTemperature = 8000,
	targetOutputFlux = 10000,
	outputRampSpeed = 0.05,
	autoInputFlux = true,
	maximumInputFlux = 45000,
}

local controller = ReactorController.new(config)
local reactor = peripheral.find("draconic_reactor")
local inputFluxGate = peripheral.wrap("flux_gate_0")
local outputFluxGate = peripheral.wrap("flux_gate_1")
local monitor = term  -- Could be peripheral.wrap("monitor_1")

local lastTime = os.clock()
local running = true

-- Control loop
while running do
	local currentTime = os.clock()
	local deltaTime = math.min(currentTime - lastTime, 0.1)  -- Cap deltaTime
	lastTime = currentTime

	local reactorInfo = reactor.getReactorInfo()
	local inputFlux = inputFluxGate.getFlow()
	local outputFlux = outputFluxGate.getFlow()

	local result = controller:update(deltaTime, reactorInfo, inputFlux, outputFlux)

	-- Apply commands
	inputFluxGate.setFlowOverride(result.inputFlux)
	outputFluxGate.setFlowOverride(result.outputFlux)

	-- Handle shutdown
	if result.emergencyShutdown then
		reactor.stopReactor()
		print("EMERGENCY SHUTDOWN: " .. controller:getEmergencyShutdownReason())
		running = false
	end

	-- Display diagnostics every second
	if controller.updateCount % 20 == 0 then
		monitor.clear()
		monitor.setCursorPos(1, 1)

		local diags = controller:getDiagnostics()
		monitor.write(Diagnostics.format(diags))
	end

	sleep(0.05)
end


-- Example 3: Configuration for conservative (safe) operation
-- ============================================================================

local conservativeConfig = {
	-- Require very healthy field at all times
	minimumFieldPercent = 0.20,
	targetFieldPercent = 0.60,

	-- Low temperature limit
	maximumTemperature = 7000,

	-- Moderate output with slow ramp
	targetOutputFlux = 8000,
	outputRampSpeed = 0.02,

	-- Explicitly limit input to known safe value
	autoInputFlux = true,
	maximumInputFlux = 40000,
}


-- Example 4: Configuration for aggressive (high-output) operation
-- ============================================================================

local aggressiveConfig = {
	-- Accept lower field margins
	minimumFieldPercent = 0.10,
	targetFieldPercent = 0.40,

	-- Higher temperature tolerance
	maximumTemperature = 8500,

	-- Push for higher output
	targetOutputFlux = 25000,
	outputRampSpeed = 0.10,

	-- Higher input limit for more power
	autoInputFlux = true,
	maximumInputFlux = 80000,
}


-- Example 5: Manual input mode (for testing or special scenarios)
-- ============================================================================

local manualInputConfig = {
	minimumFieldPercent = 0.15,
	targetFieldPercent = 0.50,
	maximumTemperature = 8000,
	targetOutputFlux = 15000,
	outputRampSpeed = 0.05,

	-- Disable automatic input calculation
	autoInputFlux = false,
	targetInputFlux = 12000,  -- Fixed input value
	maximumInputFlux = nil,    -- No limit
}

