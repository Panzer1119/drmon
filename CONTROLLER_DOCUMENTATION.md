# Draconic Evolution Reactor Controller Library

A production-quality, modular Lua library for controlling Draconic Evolution fusion reactors in CC:Tweaked (ComputerCraft: Tweaked).

## Overview

This library implements **pure control logic** only. It never directly accesses peripherals. The application using this library is responsible for:
- Reading reactor information
- Reading flux gate values
- Writing flux gate commands
- Performing emergency shutdowns

This separation of concerns makes the controller:
- **Testable** without peripherals
- **Reusable** in different applications
- **Predictable** with no I/O latency surprises
- **Safe** with explicit emergency shutdown requests

## Architecture

The controller is organized into focused modules:

```
controller/
├── init.lua              # Main ReactorController class
├── Config.lua            # Configuration validation
├── Constants.lua         # Tuning constants
├── Helpers.lua           # Utility functions
├── StateMachine.lua      # State management
├── FieldController.lua   # Shield field control
├── OutputController.lua  # Output ramping with adaptive limits
├── SaturationDetector.lua # Input saturation detection
└── Diagnostics.lua       # Diagnostics reporting
```

### Module Responsibilities

#### Config.lua
Validates user-provided configuration and applies sensible defaults. Ensures:
- All required fields are present
- All values are in valid ranges
- Internal consistency (e.g., minimum < target field strength)

#### Constants.lua
Centralized tuning parameters for:
- State machine hysteresis delays
- Proportional control gains
- Ramp speeds and margins
- Saturation detection thresholds
- Temperature margins

Modify these values to adjust controller responsiveness.

#### Helpers.lua
Common utilities:
- `clamp(value, min, max)` - Bound a value
- `lerp(a, b, t)` - Linear interpolation
- `adaptiveScale(value, minThresh, maxThresh, minMult, maxMult)` - Scaled interpolation
- `proportional(gain, error)` - Proportional control output
- `hysteresisThreshold()` - Hysteresis-based threshold crossing
- `ema()` - Exponential moving average filtering

#### StateMachine.lua
Explicit state management to make behavior predictable:
- **STABLE**: Field healthy, output can increase
- **RECOVERING**: Field below target, focusing on recovery
- **LIMITED**: Output at user limit or safety limit
- **SATURATED**: Input power is limited
- **EMERGENCY**: Shutdown condition triggered

States only change after configurable delay to prevent oscillation.

#### FieldController.lua
Controls input flux to maintain shield field strength:
1. **Baseline**: Uses `reactor.fieldDrainRate`
2. **Error correction**: Proportional to `(targetField - currentField)`
3. **Velocity damping**: Proportional to how fast field is falling

This keeps field near target while preventing oscillation.

#### OutputController.lua
Implements adaptive output limiting:
1. **Commanded output**: User's requested output (upper limit)
2. **Allowed output**: Controller's adaptive limit based on stability
3. **Safe output**: Highest output achieved so far

Key features:
- Immediate output reduction if system is stressed
- Gradual output increase when stable
- Increase speed depends on field margin (more margin = faster increase)
- Maintains memory of safe output achieved

#### SaturationDetector.lua
Detects when input power is limited:

**Case 1**: `maximumInputFlux` configured
- If input reaches limit and field still falling → saturated

**Case 2**: `maximumInputFlux` not configured
- Monitor behavior: input increasing but field not responding
- Confidence builds over time
- Decreases when field starts recovering
- Hysteresis prevents oscillation

#### Diagnostics.lua
Provides UI-friendly diagnostics:
- Current state and timers
- Field percentage and velocity
- Input/output commanded and actual values
- Saturation confidence
- Temperature status
- Shutdown reasons

## Control Strategy

### Priority Hierarchy

1. **Highest**: Never let the reactor explode
   - Emergency shutdown if field < minimum
   - Emergency shutdown if temperature > maximum

2. **Second**: Keep shield near target field strength
   - Field controller maintains target via proportional control
   - Velocity-based damping prevents oscillation

3. **Third**: Reach requested output flux
   - Output only increases when field is healthy
   - Speed depends on available margin
   - Adaptive limiting discovers maximum safe output

**Core principle**: Never sacrifice safety for performance.

### Field Maintenance

The field controller maintains shield strength through:

```
Input = FieldDrainRate + FieldErrorCorrection + VelocityCorrection
```

Where:
- **FieldDrainRate**: Baseline from reactor (what it needs to stay even)
- **FieldErrorCorrection**: Compensates if field is below target
- **VelocityCorrection**: Boosts input if field is falling rapidly

This prevents both oscillation and slow field decay.

### Output Discovery

The output controller gradually discovers the maximum safe output:

```
CurrentOutput = min(CommandedOutput, AllowedOutput)
```

**Allowed output adapts**:
- Increases slowly when stable (rate depends on field margin)
- Increases faster with plenty of shield reserve
- Increases slowly with minimal shield reserve
- Decreases immediately if system shows stress
- Remembers safe output achieved

This "learning" approach is safer than aggressively pushing output.

### Saturation Handling

When input power cannot keep up:
1. **Detection**: Confidence increases as input hits limit and field falls
2. **Response**: Output immediately reduces
3. **Recovery**: Confidence falls once field starts recovering
4. **Stability**: Hysteresis prevents rapid state changes

## Usage

### Basic Example

```lua
local ReactorController = require("controller")

-- Configuration
local config = {
    minimumFieldPercent = 0.15,
    targetFieldPercent = 0.50,
    maximumTemperature = 8000,
    targetOutputFlux = 15000,
    outputRampSpeed = 0.05,
    autoInputFlux = true,
    maximumInputFlux = 50000,
}

-- Create controller
local controller = ReactorController.new(config)

-- Main loop
local lastTime = os.clock()
while true do
    local currentTime = os.clock()
    local deltaTime = currentTime - lastTime
    lastTime = currentTime

    -- Read reactor state
    local reactorInfo = reactor.getReactorInfo()
    local inputFlux = inputFluxGate.getFlow()
    local outputFlux = outputFluxGate.getFlow()

    -- Update controller
    local result = controller:update(deltaTime, reactorInfo, inputFlux, outputFlux)

    -- Apply commands
    inputFluxGate.setFlowOverride(result.inputFlux)
    outputFluxGate.setFlowOverride(result.outputFlux)

    -- Handle emergency
    if result.emergencyShutdown then
        reactor.stopReactor()
        print("SHUTDOWN: " .. controller:getEmergencyShutdownReason())
        break
    end

    sleep(0.05)  -- 20 Hz update rate
end
```

### API Reference

#### ReactorController.new(config) → controller or (nil, error)
Creates a controller instance. Returns nil with error message if config is invalid.

#### controller:update(deltaTime, reactorInfo, inputFlux, outputFlux) → result
Main update function. Call regularly (20 Hz recommended).

Returns:
```lua
{
    inputFlux = number,              -- Recommended input (RF/t)
    outputFlux = number,             -- Recommended output (RF/t)
    emergencyShutdown = boolean      -- Whether to shut down immediately
}
```

#### controller:getDiagnostics() → diags
Returns current controller state suitable for UI display:
```lua
{
    state = "STABLE" | "RECOVERING" | "LIMITED" | "SATURATED" | "EMERGENCY",
    fieldPercent = number,
    fieldVelocity = number,
    commandedInput = number,
    allowedOutput = number,
    saturationConfidence = number,
    -- ... and more
}
```

#### controller:getEmergencyShutdownReason() → reason
Returns the reason for emergency shutdown (if any).

#### controller:reset()
Resets controller to initial state. Useful after emergency shutdown.

### Configuration

#### Required Fields
- `minimumFieldPercent` (0-1): Field shutdown threshold
- `targetFieldPercent` (0-1): Desired field strength
- `maximumTemperature` (°C): Temperature shutdown threshold

#### Output Control
- `targetOutputFlux` (RF/t): Desired output (or nil for no output)
- `outputRampSpeed` (0-1): Max increase as fraction of target per second

#### Input Control
- `autoInputFlux` (bool): Auto-calculate from field error (default: true)
- `targetInputFlux` (RF/t): Fixed input if autoInputFlux=false (default: 0)
- `maximumInputFlux` (RF/t): Optional input limit (nil = no limit)

### Recommended Configurations

#### Conservative (Safe Operation)
```lua
{
    minimumFieldPercent = 0.20,
    targetFieldPercent = 0.60,
    maximumTemperature = 7000,
    targetOutputFlux = 8000,
    outputRampSpeed = 0.02,
    autoInputFlux = true,
    maximumInputFlux = 40000,
}
```

#### Balanced (Default)
```lua
{
    minimumFieldPercent = 0.15,
    targetFieldPercent = 0.50,
    maximumTemperature = 8000,
    targetOutputFlux = 15000,
    outputRampSpeed = 0.05,
    autoInputFlux = true,
    maximumInputFlux = 50000,
}
```

#### Aggressive (High Output)
```lua
{
    minimumFieldPercent = 0.10,
    targetFieldPercent = 0.40,
    maximumTemperature = 8500,
    targetOutputFlux = 25000,
    outputRampSpeed = 0.10,
    autoInputFlux = true,
    maximumInputFlux = 80000,
}
```

## Testing

The controller can be tested without peripherals by directly calling `update()` with simulated reactor data:

```lua
local controller = ReactorController.new(config)

local reactorData = {
    fieldStrength = 50000,
    maxFieldStrength = 100000,
    temperature = 5000,
    fieldDrainRate = 3000,
}

local result = controller:update(0.05, reactorData, 3000, 5000)
assert(result.inputFlux >= 0)
assert(result.outputFlux >= 0)
```

## Performance Considerations

- **Update rate**: Design assumes 20 Hz updates. Works at other rates but timing values scale.
- **Memory**: ~2 KB for controller instance
- **CPU**: Minimal, designed for cooperative multitasking
- **Deterministic**: Same inputs produce same outputs (no randomness)

## Design Philosophy

This controller prioritizes:

1. **Safety** over performance
2. **Simplicity** over cleverness
3. **Predictability** over adaptability
4. **Readability** over brevity

It uses:
- Explicit state machines (not implicit behavior)
- Proportional control (not PID or fuzzy logic)
- Hysteresis (to prevent oscillation)
- Confidence values (to prevent single-sample noise)
- Conservative adaptive limiting (to safely discover safe operating point)

This makes the reactor feel like it's under reliable, predictable control rather than being pushed to limits.

## Troubleshooting

### Field won't increase
- Check `maximumInputFlux` isn't too low
- Verify reactor's `fieldDrainRate` is realistic
- Check temperature isn't near limit

### Output not reaching target
- Field may be too low (check `fieldPercent` in diagnostics)
- Reactor may be saturated (check `saturationConfidence`)
- Check `outputRampSpeed` isn't too conservative

### Reactor keeps shutting down
- Check `minimumFieldPercent` isn't too high
- Verify input power is sufficient for target output
- Check `maximumTemperature` isn't too low

### Rapid state changes
- Increase `STATE_CHANGE_DELAY` in Constants.lua
- Check for hardware latency (is reactor responding to commands?)
- Verify update rate is consistent

## License

This library is provided as-is for use with CC:Tweaked and Draconic Evolution.

