local Config = require("config")
local Gates = require("gates")
local Reactor = require("reactor")



local config = Config.load()

local reactor = Reactor.new()



local function updateState(info)

    if not info then
        return
    end

    local status = info.status

    if config.desiredState == "off" then

        if status == "running"
        or status == "warming_up" then

            reactor:stop()

        end

        return

    end

    if status == "cold"
    or status == "cooling" then

        reactor:charge()
        return

    end

    if status == "warming_up" then

        local energy = info.energySaturation / info.maxEnergySaturation
        local field = info.fieldStrength / info.maxFieldStrength

        if energy >= 0.5
        and field >= 0.5
        and info.temperature >= 2000 then

            reactor:activate()

        end

    end

end



local function controlLoop()

    while true do

        if not reactor.connected then

            reactor:connect()

        end

        local info = reactor:info()

        if info then

            print("Reactor Status: " .. textutils.serialize(info))
            updateState(info)

            local output = 0

            if info.status == "running" then

                local values =
                    Gates.calculate(

                        info.fieldStrength,
                        info.maxFieldStrength,
                        info.fieldDrainRate,

                        config.targetFieldPercent,
                        config.minFieldPercent,

                        info.temperature,
                        config.maxTemperature,

                        config.requestedOutputRate,

                        reactor.currentOutput,

                        config.outputRampPercent,
                        config.outputRampMinimum

                    )

                reactor.currentOutput = values.outputGate

                -- Input is applied first.
                reactor:setGates(
                    values.inputGate,
                    values.outputGate,
                    config.minimumInputRate
                )


            else

                reactor.currentOutput = 0

                local chargeInput = config.minimumInputRate

                if info.status == "warming_up" then

                    local configuredChargeRate = tonumber(config.chargeRate)

                    if configuredChargeRate then
                        chargeInput = math.max(0, configuredChargeRate)
                    end

                end

                reactor:setGates(chargeInput, 0, 0)

            end

        end

        sleep(config.loopDelay)

    end

end



parallel.waitForAny(controlLoop)
