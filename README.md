# drmon

ComputerCraft / CC:Tweaked Lua modules for controlling a Draconic Evolution reactor.

## Reactor controller

```lua
local drmon = require("drmon")

local controller = drmon.ReactorController.new(
    peripheral.wrap("back"),
    peripheral.wrap("left"),
    peripheral.wrap("right"),
    {
        targetFieldPercent = 55,
        minFieldPercent = 20,
        targetOutputRate = 5000000,
        maxTemperature = 7500,
        cutOffTemperature = 7800,
        outputRampRate = 1000000,
        inputReductionRampRate = 500000,
        minimumInputRate = 250000,
        preemptiveInputRatio = 0.5,
        fieldRecoveryWindow = 10,
        statePath = "drmon/reactor-a.state",
    }
)

controller:start()

local lastUpdate = os.epoch("utc")

while true do
    local now = os.epoch("utc")
    local deltaTime = (now - lastUpdate) / 1000
    lastUpdate = now

    local telemetry = controller:update(deltaTime)
    print(telemetry.controlStatus, telemetry.currentInputRate, telemetry.currentOutputRate)

    sleep(0.25)
end
```

## Behavior

1. The controller always enables flow gate override mode and seeds the override from the current live flow so a reboot does not cause a sudden spike.
2. While running, input increases immediately when the field needs help, output only ramps upward, and input reductions are ramp-limited.
3. Output increases are paired with a preemptive input boost so a target increase does not leave the field exposed.
4. The controller stores its desired run state, config, and last commanded rates with `textutils.serialize`.

## Public API

- `ReactorController.new(reactor, inputGate, outputGate, config)`
- `controller:start()`
- `controller:stop()`
- `controller:update(deltaTime)`
- `controller:setConfig(overrides)`
- `controller:getTelemetry()`
- `controller:getControlStatus()`
- `controller:getState()`
- `controller:getFieldPercent()`
- `controller:getEnergySaturationPercent()`
- `controller:getFuelPercent()`
- `controller:getFuelUsageRate()`
- `controller:getCurrentTemperature()`
- `controller:getCurrentInputRate()`
- `controller:getCurrentGenerationRate()`
- `controller:getCurrentOutputRate()`
- `controller:getTargetOutputRate()`
- `controller:getNetPositiveRate()`
- `controller:getFieldDrainRate()`
- `controller:getReactorInfo()`

## Config

- `targetFieldPercent`: output will not ramp upward until the field is at or above this percentage.
- `minFieldPercent`: the controller shuts the reactor down if the running field drops below this percentage.
- `targetOutputRate`: requested output gate rate.
- `maxTemperature`: output increases pause above this temperature.
- `cutOffTemperature`: the controller shuts the reactor down above this temperature.
- `outputRampRate`: maximum upward output change per second.
- `inputReductionRampRate`: maximum downward input change per second.
- `minimumInputRate`: minimum input gate rate while the controller is managing an active or starting reactor. It cannot be set below `250000`.
- `preemptiveInputRatio`: extra input added when output ramps upward.
- `fieldRecoveryWindow`: seconds used by the field controller when estimating how quickly it should move back to target.
- `statePath`: serialized controller state path.
