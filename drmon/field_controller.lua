local FieldController = {}
FieldController.__index = FieldController

local DEFAULT_CONFIG = {
    responseMultiplier = 4,
    trimMultiplier = 0.5,
}

local function copyTable(source)
    local copy = {}

    for key, value in pairs(source) do
        copy[key] = value
    end

    return copy
end

local function expectNonNegativeNumber(name, value)
    if type(value) ~= "number" or value < 0 then
        error(string.format("%s must be a non-negative number", name), 3)
    end
end

function FieldController.new(config)
    local self = setmetatable({}, FieldController)

    self._config = copyTable(DEFAULT_CONFIG)
    self:updateConfig(config or {})

    return self
end

function FieldController:updateConfig(config)
    if config.responseMultiplier ~= nil then
        expectNonNegativeNumber("responseMultiplier", config.responseMultiplier)
        self._config.responseMultiplier = config.responseMultiplier
    end

    if config.trimMultiplier ~= nil then
        expectNonNegativeNumber("trimMultiplier", config.trimMultiplier)
        self._config.trimMultiplier = config.trimMultiplier
    end
end

function FieldController:getConfig()
    return copyTable(self._config)
end

function FieldController:calculate(context)
    if type(context) ~= "table" then
        error("context must be a table", 2)
    end

    local currentInputRate = math.max(0, tonumber(context.currentInputRate) or 0)
    local minInputRate = math.max(0, tonumber(context.minInputRate) or 0)
    local fieldDrainRate = math.max(0, tonumber(context.fieldDrainRate) or 0)
    local fieldPercent = math.max(0, math.min(100, tonumber(context.fieldPercent) or 0))
    local targetFieldPercent = math.max(0, math.min(100, tonumber(context.targetFieldPercent) or 0))
    local deltaTime = math.max(0, tonumber(context.deltaTime) or 0)
    local inputRampDownPerSecond = math.max(0, tonumber(context.inputRampDownPerSecond) or 0)

    local baseHoldRate = math.max(minInputRate, fieldDrainRate)
    local controlTargetRate = baseHoldRate
    local reason = "holding_field"

    if fieldPercent < targetFieldPercent then
        local deficitRatio = (targetFieldPercent - fieldPercent) / math.max(targetFieldPercent, 1)
        local recoveryBoost = math.max(baseHoldRate, currentInputRate, 1) * deficitRatio * self._config.responseMultiplier

        controlTargetRate = baseHoldRate + recoveryBoost
        reason = "boosting_field"
    elseif fieldPercent > targetFieldPercent then
        local overshootRatio = (fieldPercent - targetFieldPercent) / math.max(100 - targetFieldPercent, 1)
        local trimAmount = math.max(fieldDrainRate, minInputRate, 1) * overshootRatio * self._config.trimMultiplier

        controlTargetRate = math.max(minInputRate, baseHoldRate - trimAmount)
        reason = "trimming_field"
    end

    local desiredInputRate = controlTargetRate

    if controlTargetRate < currentInputRate then
        local maxDecrease = inputRampDownPerSecond * deltaTime

        if maxDecrease > 0 then
            desiredInputRate = math.max(controlTargetRate, currentInputRate - maxDecrease)
        else
            desiredInputRate = currentInputRate
        end
    end

    if fieldPercent < targetFieldPercent and desiredInputRate < baseHoldRate then
        desiredInputRate = baseHoldRate
    end

    return {
        desiredInputRate = desiredInputRate,
        baseHoldRate = baseHoldRate,
        controlTargetRate = controlTargetRate,
        fieldDelta = targetFieldPercent - fieldPercent,
        recovering = fieldPercent < targetFieldPercent,
        trimming = controlTargetRate < currentInputRate,
        reason = reason,
    }
end

return FieldController
