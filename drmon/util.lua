local Util = {}

function Util.assertMethod(object, methodName, label)
    assert(type(object) == "table", ("%s must be a wrapped peripheral"):format(label or "Object"))
    assert(type(object[methodName]) == "function", ("%s is missing method %s"):format(label or "Object", methodName))
end

function Util.clamp(value, minValue, maxValue)
    assert(type(value) == "number", "value must be a number")
    if value < minValue then
        return minValue
    end

    if value > maxValue then
        return maxValue
    end

    return value
end

function Util.copy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}

    for key, nestedValue in pairs(value) do
        result[key] = Util.copy(nestedValue)
    end

    return result
end

function Util.merge(base, overrides)
    local result = Util.copy(base or {})

    for key, value in pairs(overrides or {}) do
        if type(value) == "table" and type(result[key]) == "table" then
            result[key] = Util.merge(result[key], value)
        else
            result[key] = Util.copy(value)
        end
    end

    return result
end

function Util.normalizeStatus(status)
    if type(status) ~= "string" or status == "" then
        return "unknown"
    end

    return string.lower(status)
end

function Util.percent(part, whole)
    if type(part) ~= "number" or type(whole) ~= "number" or whole <= 0 then
        return 0
    end

    return (part / whole) * 100
end

function Util.roundRate(value)
    if type(value) ~= "number" then
        return 0
    end

    return math.floor(math.max(value, 0) + 0.5)
end

return Util
