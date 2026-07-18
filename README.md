# drmon reactor controller

A fresh ComputerCraft/CC:Tweaked Lua reactor controller for a Draconic Evolution reactor on Minecraft 1.21.1.

## Files

- `drmon/reactor_controller.lua`: lifecycle, persistence, telemetry, and the five-step update loop.
- `drmon/field_controller.lua`: field input regulation with instant upward correction and ramped downward trimming.
- `drmon/output_controller.lua`: output ramping that only increases while the field is healthy.

## Usage

Passing peripheral names is recommended, because it lets the controller recover when peripherals disconnect and come back.
If the reactor peripheral drops out, the controller holds the last known rates until the connection returns instead of making blind changes.
If either flow gate drops out while the controller is active, the controller requests an emergency shutdown, cuts any still-connected output gate to `0`, and remembers that the user still wanted the reactor running. Once both flow gates are back, it waits for the restart cooldown and then resumes the normal startup sequence automatically.

```lua
local ReactorController = require("drmon.reactor_controller")

local controller = ReactorController.new(
    "draconic_reactor_0",
    "flux_gate_0",
    "flux_gate_1",
    {
        targetFieldPercent = 55,
        minFieldPercent = 35,
        targetOutputRate = 2000000,
        maxTemperature = 7800,
        cutOffTemperature = 8200,
        rateRampPerSecond = 1000000,
        statePath = "/drmon/reactor_controller_state.txt",
    }
)

controller:start()

while true do
    local status = controller:update(0.5)

    print(string.format(
        "[%s] field=%.1f%% temp=%.0fC in=%d out=%d",
        status.controlStatus,
        status.fieldPercent,
        status.currentTemperature,
        status.currentInputRate,
        status.currentOutputRate
    ))

    sleep(0.5)
end
```

## Config

Required runtime config values:

| Key | Meaning |
| --- | --- |
| `targetFieldPercent` | Field target. Output will not ramp upward while the field is below this. |
| `minFieldPercent` | Hard shutdown threshold while running. |
| `targetOutputRate` | Desired production/export rate. |
| `maxTemperature` | Output will stop ramping upward at or above this temperature. |
| `cutOffTemperature` | Hard shutdown threshold while running. |
| `rateRampPerSecond` | Shared ramp for output increases and input decreases. |

Useful optional values:

| Key | Meaning |
| --- | --- |
| `outputRampPerSecond` | Override the output ramp without changing the shared rate. |
| `inputRampDownPerSecond` | Override the input trim speed without changing the shared rate. |
| `restartCooldownSeconds` | Cooldown after a stop before an automatic restart from flow-gate recovery is allowed. Default `10`. |
| `minInputRate` | Minimum field input while the controller is actively running or stopping. Clamped to at least `250000`. |
| `startupInputRate` | Charging input floor before activation. |
| `outputBoostCompensationRatio` | Extra field input added after an output increase. Default `0.5`. |
| `fieldResponseMultiplier` | Aggressiveness when the field is below target. |
| `fieldTrimMultiplier` | Aggressiveness when trimming excess field input. |
| `statePath` | Serialized controller state file. |

## API highlights

- `start()` / `stop()`: request reactor start or stop; the next `update` applies the lifecycle steps.
- `update(deltaTime)`: runs the control loop, manages charging/activation/shutdown, and applies both gates after all calculations are complete.
- `setConfig(partial)` plus targeted setters like `setTargetOutputRate(value)`.
- `getStatus()`: returns the current telemetry snapshot, including controller status, field/fuel/saturation percentages, gate rates, net positive rate, and peripheral health.
- `getLastStartedAt()`, `getLastStoppedAt()`, `getRestartCooldownRemainingSeconds()`, and `isRestartPending()` expose the persisted restart timing state.

Useful status strings from `getStatus().controlStatus`:

- `throttled_field`: output is being held because the field is below target.
- `throttled_temperature`: output is being held because temperature is too high to ramp further.
- `ramping_output`: output is climbing toward the user target.
- `at_target_output`: full target output is being produced.
- `starting`, `stopping`, `needs_fuel`, `shutdown_requested`, `restart_cooldown`, `refuel_shutdown`, `peripheral_error`.

`getStatus().lastShutdownReason` includes `flow_gate_connection_lost` when a flow gate disconnect triggered the shutdown path, and the status also includes `lastStartedAt`, `lastStoppedAt`, `restartPending`, and `restartCooldownRemainingSeconds`.
