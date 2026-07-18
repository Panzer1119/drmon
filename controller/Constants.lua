--[[
Constants.lua - Tuning constants for the reactor controller.

These values are used throughout the controller for behavior tuning.
Modify these to adjust how aggressively the controller responds.
]]

local Constants = {
    -- State machine hysteresis (updates before state changes)
    STATE_CHANGE_DELAY = 5,

    -- Field controller: proportional gain for field error correction.
    -- Formula: errorCorrection = (targetPercent - currentPercent) * maxFieldStrength * FIELD_ERROR_GAIN
    -- Example: field 10% below target, maxFieldStrength = 2,000,000, gain = 0.5
    --          => +100,000 RF/t added on top of the baseline drain rate.
    -- Increase to react faster; decrease to reduce overshoot.
    FIELD_ERROR_GAIN = 0.25,

    -- Field controller: proportional gain for field velocity damping.
    -- Formula: velocityCorrection = |fieldVelocityPerUpdate| * maxFieldStrength * FIELD_VELOCITY_GAIN
    -- Applies only when the field is actively falling, to front-run the drop.
    -- Example: field falling 0.05%/update, maxFieldStrength = 2,000,000, gain = 1.5
    --          => +1,500 RF/t anticipatory boost.
    -- Increase to damp faster falls more aggressively.
    FIELD_VELOCITY_GAIN = 0.3,

    -- Output ramping: maximum increase per second (fraction of maxOutput)
    --OUTPUT_RAMP_SPEED_DEFAULT = 0.05,
    OUTPUT_RAMP_SPEED_DEFAULT = 0.005,

    -- Output ramping: minimum increase per ramp step
    OUTPUT_RAMP_MIN_STEP = 0.1,

    -- Saturation detection: minimum time at max input to trigger (seconds)
    SATURATION_DETECTION_TIME = 3.0,

    -- Saturation detection: confidence increase per update when detecting saturation
    SATURATION_CONFIDENCE_GAIN = 0.2,

    -- Saturation detection: confidence decrease per update when field recovering
    SATURATION_CONFIDENCE_LOSS = 0.1,

    -- Saturation detection: confidence threshold to declare input-limited
    SATURATION_THRESHOLD = 0.8,

    -- Field margin: how much above target to consider "plenty of reserve"
    FIELD_MARGIN_COMFORTABLE = 0.10,

    -- Field margin: how much above target to consider "minimal reserve"
    FIELD_MARGIN_TIGHT = 0.02,

    -- Output ramp: speed multiplier when shield is at comfortable margin
    RAMP_SPEED_COMFORTABLE = 1.0,

    -- Output ramp: speed multiplier when shield is at tight margin
    RAMP_SPEED_TIGHT = 0.2,

    -- Output ramp: speed when field is below target (conservative)
    RAMP_SPEED_RECOVERING = 0.05,

    -- Temperature: margin before emergency (as fraction of max, e.g., 0.95 = 95%)
    TEMPERATURE_MARGIN = 0.95,

    -- Update rate assumption (for saturation detection timing)
    UPDATE_RATE_HZ = 20,
}

return Constants

