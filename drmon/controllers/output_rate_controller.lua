local Util = require("drmon.util")

local OutputRateController = {}
OutputRateController.__index = OutputRateController

function OutputRateController.new()
    return setmetatable({}, OutputRateController)
end

function OutputRateController:calculate(options)
    local currentOutputRate = Util.roundRate(options.currentOutputRate or 0)
    local targetOutputRate = Util.roundRate(options.targetOutputRate or 0)
    local fieldPercent = options.fieldPercent or 0
    local targetFieldPercent = options.targetFieldPercent or 0
    local temperature = options.temperature or 0
    local maxTemperature = options.maxTemperature or 0
    local outputRampRate = math.max(options.outputRampRate or 0, 0)
    local deltaTime = math.max(options.deltaTime or 0, 0)

    if targetOutputRate <= currentOutputRate then
        return targetOutputRate, {
            idealOutputRate = targetOutputRate,
            mode = targetOutputRate < currentOutputRate and "reducing_output" or "holding_output",
        }
    end

    if fieldPercent < targetFieldPercent then
        return currentOutputRate, {
            idealOutputRate = targetOutputRate,
            mode = "waiting_for_field",
        }
    end

    if temperature > maxTemperature then
        return currentOutputRate, {
            idealOutputRate = targetOutputRate,
            mode = "temperature_limited",
        }
    end

    local maximumIncrease = outputRampRate * deltaTime
    local nextOutputRate = math.min(targetOutputRate, currentOutputRate + maximumIncrease)

    return Util.roundRate(nextOutputRate), {
        idealOutputRate = targetOutputRate,
        mode = nextOutputRate < targetOutputRate and "ramping_output" or "target_output_reached",
    }
end

return OutputRateController
