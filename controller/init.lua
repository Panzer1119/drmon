--[[
Draconic Evolution Reactor Controller

A modular, object-oriented controller for CC:Tweaked to safely operate
a Draconic Evolution fusion reactor.

This library implements only control logic and never directly accesses peripherals.
The application using this library is responsible for:
- Reading reactor data via getReactorInfo()
- Reading flux gate values
- Writing flux gate commands
- Performing emergency shutdowns on command

Usage:
  local ReactorController = require("controller")
  local controller = ReactorController.new(config)

  while true do
    local result = controller:update(deltaTime, reactorInfo, inputFlux, outputFlux)
    -- Apply result.inputFlux and result.outputFlux
    -- If result.emergencyShutdown is true, shut down the reactor
  end

API:
  controller:update(deltaTime, reactorInfo, currentInputFlux, currentOutputFlux) -> result
  controller:getDiagnostics() -> diagnostics
  controller:getEmergencyShutdownReason() -> reason
]]

local moduleName = ...

local Config = require(moduleName .. ".Config")
local Constants = require(moduleName .. ".Constants")
local StateMachine = require(moduleName .. ".StateMachine")
local FieldController = require(moduleName .. ".FieldController")
local OutputController = require(moduleName .. ".OutputController")
local SaturationDetector = require(moduleName .. ".SaturationDetector")
local Diagnostics = require(moduleName .. ".Diagnostics")

local ReactorController = {}
ReactorController.__index = ReactorController

--[[
Creates a new reactor controller.

Parameters:
  config: configuration table (see Config.lua for valid fields)

Returns:
  controller object, or (nil, error) if config is invalid
]]
function ReactorController.new(userConfig)
    local config, err = Config.new(userConfig)
    if not config then
        return nil, err
    end

    local controller = {
        config = config,

        -- Subcontrollers
        stateMachine = StateMachine.new(),
        fieldController = FieldController.new(config),
        outputController = OutputController.new(config),
        saturationDetector = SaturationDetector.new(config),

        -- Safety
        emergencyShutdown = false,
        shutdownReason = nil,

        -- State tracking
        lastFieldPercent = 0.5,
        lastTemperature = 0,
        lastDeltaTime = 0,
        lastReactorInfo = nil,

        -- Statistics
        updateCount = 0,
    }

    setmetatable(controller, ReactorController)
    return controller
end

--[[
Main update function. Call this regularly (typically 20 times per second).

Parameters:
  deltaTime: seconds since last update
  reactorInfo: table with at least {temperature, fieldStrength, maxFieldStrength, fieldDrainRate, ...}
  currentInputFlux: current input flux gate output (RF/t)
  currentOutputFlux: current output flux gate output (RF/t)

Returns:
  result table:
    {
      inputFlux = number,        -- recommended input flux
      outputFlux = number,       -- recommended output flux
      emergencyShutdown = boolean -- whether to shut down immediately
    }
]]
function ReactorController:update(deltaTime, reactorInfo, currentInputFlux, currentOutputFlux)
    self.lastDeltaTime = deltaTime
    self.updateCount = self.updateCount + 1
    self.lastReactorInfo = reactorInfo

    -- Calculate field percentage
    local fieldPercent = 0
      if reactorInfo.maxFieldStrength and reactorInfo.maxFieldStrength > 0 then
        fieldPercent = reactorInfo.fieldStrength / reactorInfo.maxFieldStrength
    end
    self.lastFieldPercent = fieldPercent

    -- Store temperature for diagnostics
    self.lastTemperature = reactorInfo.temperature or 0

    -- ========================================================================
    -- SAFETY CHECKS: Emergency shutdown takes absolute priority
    -- ========================================================================

    -- Check minimum field
    if fieldPercent < self.config.minimumFieldPercent then
        if not self.emergencyShutdown then
            self:_triggerEmergencyShutdown("Field strength below minimum")
        end
    end

    -- Check maximum temperature
    if reactorInfo.temperature and reactorInfo.temperature > self.config.maximumTemperature then
        if not self.emergencyShutdown then
            self:_triggerEmergencyShutdown("Temperature exceeds maximum")
        end
    end

    -- If emergency shutdown is triggered, return it immediately
    if self.emergencyShutdown then
        return {
            inputFlux = 0,
            outputFlux = 0,
            emergencyShutdown = true,
        }
    end

    -- ========================================================================
    -- CONTROL LOGIC
    -- ========================================================================

    -- Update field controller (calculates desired input based on field error)
    local commandedInput = self.fieldController:update(reactorInfo, fieldPercent)

    -- Clamp input to maximum if configured
    if self.config.maximumInputFlux then
        commandedInput = math.min(commandedInput, self.config.maximumInputFlux)
    end

    -- Check if at max input
    local atMaxInput = false
    if self.config.maximumInputFlux then
        atMaxInput = math.abs(commandedInput - self.config.maximumInputFlux) < 0.1
    end

    -- Update saturation detector
    self.saturationDetector:update(
        deltaTime,
        fieldPercent,
        commandedInput,
        atMaxInput
    )
    local isSaturated = self.saturationDetector:isSaturated()

    -- Determine if we're in a stable state
    -- Stable = field above target, not saturated, temperature healthy
    local isStable = (fieldPercent >= self.config.targetFieldPercent) and not isSaturated
    and (reactorInfo.temperature <= self.config.maximumTemperature * Constants.TEMPERATURE_MARGIN)

    -- Update state machine
    local states = StateMachine.getStates()

    if isSaturated then
        StateMachine.tryTransition(self.stateMachine, states.SATURATED, Constants.STATE_CHANGE_DELAY)
    elseif fieldPercent < self.config.targetFieldPercent then
        StateMachine.tryTransition(self.stateMachine, states.RECOVERING, Constants.STATE_CHANGE_DELAY)
    elseif isStable then
        StateMachine.tryTransition(self.stateMachine, states.STABLE, Constants.STATE_CHANGE_DELAY)
    else
        StateMachine.tryTransition(self.stateMachine, states.LIMITED, Constants.STATE_CHANGE_DELAY)
    end

    -- Update output controller (adaptive output limiting)
    local commandedOutput = self.outputController:update(
        deltaTime,
        fieldPercent,
        isStable,
        isSaturated
    )

    -- ========================================================================
    -- RETURN COMMANDS
    -- ========================================================================

    return {
        inputFlux = commandedInput,
        outputFlux = commandedOutput,
        emergencyShutdown = false,
    }
end

--[[
Returns a diagnostics table suitable for UI display.
]]
function ReactorController:getDiagnostics()
    return Diagnostics.snapshot(self)
end

--[[
Returns the reason for emergency shutdown, if any.
]]
function ReactorController:getEmergencyShutdownReason()
    return self.shutdownReason
end

--[[
Resets the controller to initial state.
Useful after emergency shutdown or manual intervention.
]]
function ReactorController:reset()
    self.emergencyShutdown = false
    self.shutdownReason = nil
    self.saturationDetector:reset()
    self.outputController:reset()
    StateMachine.forceTransition(self.stateMachine, StateMachine.getStates().STABLE)
end

-- ============================================================================
-- PRIVATE METHODS
-- ============================================================================

--[[
Triggers emergency shutdown with a reason.
This should only be called internally from the control logic.
]]
function ReactorController:_triggerEmergencyShutdown(reason)
    self.emergencyShutdown = true
    self.shutdownReason = reason
    StateMachine.forceTransition(self.stateMachine, StateMachine.getStates().EMERGENCY)
end

return ReactorController

