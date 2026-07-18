--[[
Test Suite for Reactor Controller

Run this to verify the controller works correctly without peripherals.
]]

local ReactorController = require("controller")

local function test(name, fn)
    local success, err = pcall(fn)
    if success then
        print("✓ " .. name)
    else
        print("✗ " .. name .. ": " .. tostring(err))
    end
end

-- ============================================================================
-- Configuration Tests
-- ============================================================================

print("\n=== Configuration Tests ===")

test("Valid configuration", function()
    local config = {
        minimumFieldPercent = 0.15,
        targetFieldPercent = 0.50,
        maximumTemperature = 8000,
        targetOutputFlux = 15000,
        outputRampSpeed = 0.05,
        autoInputFlux = true,
        maximumInputFlux = 50000,
    }
    local controller = ReactorController.new(config)
    assert(controller ~= nil, "Controller should be created")
end)

test("Default values are applied", function()
    local config = {}
    local controller = ReactorController.new(config)
    assert(controller ~= nil, "Controller should be created with defaults")
    assert(controller.config.minimumFieldPercent == 0.15)
    assert(controller.config.targetFieldPercent == 0.50)
end)

test("Invalid field percentages rejected", function()
    local config = {
        minimumFieldPercent = 0.50,
        targetFieldPercent = 0.15,  -- min > target, invalid
    }
    local controller, err = ReactorController.new(config)
    assert(controller == nil, "Should reject invalid config")
    assert(err ~= nil, "Should have error message")
end)

test("Configuration is copied, not referenced", function()
    local userConfig = { minimumFieldPercent = 0.15 }
    local controller = ReactorController.new(userConfig)
    userConfig.minimumFieldPercent = 0.99
    assert(controller.config.minimumFieldPercent == 0.15, "Config should be independent copy")
end)

-- ============================================================================
-- Update Tests
-- ============================================================================

print("\n=== Update Tests ===")

test("Basic update doesn't crash", function()
    local controller = ReactorController.new({
        minimumFieldPercent = 0.15,
        targetFieldPercent = 0.50,
        maximumTemperature = 8000,
        targetOutputFlux = 15000,
        outputRampSpeed = 0.05,
    })

    local reactorInfo = {
        fieldStrength = 50000,
        maxFieldStrength = 100000,
        temperature = 5000,
        fieldDrainRate = 3000,
    }

    local result = controller:update(0.05, reactorInfo, 3000, 5000)
    assert(result ~= nil)
    assert(result.inputFlux ~= nil)
    assert(result.outputFlux ~= nil)
    assert(result.emergencyShutdown == false)
end)

test("Returns numeric values", function()
    local controller = ReactorController.new({})
    local reactorInfo = {
        fieldStrength = 50000,
        maxFieldStrength = 100000,
        temperature = 5000,
        fieldDrainRate = 3000,
    }
    local result = controller:update(0.05, reactorInfo, 3000, 5000)

    assert(type(result.inputFlux) == "number")
    assert(type(result.outputFlux) == "number")
    assert(type(result.emergencyShutdown) == "boolean")
end)

test("Emergency shutdown on low field", function()
    local controller = ReactorController.new({
        minimumFieldPercent = 0.20,
        targetFieldPercent = 0.50,
    })

    local reactorInfo = {
        fieldStrength = 5000,
        maxFieldStrength = 100000,  -- 5% field
        temperature = 5000,
        fieldDrainRate = 3000,
    }

    local result = controller:update(0.05, reactorInfo, 3000, 5000)
    assert(result.emergencyShutdown == true, "Should trigger emergency shutdown")
    assert(controller:getEmergencyShutdownReason() ~= nil)
end)

test("Emergency shutdown on high temperature", function()
    local controller = ReactorController.new({
        maximumTemperature = 8000,
    })

    local reactorInfo = {
        fieldStrength = 50000,
        maxFieldStrength = 100000,
        temperature = 9000,  -- Over limit
        fieldDrainRate = 3000,
    }

    local result = controller:update(0.05, reactorInfo, 3000, 5000)
    assert(result.emergencyShutdown == true)
end)

test("Once in emergency, stays in emergency", function()
    local controller = ReactorController.new({
        minimumFieldPercent = 0.20,
    })

    -- First update: trigger emergency
    local result1 = controller:update(0.05, {
        fieldStrength = 5000,
        maxFieldStrength = 100000,
        temperature = 5000,
        fieldDrainRate = 3000,
    }, 3000, 5000)
    assert(result1.emergencyShutdown == true)

    -- Second update: field recovers, but still in emergency
    local result2 = controller:update(0.05, {
        fieldStrength = 60000,
        maxFieldStrength = 100000,
        temperature = 5000,
        fieldDrainRate = 3000,
    }, 3000, 5000)
    assert(result2.emergencyShutdown == true)
end)

test("Reset clears emergency shutdown", function()
    local controller = ReactorController.new({
        minimumFieldPercent = 0.20,
    })

    -- Trigger emergency
    controller:update(0.05, {
        fieldStrength = 5000,
        maxFieldStrength = 100000,
        temperature = 5000,
        fieldDrainRate = 3000,
    }, 3000, 5000)
    assert(controller.emergencyShutdown == true)

    -- Reset
    controller:reset()
    assert(not controller.emergencyShutdown)

    -- Verify normal operation resumes
    local result = controller:update(0.05, {
        fieldStrength = 50000,
        maxFieldStrength = 100000,
        temperature = 5000,
        fieldDrainRate = 3000,
    }, 3000, 5000)
    assert(result.emergencyShutdown == false)
end)

-- ============================================================================
-- Field Control Tests
-- ============================================================================

print("\n=== Field Control Tests ===")

test("Manual input mode respects target", function()
    local controller = ReactorController.new({
        autoInputFlux = false,
        targetInputFlux = 5000,
    })

    local reactorInfo = {
        fieldStrength = 50000,
        maxFieldStrength = 100000,
        temperature = 5000,
        fieldDrainRate = 3000,
    }

    local result = controller:update(0.05, reactorInfo, 3000, 5000)
    assert(result.inputFlux == 5000, "Manual input should use target value")
end)

test("Input respects maximum limit", function()
    local controller = ReactorController.new({
        autoInputFlux = true,
        maximumInputFlux = 10000,
    })

    local reactorInfo = {
        fieldStrength = 10000,  -- Very low field
        maxFieldStrength = 100000,
        temperature = 5000,
        fieldDrainRate = 50000,  -- Very high drain
    }

    local result = controller:update(0.05, reactorInfo, 3000, 5000)
    assert(result.inputFlux <= 10000, "Input should not exceed maximum")
end)

test("Input never goes negative", function()
    local controller = ReactorController.new({
        autoInputFlux = true,
        targetFieldPercent = 0.50,
    })

    local reactorInfo = {
        fieldStrength = 99000,  -- Very high field
        maxFieldStrength = 100000,
        temperature = 5000,
        fieldDrainRate = 0,  -- No drain
    }

    local result = controller:update(0.05, reactorInfo, 3000, 5000)
    assert(result.inputFlux >= 0, "Input should never be negative")
end)

-- ============================================================================
-- Output Control Tests
-- ============================================================================

print("\n=== Output Control Tests ===")

test("Output respects commanded target", function()
    local controller = ReactorController.new({
        targetOutputFlux = 10000,
        outputRampSpeed = 1.0,  -- Max ramp speed
    })

    -- Run for several updates with perfect conditions
    local reactorInfo = {
        fieldStrength = 60000,
        maxFieldStrength = 100000,
        temperature = 5000,
        fieldDrainRate = 3000,
    }

    for i = 1, 100 do
        controller:update(1.0, reactorInfo, 3000, 5000)
    -- Output should eventually reach target (or get close)
    end

    local result = controller:update(1.0, reactorInfo, 3000, 5000)
    assert(result.outputFlux <= 10000, "Output should not exceed target")
end)

test("Output is zero when not configured", function()
    local controller = ReactorController.new({
        targetOutputFlux = nil,  -- No output target
    })

    local reactorInfo = {
        fieldStrength = 50000,
        maxFieldStrength = 100000,
        temperature = 5000,
        fieldDrainRate = 3000,
    }

    local result = controller:update(0.05, reactorInfo, 3000, 5000)
    assert(result.outputFlux == 0, "Output should be zero when not configured")
end)

-- ============================================================================
-- Diagnostics Tests
-- ============================================================================

print("\n=== Diagnostics Tests ===")

test("Diagnostics accessible", function()
    local controller = ReactorController.new({})
    local reactorInfo = {
        fieldStrength = 50000,
        maxFieldStrength = 100000,
        temperature = 5000,
        fieldDrainRate = 3000,
    }
    controller:update(0.05, reactorInfo, 3000, 5000)

    local diags = controller:getDiagnostics()
    assert(diags ~= nil)
    assert(diags.state ~= nil)
    assert(diags.fieldPercent ~= nil)
    assert(diags.commandedInput ~= nil)
    assert(diags.allowedOutput ~= nil)
end)

test("Diagnostics field is accurate", function()
    local controller = ReactorController.new({})
    local reactorInfo = {
        fieldStrength = 30000,
        maxFieldStrength = 100000,  -- Should be 30%
        temperature = 5000,
        fieldDrainRate = 3000,
    }
    controller:update(0.05, reactorInfo, 3000, 5000)

    local diags = controller:getDiagnostics()
    assert(math.abs(diags.fieldPercent - 0.30) < 0.01, "Field percentage should be accurate")
end)

-- ============================================================================
-- Summary
-- ============================================================================

print("\n=== All tests complete ===")

