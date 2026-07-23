local M = {}


function M.clamp(value, min, max)

    if value < min then
        return min
    elseif value > max then
        return max
    end

    return value
end



function M.approach(
    current,
    target,
    percentageStep,
    minimumStep,
    maximumStep
)

    local difference = target - current

    if difference == 0 then
        return current
    end


    local step = math.max(
        math.abs(current) * percentageStep,
        minimumStep
    )

    if type(maximumStep) == "number" then
        step = math.min(step, math.max(0, maximumStep))
    end


    step = math.min(
        step,
        math.abs(difference)
    )


    if difference > 0 then
        return current + step
    end

    return current - step
end


return M
