--[[
FieldController.lua - Controls reactor field strength.

Uses proportional control to maintain field near target:
- Baseline: reactor.fieldDrainRate
- Correction: proportional gain based on field error
- Damping: considers field velocity to prevent oscillation

When autoInputFlux is disabled, uses the configured targetInputFlux.
]]

local moduleName = ...
local baseModuleName = moduleName:match("^(.*)%.[^.]+$")

local FieldController = {}
FieldController.__index = FieldController
local Helpers = require(baseModuleName .. ".Helpers")
local Constants = require(baseModuleName .. ".Constants")

--[[
Creates a new field controller.
]]
function FieldController.new(config)
    local fc = {
        config = config,
        lastFieldPercent = nil,
        fieldVelocity = 0,
        commandedInput = 0,
    }
    setmetatable(fc, FieldController)
    return fc
end

--[[
Calculates the desired input flux based on field state.

Algorithm:
  input = baseDrain + errorCorrection + velocityCorrection

  baseDrain       = reactor.fieldDrainRate   (keeps field steady at current level)
  errorCorrection = (targetPercent - currentPercent) * maxFieldStrength * FIELD_ERROR_GAIN
  velocityCorrection = |fieldVelocity| * maxFieldStrength * FIELD_VELOCITY_GAIN
                       (only applied when field is falling, to front-run the drop)

Scaling by maxFieldStrength converts the 0-1 fractional error into RF/t so
the correction is meaningful compared to a drain rate in the hundreds of thousands.

Parameters:
- reactorInfo: reactor data including fieldDrainRate, maxFieldStrength
- fieldPercent: current field strength (0-1)

Returns: recommended input flux (RF/t)
]]
function FieldController.update(fc, reactorInfo, fieldPercent)
	-- If manual input mode, just use configured target
	if not fc.config.autoInputFlux then
		fc.commandedInput = fc.config.targetInputFlux or 0
		return fc.commandedInput
	end

	local maxFieldStrength = reactorInfo.maxFieldStrength or 0

	-- Calculate field velocity (percentage points per update)
	local fieldVelocity = 0
	if fc.lastFieldPercent ~= nil then
		fieldVelocity = fieldPercent - fc.lastFieldPercent
	end
	fc.fieldVelocity = Helpers.ema(0.3, fc.fieldVelocity, fieldVelocity)

	-- Baseline: exactly what the reactor is draining right now.
	-- This alone keeps the field steady; corrections push it up or down.
	local baseDrain = reactorInfo.fieldDrainRate or 0

	-- Error correction: scaled by maxFieldStrength so the result is in RF/t.
	-- Positive when field is below target (boost input), negative when above (reduce input).
	local fieldError = fc.config.targetFieldPercent - fieldPercent
	local fieldErrorCorrection = fieldError * maxFieldStrength * Constants.FIELD_ERROR_GAIN

	-- Velocity damping: if the field is falling quickly, boost input early
	-- to front-run the drop before hitting the minimum.
	-- Also scaled by maxFieldStrength to keep units consistent.
	local velocityCorrection = 0
	if fc.fieldVelocity < 0 then
		velocityCorrection = (-fc.fieldVelocity) * maxFieldStrength * Constants.FIELD_VELOCITY_GAIN
	end

	-- Combine all three terms.
	fc.commandedInput = baseDrain + fieldErrorCorrection + velocityCorrection

	-- Never go negative (flux gates cannot absorb power).
	fc.commandedInput = math.max(0, fc.commandedInput)

	fc.lastFieldPercent = fieldPercent
	return fc.commandedInput
end

--[[
Returns the last commanded input flux.
]]
function FieldController.getCommandedInput(fc)
    return fc.commandedInput
end

--[[
Returns the estimated field velocity (percentage points per update).
]]
function FieldController.getFieldVelocity(fc)
    return fc.fieldVelocity
end

return FieldController

