local Util = require("drmon.util")

local FieldRateController = {}
FieldRateController.__index = FieldRateController

function FieldRateController.new()
    return setmetatable({}, FieldRateController)
end

function FieldRateController:calculate(options)
    local currentInputRate = Util.roundRate(options.currentInputRate or 0)
    local fieldStrength = math.max(options.fieldStrength or 0, 0)
    local maxFieldStrength = math.max(options.maxFieldStrength or 0, 0)
    local fieldDrainRate = math.max(options.fieldDrainRate or 0, 0)
    local targetFieldPercent = options.targetFieldPercent or 0
    local minimumInputRate = math.max(options.minimumInputRate or 0, 0)
    local inputReductionRampRate = math.max(options.inputReductionRampRate or 0, 0)
    local fieldRecoveryWindow = math.max(options.fieldRecoveryWindow or 1, 1)
    local deltaTime = math.max(options.deltaTime or 0, 0)

    local targetFieldStrength = maxFieldStrength * (targetFieldPercent / 100)
    local fieldDelta = targetFieldStrength - fieldStrength
    local correctionRate = 0

    if maxFieldStrength > 0 then
        correctionRate = fieldDelta / (fieldRecoveryWindow * 20)
    end

    local idealInputRate = Util.roundRate(math.max(minimumInputRate, fieldDrainRate + correctionRate))

    if idealInputRate >= currentInputRate then
        return idealInputRate, {
            idealInputRate = idealInputRate,
            fieldDelta = fieldDelta,
            mode = fieldDelta > 0 and "recovering_field" or "holding_field",
        }
    end

    local maximumReduction = inputReductionRampRate * deltaTime
    local nextInputRate = math.max(idealInputRate, currentInputRate - maximumReduction)
    nextInputRate = Util.roundRate(math.max(nextInputRate, minimumInputRate))

    return nextInputRate, {
        idealInputRate = idealInputRate,
        fieldDelta = fieldDelta,
        mode = fieldDelta < 0 and "trimming_field_input" or "holding_field",
    }
end

return FieldRateController
