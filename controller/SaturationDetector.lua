--[[
SaturationDetector.lua - Detects when reactor input power is saturated.

There are two cases:

Case 1: maximumInputFlux is configured
  If commanded input reaches the limit and field continues falling,
  the controller is input-limited.

Case 2: maximumInputFlux is not configured
  Monitor behavior over time:
  - Input command increases
  - Field continues decreasing
  This suggests power starvation.

Uses a confidence system to avoid single-update noise:
- Confidence increases when evidence of saturation appears
- Confidence decreases when field starts recovering
- Hysteresis prevents oscillation
]]

local relativePath = fs.getDir(select(2,...) or ""):gsub("^"..fs.getDir(shell.getRunningProgram()):gsub("([%.%+%-%*%?%[%]%^%$%(%)])","%%%1").."/?","")

local SaturationDetector = {}
local Helpers = require(relativePath .. ".Helpers")
local Constants = require(relativePath .. ".Constants")

--[[
Creates a new saturation detector.
]]
function SaturationDetector.new(config)
	local detector = {
		config = config,
		confidence = 0,
		timeAtMaxInput = 0,
		maxInputCommandedThisSession = 0,
		fieldWasIncreasing = false,
		lastFieldPercent = nil,
	}
	return detector
end

--[[
Updates saturation detection based on reactor state.

Returns confidence (0-1) that the reactor is input-saturated.

Parameters:
- deltaTime: seconds since last update
- fieldPercent: current field percentage (0-1)
- commandedInput: current input command (RF/t)
- atMaxInput: whether input is at its maximum
]]
function SaturationDetector.update(detector, deltaTime, fieldPercent, commandedInput, atMaxInput)
	-- Case 1: maximumInputFlux is configured
	if detector.config.maximumInputFlux ~= nil then
		if atMaxInput and fieldPercent < detector.config.targetFieldPercent then
			-- Commanding max input but field still falling = saturated
			detector.confidence = math.min(1, detector.confidence + deltaTime / Constants.SATURATION_DETECTION_TIME)
		else
			-- Either not at max or field is recovering = not saturated
			detector.confidence = math.max(0, detector.confidence - deltaTime * Constants.SATURATION_CONFIDENCE_LOSS)
		end
	else
		-- Case 2: maximumInputFlux not configured, use behavioral detection
		detector.maxInputCommandedThisSession = math.max(detector.maxInputCommandedThisSession, commandedInput)

		local fieldIncreasing = false
		if detector.lastFieldPercent ~= nil then
			fieldIncreasing = fieldPercent > detector.lastFieldPercent
		end

		-- Evidence of saturation:
		-- - We're increasing input beyond what we've tried before
		-- - But field is not responding (decreasing or flat)
		if commandedInput >= detector.maxInputCommandedThisSession * 0.95 and not fieldIncreasing then
			detector.timeAtMaxInput = detector.timeAtMaxInput + deltaTime
			if detector.timeAtMaxInput > Constants.SATURATION_DETECTION_TIME then
				detector.confidence = math.min(1, detector.confidence + deltaTime * Constants.SATURATION_CONFIDENCE_GAIN)
			end
		else
			detector.timeAtMaxInput = 0
		end

		-- If field starts recovering, confidence falls
		if fieldIncreasing then
			detector.confidence = math.max(0, detector.confidence - deltaTime * Constants.SATURATION_CONFIDENCE_LOSS)
		end
	end

	detector.lastFieldPercent = fieldPercent
	return detector.confidence
end

--[[
Returns true if confidence is high enough to declare saturation.
]]
function SaturationDetector.isSaturated(detector)
	return detector.confidence >= Constants.SATURATION_THRESHOLD
end

--[[
Returns the current confidence (0-1).
]]
function SaturationDetector.getConfidence(detector)
	return detector.confidence
end

--[[
Resets saturation detection state.
Useful for controller reset or when circumstances change significantly.
]]
function SaturationDetector.reset(detector)
	detector.confidence = 0
	detector.timeAtMaxInput = 0
	detector.maxInputCommandedThisSession = 0
	detector.fieldWasIncreasing = false
	detector.lastFieldPercent = nil
end

return SaturationDetector

