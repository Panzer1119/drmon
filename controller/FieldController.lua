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

Parameters:
- reactorInfo: reactor data including fieldDrainRate
- fieldPercent: current field strength (0-1)

Returns: recommended input flux (RF/t)
]]
function FieldController.update(fc, reactorInfo, fieldPercent)
-- If manual input mode, just use configured target
    if not fc.config.autoInputFlux then
        fc.commandedInput = fc.config.targetInputFlux or 0
        return fc.commandedInput
    end

    -- Calculate field velocity (percentage points per update)
    local fieldVelocity = 0
    if fc.lastFieldPercent ~= nil then
        fieldVelocity = fieldPercent - fc.lastFieldPercent
    end
    fc.fieldVelocity = Helpers.ema(0.3, fc.fieldVelocity, fieldVelocity)

    -- Baseline: use measured drain rate
    local baseDrain = reactorInfo.fieldDrainRate or 0

    -- Error correction: how far below target is the field?
    local fieldError = fc.config.targetFieldPercent - fieldPercent
    local fieldErrorCorrection = Helpers.proportional(Constants.FIELD_ERROR_GAIN, fieldError)

    -- Velocity damping: if field is falling quickly, boost input
    local velocityCorrection = 0
    if fc.fieldVelocity < 0 then
    -- Field is falling, apply corrective input
        velocityCorrection = Helpers.proportional(Constants.FIELD_VELOCITY_GAIN, -fc.fieldVelocity)
    end

    -- Combine baseline, error correction, and velocity correction
    fc.commandedInput = baseDrain + fieldErrorCorrection + velocityCorrection

    -- Never go negative
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

