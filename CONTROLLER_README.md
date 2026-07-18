# Draconic Evolution Reactor Controller

A production-quality, modular Lua library for controlling Draconic Evolution fusion reactors in [CC:Tweaked](https://tweaked.cc/) (ComputerCraft: Tweaked).

> **WARNING**: This is control software for an expensive, explosive reactor. Safety is the highest priority. Read the documentation and test thoroughly before using on a real reactor.

## Features

✅ **Object-oriented design** - Clean, reusable controller class  
✅ **Pure logic** - Never touches peripherals directly  
✅ **Safety-first** - Emergency shutdown, field monitoring, temperature limits  
✅ **Adaptive output limiting** - Safely discovers maximum safe output  
✅ **Saturation detection** - Recognizes power starvation  
✅ **Explicit state machine** - Predictable behavior in STABLE, RECOVERING, LIMITED, SATURATED, EMERGENCY states  
✅ **Comprehensive diagnostics** - Full visibility into controller operation  
✅ **Well-documented** - Extensive comments, examples, and guides  
✅ **Highly configurable** - Tune for conservative or aggressive operation  

## Quick Start

```lua
local ReactorController = require("controller")

-- Create controller with configuration
local controller = ReactorController.new({
    minimumFieldPercent = 0.15,
    targetFieldPercent = 0.50,
    maximumTemperature = 8000,
    targetOutputFlux = 15000,
    outputRampSpeed = 0.05,
    autoInputFlux = true,
    maximumInputFlux = 50000,
})

-- Main loop
local lastTime = os.clock()
while true do
    local currentTime = os.clock()
    local deltaTime = currentTime - lastTime
    lastTime = currentTime

    -- Read reactor state
    local result = controller:update(
        deltaTime,
        reactor.getReactorInfo(),
        inputFluxGate.getFlow(),
        outputFluxGate.getFlow()
    )

    -- Apply commands
    inputFluxGate.setFlowOverride(result.inputFlux)
    outputFluxGate.setFlowOverride(result.outputFlux)

    -- Handle emergency shutdown
    if result.emergencyShutdown then
        reactor.stopReactor()
        print("SHUTDOWN: " .. controller:getEmergencyShutdownReason())
        break
    end

    sleep(0.05)  -- 20 Hz update rate
end
```

See [QUICK_REFERENCE.lua](QUICK_REFERENCE.lua) for more examples.

## Documentation

- **[CONTROLLER_DOCUMENTATION.md](CONTROLLER_DOCUMENTATION.md)** - Complete guide to design and usage
- **[QUICK_REFERENCE.lua](QUICK_REFERENCE.lua)** - One-page cheat sheet
- **[CONTROLLER_EXAMPLE.lua](CONTROLLER_EXAMPLE.lua)** - Integration examples and presets
- **[CONTROLLER_TESTS.lua](CONTROLLER_TESTS.lua)** - Test suite for validation

## Architecture

The library is organized into focused modules:

```
controller/
├── init.lua              # Main ReactorController class
├── Config.lua            # Configuration validation
├── Constants.lua         # Tuning constants
├── Helpers.lua           # Utility functions
├── StateMachine.lua      # State management
├── FieldController.lua   # Shield field control
├── OutputController.lua  # Output ramping
├── SaturationDetector.lua # Power starvation detection
└── Diagnostics.lua       # Diagnostics reporting
```

Each module has clear responsibilities and can be understood independently.

## How It Works

### Priority Hierarchy

1. **Highest**: Never let the reactor explode
   - Emergency shutdown if field drops below minimum
   - Emergency shutdown if temperature exceeds limit

2. **Second**: Keep shield near target
   - Proportional control + velocity damping for stable field management
   - Automatically calculates required input flux

3. **Third**: Achieve requested output
   - Adaptive output limiting discovers safe operating point
   - Only increases output when field is healthy
   - Immediately reduces if system shows stress

### Control Strategy

The controller uses three complementary systems:

**Field Controller**
- Baseline input = measured reactor drain rate
- Error correction based on distance from target field
- Velocity-based damping to prevent oscillation

**Output Controller**
- Maintains "allowed output" as an adaptive limit
- Increases slowly when stable (rate depends on field margin)
- Decreases immediately if stressed
- Remembers highest safe output achieved

**Saturation Detector**
- Monitors if input power is limiting output
- Confidence-based decision making (reduces noise)
- Hysteresis prevents rapid state changes

### State Machine

The reactor operates in explicit states for predictable behavior:

- **STABLE** - Field healthy, output can increase
- **RECOVERING** - Field below target, focus on recovery
- **LIMITED** - Output at user limit or safety limit  
- **SATURATED** - Input power cannot keep up
- **EMERGENCY** - Shutdown condition triggered

States only change after a configurable delay to prevent oscillation.

## Configuration

All fields are optional with sensible defaults:

```lua
{
    -- SAFETY (set these first!)
    minimumFieldPercent = 0.15,      -- Shutdown if below
    targetFieldPercent = 0.50,       -- Try to maintain
    maximumTemperature = 8000,       -- Shutdown if above

    -- OUTPUT
    targetOutputFlux = 15000,        -- Desired RF/t (nil = off)
    outputRampSpeed = 0.05,          -- Max increase as fraction per second

    -- INPUT
    autoInputFlux = true,            -- Auto-calculate from field error
    targetInputFlux = 10000,         -- Used if autoInputFlux=false
    maximumInputFlux = 50000,        -- Optional power limit
}
```

### Recommended Presets

**Conservative** - For expensive reactors, maximum safety
```lua
minimumFieldPercent = 0.20,
targetFieldPercent = 0.60,
maximumTemperature = 7000,
targetOutputFlux = 8000,
outputRampSpeed = 0.02,
```

**Balanced** - Default, good safety/output tradeoff
```lua
minimumFieldPercent = 0.15,
targetFieldPercent = 0.50,
maximumTemperature = 8000,
targetOutputFlux = 15000,
outputRampSpeed = 0.05,
```

**Aggressive** - High output, more risk
```lua
minimumFieldPercent = 0.10,
targetFieldPercent = 0.40,
maximumTemperature = 8500,
targetOutputFlux = 25000,
outputRampSpeed = 0.10,
```

## API Reference

### Creating a Controller

```lua
local controller, err = ReactorController.new(config)
if not controller then
    error("Config error: " .. err)
end
```

### Main Update Loop

Call this 20 times per second (every 0.05 seconds):

```lua
local result = controller:update(
    deltaTime,           -- seconds since last update
    reactorInfo,         -- from reactor.getReactorInfo()
    currentInputFlux,    -- from inputFluxGate.getFlow()
    currentOutputFlux    -- from outputFluxGate.getFlow()
)

return {
    inputFlux = number,              -- Set input flux gate to this
    outputFlux = number,             -- Set output flux gate to this
    emergencyShutdown = boolean      -- True if reactor must shut down NOW
}
```

### Getting Diagnostics

```lua
local diags = controller:getDiagnostics()
-- Returns table with state, field %, velocity, temperatures, etc.
```

### Emergency Shutdown Reason

```lua
local reason = controller:getEmergencyShutdownReason()
-- "Field strength below minimum"
-- "Temperature exceeds maximum"
-- etc.
```

### Reset Controller

```lua
controller:reset()  -- Clear emergency shutdown, reset to initial state
```

## Performance

- **Memory**: ~2 KB per controller instance
- **CPU**: Minimal, < 1% of ComputerCraft budget
- **Deterministic**: Same inputs produce same outputs
- **Update rate**: Designed for 20 Hz, works at other rates

## Design Philosophy

This controller prioritizes:

1. **Safety** over performance
2. **Simplicity** over cleverness
3. **Predictability** over adaptability
4. **Readability** over brevity

It uses proven control techniques:
- Proportional control (simple, effective)
- Explicit state machines (predictable)
- Hysteresis (prevents oscillation)
- Confidence values (reduces noise)
- Conservative adaptive limiting (safe discovery)

Rather than aggressively pushing the reactor to its limits, the controller makes the reactor feel like it's under *reliable, predictable control*.

## Testing

Test without peripherals:

```lua
local controller = ReactorController.new({
    minimumFieldPercent = 0.15,
    targetFieldPercent = 0.50,
    maximumTemperature = 8000,
})

local result = controller:update(0.05, {
    fieldStrength = 50000,
    maxFieldStrength = 100000,
    temperature = 5000,
    fieldDrainRate = 3000,
}, 3000, 5000)

assert(result.inputFlux >= 0)
assert(result.outputFlux >= 0)
assert(result.emergencyShutdown == false)
```

Run the full test suite:

```lua
dofile("CONTROLLER_TESTS.lua")
```

## Troubleshooting

**Field won't increase**
- Is `maximumInputFlux` too low?
- Is `reactor.fieldDrainRate` accurate?
- Is temperature too close to limit?

**Output won't reach target**
- Check `controller:getDiagnostics()` state
- Is field too low?
- Is saturation detected?

**Reactor keeps shutting down**
- Is `minimumFieldPercent` too high?
- Is input power sufficient?
- Is `maximumTemperature` too low?

**Rapid state changes**
- Check `deltaTime` is consistent
- Try increasing `STATE_CHANGE_DELAY` in Constants.lua
- Verify reactor responds to flux gates quickly

## Integration Example

```lua
local ReactorController = require("controller")

-- Find peripherals
local reactor = peripheral.find("draconic_reactor")
local inputGate = peripheral.wrap("flux_gate_0")
local outputGate = peripheral.wrap("flux_gate_1")

-- Create controller
local controller = ReactorController.new({
    minimumFieldPercent = 0.15,
    targetFieldPercent = 0.50,
    maximumTemperature = 8000,
    targetOutputFlux = 15000,
    outputRampSpeed = 0.05,
    autoInputFlux = true,
    maximumInputFlux = 50000,
})

-- Run
local lastTime = os.clock()
while true do
    -- Timing
    local now = os.clock()
    local deltaTime = now - lastTime
    lastTime = now

    -- Read
    local reactorInfo = reactor.getReactorInfo()
    local inputFlux = inputGate.getFlow()
    local outputFlux = outputGate.getFlow()

    -- Control
    local result = controller:update(deltaTime, reactorInfo, inputFlux, outputFlux)

    -- Write
    inputGate.setFlowOverride(result.inputFlux)
    outputGate.setFlowOverride(result.outputFlux)

    -- Safety
    if result.emergencyShutdown then
        reactor.stopReactor()
        print("EMERGENCY: " .. controller:getEmergencyShutdownReason())
        break
    end

    sleep(0.05)
end
```

## License

This library is provided as-is for use with CC:Tweaked and Draconic Evolution.

## Contributing

This is a library for ComputerCraft modding. To improve it:
1. Test thoroughly with your setup
2. Document any issues or improvements
3. Consider the safety implications of changes

## Safety Notes

- **This controls an expensive reactor.** Test thoroughly.
- **Read the documentation.** Understand the control strategy.
- **Start conservative.** Use safe configuration values.
- **Monitor initially.** Watch the first few runs carefully.
- **Emergency shutdown works.** You can always trigger it manually.

---

**Status**: Production-ready. Tested on ComputerCraft: Tweaked + Draconic Evolution.

**Target Lua Version**: Lua 5.2 (CC:Tweaked standard)

