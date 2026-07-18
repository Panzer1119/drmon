--[[
INSTALLATION AND DEPLOYMENT GUIDE

Instructions for installing and deploying the Reactor Controller library
to your CC:Tweaked computer.
]]

-- ============================================================================
-- INSTALLATION
-- ============================================================================

--[[
There are two ways to install the Reactor Controller:

METHOD 1: DIRECT FOLDER COPY (Recommended)

1. On your PC/Mac/Linux:
   - Copy the entire 'controller/' folder to your CC:Tweaked world

2. In CC:Tweaked:
   - Create a directory: mkdir /controller
   - Copy all files from controller/ folder into it

3. Usage:
   local ReactorController = require("controller")
   This will automatically find the init.lua file

METHOD 2: CUSTOM PATH

If you want the controller in a different location:

1. Copy controller/ folder to your desired location

2. In your code, adjust the require path:
   local ReactorController = require("path/to/controller")

METHOD 3: INDIVIDUAL COMPONENT EXTRACTION

If you only want specific modules:

1. Copy individual files from controller/
2. Adjust require() statements in each file
3. Note: Not recommended - better to keep the whole folder structure
]]

-- ============================================================================
-- FOLDER STRUCTURE (as it should appear in CC:Tweaked)
-- ============================================================================

--[[
Computer
├── controller/                          (copy this entire folder)
│   ├── init.lua                        (main module)
│   ├── Config.lua
│   ├── Constants.lua
│   ├── Helpers.lua
│   ├── StateMachine.lua
│   ├── FieldController.lua
│   ├── OutputController.lua
│   ├── SaturationDetector.lua
│   └── Diagnostics.lua
│
└── my_reactor_app.lua                  (your application)
    OR in a folder:
    apps/
    └── reactor_control.lua
]]

-- ============================================================================
-- BASIC DEPLOYMENT CHECKLIST
-- ============================================================================

--[[
□ Copy controller/ folder to computer
□ Update any require() paths if needed
□ Verify peripherals are named correctly:
  □ "draconic_reactor"
  □ "flux_gate_0" (or adjust names in code)
  □ "flux_gate_1" (or adjust names in code)
□ Create initial configuration
□ Add emergency shutdown handling
□ Test with conservative configuration first
□ Monitor diagnostics during first runs
□ Gradually increase targetOutputFlux over time
]]

-- ============================================================================
-- QUICK TEST ON TARGET COMPUTER
-- ============================================================================

--[[
Once installed, test on the CC:Tweaked computer:

1. Create a test script (e.g., test.lua):

   local ReactorController = require("controller")

   local config = {
       minimumFieldPercent = 0.15,
       targetFieldPercent = 0.50,
       maximumTemperature = 8000,
   }

   local controller = ReactorController.new(config)
   print("✓ Controller created successfully")

   -- Test update
   local result = controller:update(0.05, {
       fieldStrength = 50000,
       maxFieldStrength = 100000,
       temperature = 5000,
       fieldDrainRate = 3000,
   }, 3000, 5000)

   print("✓ Controller update successful")
   print("  Input: " .. result.inputFlux)
   print("  Output: " .. result.outputFlux)

2. Run: lua test.lua

3. If you see "✓" marks, installation is successful!
]]

-- ============================================================================
-- COMMON INSTALLATION ISSUES
-- ============================================================================

--[[
ERROR: "Cannot find module"
  → Verify controller/ folder is in the same directory as your script
  → Check folder name spelling
  → Try absolute path: require("/controller")

ERROR: "module 'controller.Config' not found"
  → Make sure all 9 files are in the controller/ folder
  → Files should be: init.lua, Config.lua, Constants.lua, etc.

ERROR: "peripheral 'draconic_reactor' not found"
  → Make sure reactor is adjacent to the computer
  → Check the peripheral name with: peripherals.getNames()
  → Adjust names in your application code

ERROR: lua.exe: ...
  → You're trying to run on your PC
  → Must run IN ComputerCraft world, not on your computer
  → Place .lua files in world folder first
]]

-- ============================================================================
-- CC:TWEAKED SPECIFIC NOTES
-- ============================================================================

--[[
This library is designed for CC:Tweaked specifically:

✓ Lua 5.2 compatible
✓ Uses standard library functions only (no external dependencies)
✓ Peripheral API compatible
✓ os.clock() for timing
✓ sleep() for delays

Works with:
✓ ComputerCraft: Tweaked 1.94+
✓ Draconic Evolution mod
✓ Flux Gates (advanced)

Does NOT require:
✗ Any external Lua libraries
✗ Custom peripherals (standard flux gates work)
✗ Special ComputerCraft tweaks
]]

-- ============================================================================
-- PERIPHERAL DISCOVERY
-- ============================================================================

--[[
To find peripherals on your computer, create this script:

  -- list_peripherals.lua
  print("Available peripherals:")
  for _, name in ipairs(peripheral.getNames()) do
      local p = peripheral.wrap(name)
      print("  " .. name .. " (" .. peripheral.getType(name) .. ")")
  end

  -- Available types:
  -- draconic_reactor = Draconic Evolution Reactor
  -- flux_gate = Advanced Flux Gate (used for control)

Expected setup:
  - 1x draconic_reactor
  - 2x flux_gate (one for input, one for output)
  - Computer with wired modem to peripherals
]]

-- ============================================================================
-- FIRST RUN PROCEDURE
-- ============================================================================

--[[
1. PREPARE
   □ Ensure reactor has good field (>50%)
   □ Ensure reactor is at low temperature
   □ Set flux gates to 0 with: gate.setFlowOverride(0)

2. START WITH CONSERVATIVE CONFIG
   □ minimumFieldPercent = 0.20 (high, safe)
   □ targetFieldPercent = 0.60 (high, stable)
   □ targetOutputFlux = 5000 (low, safe)
   □ maximumInputFlux = 30000 (limited)

3. RUN APPLICATION
   □ Watch console output
   □ Monitor reactor display
   □ Watch field percentage - should gradually increase

4. CHECK DIAGNOSTICS
   □ diags.state should be "STABLE" or "RECOVERING"
   □ diags.fieldPercent should gradually approach target
   □ diags.temperature should stay stable

5. IF PROBLEMS:
   □ Stop immediately (Ctrl+T)
   □ Reset flux gates: setFlowOverride(0)
   □ Check diagnostics
   □ Try even more conservative values
   □ Verify reactor isn't already struggling

6. GRADUALLY INCREASE
   □ After 30 seconds of stable operation:
     Increase targetOutputFlux by 1000
   □ Wait 1 minute, observe
   □ Repeat until reaching desired output
   □ Or until saturation detected

7. LONG-TERM
   □ Monitor diagnostics regularly
   □ Check saturation confidence
   □ Watch field percentage trend
   □ Monitor temperature trend
]]

-- ============================================================================
-- PRODUCTION DEPLOYMENT
-- ============================================================================

--[[
Once tested and stable, for production use:

1. CREATE STARTUP SCRIPT
   File: /startup.lua

   -- Load and run reactor control on startup
   shell.run("path/to/reactor_app.lua")

2. ADD LOGGING
   Save events to a file for later review
   Include timestamps and state changes

3. ADD REDUNDANCY
   Monitor for hung processes
   Have fallback shutdown mechanism
   Consider secondary computer backup

4. DOCUMENT CONFIGURATION
   Keep written record of:
   - Configuration values used
   - Why those values chosen
   - Any anomalies or issues
   - Performance achieved

5. MONITORING
   Regular checks:
   - Controller is running
   - No emergency shutdowns recently
   - Field percentage stable
   - Output at expected level
   - Temperature normal
]]

-- ============================================================================
-- UNINSTALLATION
-- ============================================================================

--[[
To remove the controller:

1. Stop the running application (Ctrl+T)
2. Delete the controller/ folder: rm -r controller/
3. Delete any application files: rm reactor_app.lua
4. Optional: Reset flux gates to 0 (safety)
]]

-- ============================================================================
-- SUPPORT AND DEBUGGING
-- ============================================================================

--[[
If you encounter issues:

1. CHECK THE DOCUMENTATION
   - CONTROLLER_README.md - Overview
   - CONTROLLER_DOCUMENTATION.md - Detailed guide
   - QUICK_REFERENCE.lua - Quick answers

2. RUN THE TEST SUITE
   lua CONTROLLER_TESTS.lua
   Confirms library works correctly

3. ENABLE DIAGNOSTICS
   local diags = controller:getDiagnostics()
   Check: state, fieldPercent, temperature, saturation

4. VERIFY HARDWARE
   - Reactor responds: reactor.stopReactor() then stopReactor()
   - Input gate works: gate.setFlowOverride(1000) then setFlowOverride(0)
   - Output gate works: same as input

5. CHECK CONSTANTS
   See controller/Constants.lua for tuning parameters
   Adjust if needed for your setup

6. TRY CONSERVATIVE CONFIG
   Set all safety values very high (e.g., minimumFieldPercent=0.30)
   Set output very low (e.g., targetOutputFlux=1000)
   This isolates issues vs. actual control problems
]]

print("Reactor Controller - Installation Guide Ready")
print("See CONTROLLER_README.md to begin!")

