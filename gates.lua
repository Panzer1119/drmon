local util = require("util")

local M = {}


function M.calculate(

    field,
    maxField,
    fieldDrain,

    targetFieldPercent,
    minFieldPercent,

    temperature,
    maxTemperature,

    energySaturation,
    maxEnergySaturation,

    targetOutput,
    currentOutputGate,

    outputRampPercent,
    outputRampMinimum,
    outputRampMaximum

)

--------------------------------------------------
-- Field control
--------------------------------------------------

    local targetField = targetFieldPercent / 100

    -- Prevent division problems
    targetField = util.clamp(
        targetField,
        0.01,
        0.99
    )

    -- Required RF/t to maintain target field
    local inputGate = fieldDrain / (1 - targetField)

    --------------------------------------------------
    -- Output safety limit
    --------------------------------------------------

    local allowedOutput = targetOutput

    local temperaturePercent = temperature / maxTemperature

    -- Gradually reduce output above 90% temperature
    if temperaturePercent > 0.90 then

        local reduction = (temperaturePercent - 0.90) / 0.10

        allowedOutput = allowedOutput * (1 - reduction * 0.75)

    end

    -- Emergency temperature cutoff
    if temperature >= maxTemperature then
        allowedOutput = 0
    end

    -- Field safety
    local fieldPercent = (field / maxField) * 100

    if fieldPercent < minFieldPercent then
        allowedOutput = 0
    end

    --------------------------------------------------
    -- Calculate reactor stress
    --------------------------------------------------

    local saturationPercent = energySaturation / maxEnergySaturation


    -- Higher number = more dangerous
    local temperatureStress = temperaturePercent

    local saturationStress = 1 - saturationPercent


    local fieldStress = 1 - (field / maxField)


    -- Take the worst factor
    local reactorStress =
        math.max(
            temperatureStress,
            saturationStress,
            fieldStress
        )


    -- Keep a minimum ramp speed
    local rampMultiplier =
        util.clamp(
            1 - reactorStress,
            0.05,
            1
        )


    local dynamicRampPercent = outputRampPercent * rampMultiplier

    local dynamicRampMinimum = outputRampMinimum * rampMultiplier

    local dynamicRampMaximum = outputRampMaximum * rampMultiplier

    --------------------------------------------------
    -- Output ramping
    --------------------------------------------------

    local outputGate

    -- Immediate reduction if danger is increasing
    if allowedOutput < currentOutputGate
    and (
    temperaturePercent > 0.90
    or fieldPercent < minFieldPercent
    ) then

        outputGate = allowedOutput

    else

        outputGate =
            util.approach(
                currentOutputGate,
                allowedOutput,
                dynamicRampPercent,
                dynamicRampMinimum,
                dynamicRampMaximum
            )

    end



    return {
        inputGate = math.floor(inputGate),
        outputGate = math.floor(outputGate),
        allowedOutput = math.floor(allowedOutput),

        reactorStress = reactorStress,
        temperaturePercent = temperaturePercent,
        saturationPercent = saturationPercent,
        fieldPercent = fieldPercent
    }

end


return M
