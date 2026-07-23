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

    targetOutput,
    currentOutputGate,

    outputRampPercent,
    outputRampMinimum

)

-- Convert target field percent to a decimal value
    local targetField = targetFieldPercent / 100

    -- Prevent division problems
    targetField = util.clamp(
        targetField,
        0.01,
        0.99
    )

    -- RF/t required to maintain the target field level
    local inputGate = fieldDrain / (1 - targetField)

    local allowedOutput = targetOutput

    local temperaturePercent = temperature / maxTemperature

    -- Start reducing output when temperature exceeds 90% of max temperature
    if temperaturePercent > 0.90 then

        local reduction = (temperaturePercent - 0.90) / 0.10

        allowedOutput = allowedOutput * (1 - reduction * 0.75)

    end

    -- Cut output completely if temperature exceeds max temperature
    if temperature >= maxTemperature then
        allowedOutput = 0
    end

    -- Field percent is the current field level as a percentage of the maximum field level
    local fieldPercent = (field / maxField) * 100

    -- Cut output completely if field is below minimum field percent
    if fieldPercent < minFieldPercent then
        allowedOutput = 0
    end

    local outputGate

    if temperaturePercent >= 0.90
    and allowedOutput < currentOutputGate then

    -- During high temperature conditions, drop output immediately
    -- instead of ramping down slowly.
        outputGate = allowedOutput

    else

    -- Ramp output gate towards allowed output, but don't exceed the allowed output
        outputGate =
            util.approach(
                currentOutputGate,
                allowedOutput,
                outputRampPercent,
                outputRampMinimum
            )

    end

    return {
        inputGate = math.floor(inputGate),
        outputGate = math.floor(outputGate),
        allowedOutput = math.floor(allowedOutput)
    }

end


return M
