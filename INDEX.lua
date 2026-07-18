--[[
INDEX - Complete Library Overview

This file documents the complete structure of the Reactor Controller library
and explains where to find what you need.
]]

-- ============================================================================
-- DIRECTORY STRUCTURE
-- ============================================================================

--[[
drmon/
├── controller/                       # Main library (modular control logic)
│   ├── init.lua                     # Entry point - ReactorController class
│   ├── Config.lua                   # Configuration validation
│   ├── Constants.lua                # Tuning constants
│   ├── Helpers.lua                  # Utility functions
│   ├── StateMachine.lua             # State management
│   ├── FieldController.lua          # Input flux control
│   ├── OutputController.lua         # Output flux control
│   ├── SaturationDetector.lua       # Power starvation detection
│   └── Diagnostics.lua              # Diagnostics reporting
│
├── CONTROLLER_README.md             # Start here! Complete overview
├── CONTROLLER_DOCUMENTATION.md      # In-depth design documentation
├── QUICK_REFERENCE.lua              # One-page cheat sheet
├── CONTROLLER_EXAMPLE.lua           # Usage examples
├── CONTROLLER_TESTS.lua             # Test suite
├── FULL_APPLICATION_EXAMPLE.lua     # Complete app structure
└── INDEX.lua                        # This file
]]

-- ============================================================================
-- GETTING STARTED (READ IN THIS ORDER)
-- ============================================================================

--[[
1. START HERE:
   File: CONTROLLER_README.md
   Read: Overview, features, quick start, safety notes
   Time: 10 minutes

2. UNDERSTAND THE DESIGN:
   File: CONTROLLER_DOCUMENTATION.md
   Read: Architecture, control strategy, state machine, configuration
   Time: 20 minutes

3. INTEGRATE INTO YOUR PROJECT:
   File: QUICK_REFERENCE.lua or CONTROLLER_EXAMPLE.lua
   Look at: Code examples, typical patterns, presets
   Time: 15 minutes

4. TEST:
   File: CONTROLLER_TESTS.lua
   Run: lua CONTROLLER_TESTS.lua
   Verify: Controller works on your system

5. BUILD APPLICATION:
   File: FULL_APPLICATION_EXAMPLE.lua
   Reference: Complete app with displays, safety, logging
   Time: 30 minutes

6. DEPLOY:
   Copy controller/ folder to your ComputerCraft computer
   Use in your application as shown in examples
]]

-- ============================================================================
-- LIBRARY MODULES
-- ============================================================================

--[[
CONTROLLER/INIT.lua
  Main ReactorController class
  • Creates new controller instances
  • Main update() method
  • Emergency shutdown handling
  • getDiagnostics() and reset() methods
  Usage: local ReactorController = require("controller")
         local controller = ReactorController.new(config)

CONTROLLER/CONFIG.lua
  Configuration validation
  • Validates user configuration
  • Applies defaults
  • Checks consistency
  Usage: Called internally by ReactorController.new()

CONTROLLER/CONSTANTS.lua
  Tuning parameters
  • State machine delays
  • Control gains (proportional coefficients)
  • Ramp speeds and margins
  • Saturation thresholds
  Modify: Adjust behavior without changing code

CONTROLLER/HELPERS.lua
  Utility functions
  • clamp() - bound values
  • lerp() - interpolation
  • adaptiveScale() - scaled interpolation
  • proportional() - control math
  • hysteresisThreshold() - threshold crossing
  • ema() - moving averages
  Usage: Used throughout library

CONTROLLER/STATEMACHINE.lua
  State management
  • STABLE, RECOVERING, LIMITED, SATURATED, EMERGENCY states
  • State transitions with hysteresis
  • Force transitions for emergencies
  Usage: Called from main controller

CONTROLLER/FIELDCONTROLLER.lua
  Input flux control
  • Maintains field at target level
  • Proportional error correction
  • Velocity-based damping
  • Auto or manual input modes
  Usage: Calculates required input flux

CONTROLLER/OUTPUTCONTROLLER.lua
  Output flux control
  • Adaptive output limiting
  • Safe output discovery
  • Ramping with margin-based acceleration
  • Immediate reduction on stress
  Usage: Calculates maximum safe output

CONTROLLER/SATURATIONDETECTOR.lua
  Power starvation detection
  • Detects input-limited condition
  • Confidence-based decision making
  • Two detection modes (with/without max input)
  • Hysteresis to prevent oscillation
  Usage: Signals when input is the limiting factor

CONTROLLER/DIAGNOSTICS.lua
  Diagnostics reporting
  • Snapshots of all controller state
  • Formatted output for displays
  • Fields for UI display
  Usage: controller:getDiagnostics()
]]

-- ============================================================================
-- DOCUMENTATION FILES
-- ============================================================================

--[[
CONTROLLER_README.md
  Overview of the entire system
  • Features list
  • Quick start code
  • Architecture overview
  • API reference
  • Configuration guide
  • Presets (conservative, balanced, aggressive)
  • Safety notes
  Target: First-time users

CONTROLLER_DOCUMENTATION.md
  In-depth technical documentation
  • Module responsibilities
  • Control strategy in detail
  • Field maintenance algorithm
  • Output discovery algorithm
  • Saturation handling
  • State machine details
  • Complete API reference
  • Configuration reference
  • Testing guide
  • Troubleshooting
  Target: Developers, maintainers

QUICK_REFERENCE.lua
  One-page cheat sheet (this is code, not docs!)
  • Minimal example
  • Configuration fields
  • Public API summary
  • Typical integration pattern
  • Presets
  • Debugging tips
  Target: Quick lookup during development

CONTROLLER_EXAMPLE.lua
  Working code examples
  • Example 1: Basic usage
  • Example 2: With diagnostics display
  • Example 3: Conservative configuration
  • Example 4: Aggressive configuration
  • Example 5: Manual input mode
  Target: Code snippets to copy-paste

CONTROLLER_TESTS.lua
  Complete test suite
  • Configuration tests
  • Update tests
  • Emergency shutdown tests
  • Field control tests
  • Output control tests
  • Diagnostics tests
  Usage: Run to verify controller works
         lua CONTROLLER_TESTS.lua

FULL_APPLICATION_EXAMPLE.lua
  Complete application template
  • PeripheralManager - hardware access
  • DisplayManager - UI rendering
  • SafetyMonitor - event logging
  • ReactorMonitor - main application
  • Main loop
  Target: Building real applications
]]

-- ============================================================================
-- COMMON WORKFLOWS
-- ============================================================================

--[[
WORKFLOW: I just want to use the controller

1. Read CONTROLLER_README.md (10 min)
2. Copy code from QUICK_REFERENCE.lua (5 min)
3. Run CONTROLLER_TESTS.lua to verify (2 min)
4. Integrate into your application (30 min)

WORKFLOW: I want to understand how it works

1. Read CONTROLLER_README.md architecture section (5 min)
2. Read CONTROLLER_DOCUMENTATION.md fully (30 min)
3. Read source code in controller/ (20 min)
4. Run examples and tests (10 min)

WORKFLOW: I want to build a complete application

1. Review FULL_APPLICATION_EXAMPLE.lua (20 min)
2. Copy relevant modules (PeripheralManager, DisplayManager, etc)
3. Create configuration for your setup (10 min)
4. Test with CONTROLLER_TESTS.lua (5 min)
5. Deploy and monitor

WORKFLOW: Something isn't working

1. Check CONTROLLER_DOCUMENTATION.md troubleshooting (5 min)
2. Enable diagnostics display: controller:getDiagnostics() (10 min)
3. Review Constants.lua values (5 min)
4. Check reactor responds to flux gate commands (5 min)
5. Try conservative configuration (5 min)

WORKFLOW: I want to tune for my setup

1. Read Constants.lua (5 min)
2. Choose preset (conservative/balanced/aggressive) (5 min)
3. Adjust minimumFieldPercent and targetFieldPercent (5 min)
4. Adjust maximumTemperature (3 min)
5. Test slowly, increasing targetOutputFlux over time (30 min)
6. Monitor diagnostics.saturationConfidence for input limits (10 min)
]]

-- ============================================================================
-- KEY CONCEPTS
-- ============================================================================

--[[
FIELD PERCENTAGE
  Calculated from: fieldStrength / maxFieldStrength
  Represents shield health as 0.0 to 1.0
  Target should be 0.3-0.6 for stable operation

FIELD VELOCITY
  Change in field percentage per update
  Positive = field increasing (good)
  Negative = field decreasing (bad, controller increases input)
  Used for velocity-based damping

FLUX GATE
  Device that controls power flow
  Input flux gate: controls power INTO the reactor
  Output flux gate: controls power OUT OF the reactor
  Controller sets desired values; application writes them

SATURATION
  Condition where input power is limited
  Controller detects and reduces output as a result
  Two types: configured max input, or behavioral detection

STATE MACHINE
  STABLE: Normal operation, field healthy, output can increase
  RECOVERING: Field below target, recovering
  LIMITED: Output at limit (user request or safety)
  SATURATED: Input power insufficient
  EMERGENCY: Shutdown triggered

PROPORTIONAL CONTROL
  Output = Gain × Error
  Used for field error correction
  Simple, effective, doesn't overshoot
  Gain is the Constants (FIELD_ERROR_GAIN, etc.)

ADAPTIVE OUTPUT LIMITING
  Allowed output tracks between 0 and commanded output
  Increases slowly when stable (rate depends on field margin)
  Decreases immediately if system shows stress
  Maintains "safe output" memory of highest achieved

HYSTERESIS
  Delay before state changes
  Prevents rapid oscillation at threshold
  Uses STATE_CHANGE_DELAY to skip counts before changing states
]]

-- ============================================================================
-- TROUBLESHOOTING QUICK REFERENCE
-- ============================================================================

--[[
Problem: "Failed to create controller"
  → Check configuration syntax
  → Verify all required fields are present
  → See Config.lua for valid ranges

Problem: "Field won't increase"
  → Check maximumInputFlux isn't too low
  → Verify reactor.fieldDrainRate is realistic
  → Check temperature isn't near limit

Problem: "Output won't reach target"
  → Check diagnostics.state (should eventually be STABLE)
  → Look at diagnostics.fieldPercent (should be above target)
  → Check diagnostics.saturationConfidence (should be low)

Problem: "Reactor keeps shutting down"
  → minimumFieldPercent might be too high
  → Input power may be insufficient
  → maximumTemperature might be too low
  → Try conservative configuration

Problem: "Field drops rapidly"
  → Reactor drain rate might be misconfigured
  → Input power insufficient for requested output
  → Try reducing targetOutputFlux

Problem: "State changes too fast"
  → Increase STATE_CHANGE_DELAY in Constants.lua
  → Check that deltaTime is consistent (not huge jumps)
  → Verify reactor responds quickly to flux gate changes

Solution: Always check diagnostics!
  local diags = controller:getDiagnostics()
  This shows: state, field%, temp, input, output, saturation, etc.
]]

-- ============================================================================
-- API SUMMARY
-- ============================================================================

--[[
ReactorController = require("controller")
→ Returns the controller module

controller = ReactorController.new(config)
→ Creates a new controller instance
← Returns controller or (nil, error)

result = controller:update(deltaTime, reactorInfo, inputFlux, outputFlux)
← Returns {inputFlux=number, outputFlux=number, emergencyShutdown=boolean}

diags = controller:getDiagnostics()
← Returns diagnostics table with current state

reason = controller:getEmergencyShutdownReason()
← Returns shutdown reason or nil

controller:reset()
→ Clears emergency shutdown, resets to initial state
]]

-- ============================================================================
-- CONFIGURATION SUMMARY
-- ============================================================================

--[[
SAFETY (highest priority):
  minimumFieldPercent     Default: 0.15    Range: 0.0-1.0
    Triggers emergency shutdown if field drops below this

  maximumTemperature      Default: 8000    Range: >0
    Triggers emergency shutdown if temperature exceeds this

FIELD CONTROL:
  targetFieldPercent      Default: 0.50    Range: 0.0-1.0
    Controller tries to maintain field at this level

  autoInputFlux           Default: true    Bool
    true: calculate input from field error
    false: use fixed targetInputFlux

  targetInputFlux         Default: 0       Range: >=0
    Used if autoInputFlux=false

  maximumInputFlux        Default: nil     Range: >=0 or nil
    Optional limit on input power

OUTPUT CONTROL:
  targetOutputFlux        Default: nil     Range: >=0 or nil
    Desired output power (nil = no output control)

  outputRampSpeed         Default: 0.05    Range: 0.0-1.0
    Maximum increase per second as fraction of target

PRESETS:
  Conservative:  min_field=0.20, target=0.60, max_temp=7000, output=8000
  Balanced:      min_field=0.15, target=0.50, max_temp=8000, output=15000
  Aggressive:    min_field=0.10, target=0.40, max_temp=8500, output=25000
]]

-- ============================================================================
-- FILE CHECKLIST
-- ============================================================================

--[[
Library Files (in controller/ folder):
  ✓ init.lua                  Main ReactorController class
  ✓ Config.lua                Configuration validation
  ✓ Constants.lua             Tuning parameters
  ✓ Helpers.lua               Utility functions
  ✓ StateMachine.lua          State management
  ✓ FieldController.lua       Input control
  ✓ OutputController.lua      Output control
  ✓ SaturationDetector.lua    Power detection
  ✓ Diagnostics.lua           Diagnostics reporting

Documentation Files:
  ✓ CONTROLLER_README.md      Overview and quick start
  ✓ CONTROLLER_DOCUMENTATION.md  In-depth guide
  ✓ QUICK_REFERENCE.lua       One-page cheat sheet
  ✓ CONTROLLER_EXAMPLE.lua    Code examples
  ✓ CONTROLLER_TESTS.lua      Test suite
  ✓ FULL_APPLICATION_EXAMPLE.lua  Complete app template
  ✓ INDEX.lua                 This file
]]

print("Reactor Controller Library - Complete Index")
print("")
print("Documentation:")
print("  CONTROLLER_README.md       - Start here!")
print("  CONTROLLER_DOCUMENTATION.md - Full technical guide")
print("  QUICK_REFERENCE.lua        - Cheat sheet")
print("  CONTROLLER_EXAMPLE.lua     - Code examples")
print("  CONTROLLER_TESTS.lua       - Run tests")
print("  FULL_APPLICATION_EXAMPLE.lua - Complete app")
print("")

