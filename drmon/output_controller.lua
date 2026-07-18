local OutputController = {}
OutputController.__index = OutputController

function OutputController.new()
    return setmetatable({}, OutputController)
end

function OutputController:calculate(context)
    if type(context) ~= "table" then
        error("context must be a table", 2)
    end

    local currentOutputRate = math.max(0, tonumber(context.currentOutputRate) or 0)
    local targetOutputRate = math.max(0, tonumber(context.targetOutputRate) or 0)
    local fieldPercent = math.max(0, math.min(100, tonumber(context.fieldPercent) or 0))
    local targetFieldPercent = math.max(0, math.min(100, tonumber(context.targetFieldPercent) or 0))
    local currentTemperature = math.max(0, tonumber(context.currentTemperature) or 0)
    local maxTemperature = math.max(0, tonumber(context.maxTemperature) or 0)
    local deltaTime = math.max(0, tonumber(context.deltaTime) or 0)
    local outputRampUpPerSecond = math.max(0, tonumber(context.outputRampUpPerSecond) or 0)

    if currentOutputRate > targetOutputRate then
        return {
            desiredOutputRate = targetOutputRate,
            delta = targetOutputRate - currentOutputRate,
            throttled = false,
            reason = "reducing_output",
        }
    end

    if targetOutputRate <= 0 then
        return {
            desiredOutputRate = 0,
            delta = -currentOutputRate,
            throttled = false,
            reason = currentOutputRate > 0 and "reducing_output" or "idle_output",
        }
    end

    if fieldPercent < targetFieldPercent then
        return {
            desiredOutputRate = currentOutputRate,
            delta = 0,
            throttled = true,
            reason = "waiting_for_field",
        }
    end

    if currentTemperature >= maxTemperature then
        return {
            desiredOutputRate = currentOutputRate,
            delta = 0,
            throttled = true,
            reason = "waiting_for_temperature",
        }
    end

    local maxIncrease = outputRampUpPerSecond * deltaTime
    local desiredOutputRate = currentOutputRate

    if maxIncrease > 0 then
        desiredOutputRate = math.min(targetOutputRate, currentOutputRate + maxIncrease)
    end

    local reason = desiredOutputRate < targetOutputRate and "ramping_output" or "at_target_output"

    return {
        desiredOutputRate = desiredOutputRate,
        delta = desiredOutputRate - currentOutputRate,
        throttled = false,
        reason = reason,
    }
end

return OutputController
