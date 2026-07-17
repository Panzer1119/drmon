-- controller.lua

local Controller = {}

-----------------------------------------------------------------------
-- Internal tuning constants
-----------------------------------------------------------------------

local FIELD_GAIN = 0.35          -- RF/t per 1% field error
local MIN_INPUT_FLUX = 0

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    elseif value > maxValue then
        return maxValue
    end

    return value
end

local function approach(current, target, maxIncrease)
    if target <= current then
    -- decreases are immediate
        return target
    end

    return math.min(current + maxIncrease, target)
end

-----------------------------------------------------------------------
-- Public
-----------------------------------------------------------------------

function Controller.compute(args)

    local reactor = args.reactor
    local config = args.config
    local deltaTime = args.deltaTime

    local context = {
        commandedInputFlux = args.context.commandedInputFlux or args.inputFlux,
        commandedOutputFlux = args.context.commandedOutputFlux or args.outputFlux,
        emergencyShutdownReason = nil
    }

    -------------------------------------------------------------------
    -- Reactor percentages
    -------------------------------------------------------------------

    local fieldPercent =
        (reactor.fieldStrength  * 100) / reactor.maxFieldStrength

    -------------------------------------------------------------------
    -- Emergency checks
    -------------------------------------------------------------------

    if fieldPercent < config.minFieldPercent then

        context.emergencyShutdownReason = "field"

        return {
            inputFlux = context.commandedInputFlux,
            outputFlux = context.commandedOutputFlux,
            emergencyShutdown = true,
            context = context
        }

    end

    if reactor.temperature > config.maxTemperature then

        context.emergencyShutdownReason = "temperature"

        return {
            inputFlux = context.commandedInputFlux,
            outputFlux = context.commandedOutputFlux,
            emergencyShutdown = true,
            context = context
        }

    end

    -------------------------------------------------------------------
    -- Output controller
    -------------------------------------------------------------------

    local desiredOutput = config.targetOutputFlux

    -- Don't increase output while shield is below target.
    if fieldPercent < config.targetFieldPercent then
        desiredOutput = math.min(
            desiredOutput,
            context.commandedOutputFlux
        )
    end

    local maxIncrease =
        config.outputRampSpeed * deltaTime

    local commandedOutput =
        approach(
            context.commandedOutputFlux,
            desiredOutput,
            maxIncrease
        )

    -------------------------------------------------------------------
    -- Input controller
    -------------------------------------------------------------------

    local commandedInput

    if config.autoInputFlux then

        local fieldError =
            config.targetFieldPercent - fieldPercent

        local correction =
            reactor.fieldDrainRate *
            (fieldError / 100) *
            FIELD_GAIN

        commandedInput =
            reactor.fieldDrainRate + correction

    else

        commandedInput =
            config.targetInputFlux

    end

    commandedInput =
        math.floor(math.max(
            MIN_INPUT_FLUX,
            commandedInput
        ))

    -------------------------------------------------------------------
    -- Save controller state
    -------------------------------------------------------------------

    context.commandedInputFlux = commandedInput
    context.commandedOutputFlux = commandedOutput

    -------------------------------------------------------------------
    -- Return
    -------------------------------------------------------------------

    return {
        inputFlux = commandedInput,
        outputFlux = math.floor(commandedOutput),
        emergencyShutdown = false,
        context = context
    }

end

return Controller
