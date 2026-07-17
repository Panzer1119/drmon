--[[
Diagnostics.lua - Provides a diagnostic view of controller state.

Returns a table suitable for display in a UI or logging system.
All values are read-only snapshots; the diagnostics table does not expose
mutable state.
]]

local Diagnostics = {}

--[[
Creates and returns a diagnostics snapshot.

This captures the current state of all key controller variables
suitable for UI display or debugging.

Parameters:
- controller: the ReactorController instance

Returns: diagnostics table with all relevant state
]]
function Diagnostics.snapshot(controller)
	local diags = {
		-- State machine
		state = controller.stateMachine.state,
		stateTimer = controller.stateMachine.stateTimer,

		-- Safety
		emergencyShutdown = controller.emergencyShutdown,
		shutdownReason = controller.shutdownReason,

		-- Field
		fieldPercent = controller.lastFieldPercent,
		fieldVelocity = controller.fieldController:getFieldVelocity(),
		fieldTarget = controller.config.targetFieldPercent,
		fieldMinimum = controller.config.minimumFieldPercent,

		-- Input
		commandedInput = controller.fieldController:getCommandedInput(),
		maximumInput = controller.config.maximumInputFlux,

		-- Output
		commandedOutput = controller.outputController:getCommandedOutput(),
		allowedOutput = controller.outputController:getAllowedOutput(),
		safeOutput = controller.outputController:getSafeOutput(),

		-- Saturation
		saturationConfidence = controller.saturationDetector:getConfidence(),
		isSaturated = controller.saturationDetector:isSaturated(),

		-- Reactor state (from last update)
		temperature = controller.lastTemperature,
		maximumTemperature = controller.config.maximumTemperature,

		-- Update timing
		lastDeltaTime = controller.lastDeltaTime,
	}

	return diags
end

--[[
Formats diagnostics as a readable string for debugging.
]]
function Diagnostics.format(diags)
	local lines = {}

	table.insert(lines, "=== Reactor Controller Diagnostics ===")
	table.insert(lines, "")

	table.insert(lines, "State: " .. diags.state)
	if diags.emergencyShutdown then
		table.insert(lines, "EMERGENCY SHUTDOWN: " .. (diags.shutdownReason or "Unknown"))
	end
	table.insert(lines, "")

	table.insert(lines, string.format("Field: %.1f%% (target: %.1f%%, min: %.1f%%)",
		diags.fieldPercent * 100,
		diags.fieldTarget * 100,
		diags.fieldMinimum * 100))
	table.insert(lines, string.format("Field velocity: %.4f pp/update", diags.fieldVelocity))
	table.insert(lines, "")

	table.insert(lines, string.format("Input: %.0f RF/t commanded", diags.commandedInput))
	if diags.maximumInput then
		table.insert(lines, string.format("  (limited to %.0f RF/t)", diags.maximumInput))
	end
	table.insert(lines, "")

	table.insert(lines, string.format("Output: %.0f RF/t commanded", diags.commandedOutput))
	table.insert(lines, string.format("  %.0f RF/t allowed", diags.allowedOutput))
	table.insert(lines, string.format("  %.0f RF/t safe so far", diags.safeOutput))
	table.insert(lines, "")

	table.insert(lines, string.format("Saturation confidence: %.1f%%", diags.saturationConfidence * 100))
	if diags.isSaturated then
		table.insert(lines, "  Status: SATURATED (input-limited)")
	end
	table.insert(lines, "")

	table.insert(lines, string.format("Temperature: %.0f°C / %.0f°C max",
		diags.temperature,
		diags.maximumTemperature))
	table.insert(lines, "")

	table.insert(lines, string.format("Last update: %.3fs", diags.lastDeltaTime))

	return table.concat(lines, "\n")
end

return Diagnostics

