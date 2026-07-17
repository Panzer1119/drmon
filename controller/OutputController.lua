--[[
OutputController.lua - Controls reactor output with adaptive limiting.

The controller maintains three related values:

1. Commanded Output: what the user requested
2. Allowed Output: the controller's adaptive limit based on safety
3. Actual Output: min(commandedOutput, allowedOutput)

The allowed output adapts based on reactor behavior:
- If stable and well-supplied, it slowly increases toward user request
- If reactor shows stress, it decreases immediately
- Increase speed depends on available field margin

This implements the "discovery" algorithm: gradually finding the highest
safe output without sacrificing stability for performance.
]]

local OutputController = {}
local Helpers = require(script.parent .. ".Helpers")
local Constants = require(script.parent .. ".Constants")

--[[
Creates a new output controller.
]]
function OutputController.new(config)
	local oc = {
		config = config,
		commandedOutput = config.targetOutputFlux or 0,
		allowedOutput = config.targetOutputFlux or 0,
		safeOutput = 0,
		lastActualOutput = 0,
	}
	return oc
end

--[[
Updates output control based on reactor stability and field state.

Parameters:
- fieldPercent: current field strength (0-1)
- isStable: whether reactor is in a stable state
- isSaturated: whether input is power-limited

Returns: recommended output flux (RF/t)
]]
function OutputController.update(oc, deltaTime, fieldPercent, isStable, isSaturated)
	-- If no output target configured, don't do anything
	if oc.config.targetOutputFlux == nil or oc.config.targetOutputFlux == 0 then
		oc.commandedOutput = 0
		oc.allowedOutput = 0
		return 0
	end

	oc.commandedOutput = oc.config.targetOutputFlux

	-- Immediate decrease if system is stressed
	if not isStable or isSaturated then
		-- If saturated, we're already pushing hard; back off
		if isSaturated then
			oc.allowedOutput = oc.allowedOutput * 0.95
		end

		-- Don't decrease below half of what we achieved
		oc.allowedOutput = math.max(oc.safeOutput * 0.5, oc.allowedOutput)
	else
		-- System is stable, consider gradual increase
		-- Increase speed depends on field margin above target

		local fieldMargin = fieldPercent - oc.config.targetFieldPercent

		-- Determine ramp multiplier based on available field margin
		local rampMultiplier = Helpers.adaptiveScale(
			fieldMargin,
			Constants.FIELD_MARGIN_TIGHT,
			Constants.FIELD_MARGIN_COMFORTABLE,
			Constants.RAMP_SPEED_TIGHT,
			Constants.RAMP_SPEED_COMFORTABLE
		)

		-- Calculate maximum allowed increase this update
		local maxIncrease = oc.config.targetOutputFlux * oc.config.outputRampSpeed * rampMultiplier * deltaTime
		maxIncrease = math.max(Constants.OUTPUT_RAMP_MIN_STEP, maxIncrease)

		-- Gradually increase allowed output toward commanded (never exceed commanded)
		if oc.allowedOutput < oc.commandedOutput then
			oc.allowedOutput = math.min(oc.commandedOutput, oc.allowedOutput + maxIncrease)
		end
	end

	-- Clamp to commanded output (user request is upper limit)
	oc.allowedOutput = math.min(oc.allowedOutput, oc.commandedOutput)

	-- Remember the safe output we achieved
	oc.safeOutput = math.max(oc.safeOutput, oc.allowedOutput)

	return oc.allowedOutput
end

--[[
Returns the commanded output (user request).
]]
function OutputController.getCommandedOutput(oc)
	return oc.commandedOutput
end

--[[
Returns the allowed output (adaptive limit).
]]
function OutputController.getAllowedOutput(oc)
	return oc.allowedOutput
end

--[[
Returns the safe output we've achieved so far.
]]
function OutputController.getSafeOutput(oc)
	return oc.safeOutput
end

--[[
Forces output to reduce immediately, maintaining a memory of safe output.
]]
function OutputController.reduceOutput(oc, factor)
	oc.allowedOutput = oc.allowedOutput * factor
	-- Don't forget we achieved this; safe output only goes up
	oc.safeOutput = math.max(oc.safeOutput, oc.allowedOutput)
end

--[[
Resets the output controller (useful for manual override or emergency recovery).
]]
function OutputController.reset(oc)
	oc.commandedOutput = oc.config.targetOutputFlux or 0
	oc.allowedOutput = oc.config.targetOutputFlux or 0
	oc.safeOutput = 0
	oc.lastActualOutput = 0
end

return OutputController

