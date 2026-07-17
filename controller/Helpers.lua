--[[
Helpers.lua - Utility functions used throughout the controller.
]]

local Helpers = {}

--[[
Clamps a value between min and max.
]]
function Helpers.clamp(value, min, max)
	if value < min then return min end
	if value > max then return max end
	return value
end

--[[
Linear interpolation between a and b by factor t (0-1).
]]
function Helpers.lerp(a, b, t)
	return a + (b - a) * t
end

--[[
Smoothly scales a value based on where it falls in a range.

Used for adaptive ramp speeds. For example:
- If value is at minThreshold, return minMultiplier
- If value is at maxThreshold, return maxMultiplier
- In between, interpolate smoothly

Returns minMultiplier if value <= minThreshold
Returns maxMultiplier if value >= maxThreshold
Interpolates between for values in the range.
]]
function Helpers.adaptiveScale(value, minThreshold, maxThreshold, minMultiplier, maxMultiplier)
	if value <= minThreshold then
		return minMultiplier
	end
	if value >= maxThreshold then
		return maxMultiplier
	end

	local t = (value - minThreshold) / (maxThreshold - minThreshold)
	return Helpers.lerp(minMultiplier, maxMultiplier, t)
end

--[[
Exponential moving average: updates an average with a new sample.

alpha: smoothing factor (0-1). Higher = more weight on new sample.
oldAverage: previous average (or nil for first sample)
newSample: new data point

Returns updated average.
]]
function Helpers.ema(alpha, oldAverage, newSample)
	if oldAverage == nil then
		return newSample
	end
	return oldAverage * (1 - alpha) + newSample * alpha
end

--[[
Calculates proportional control output: gain * error
]]
function Helpers.proportional(gain, error)
	return gain * error
end

--[[
Detects hysteresis: state only changes if threshold is crossed.

This prevents rapid oscillation at a threshold boundary.

currentValue: the measured value
threshold: the boundary
thresholdHysteresis: how far away from threshold the value must go
direction: "increasing" to detect crossing upward, "decreasing" for downward

Returns true if threshold should be considered crossed.
]]
function Helpers.hysteresisThreshold(currentValue, threshold, hysteresis, direction)
	if direction == "increasing" then
		return currentValue >= (threshold + hysteresis)
	elseif direction == "decreasing" then
		return currentValue <= (threshold - hysteresis)
	end
	return false
end

--[[
Formats a number as a percentage string.
]]
function Helpers.formatPercent(value, decimals)
	decimals = decimals or 2
	return string.format("%." .. decimals .. "f%%", value * 100)
end

--[[
Formats a number with commas for readability.
]]
function Helpers.formatNumber(value, decimals)
	decimals = decimals or 0
	return string.format("%." .. decimals .. "f", value)
end

--[[
Deep copy of a table (non-recursive).
Suitable for tables without nested tables.
]]
function Helpers.tableCopy(t)
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = v
	end
	return copy
end

return Helpers

