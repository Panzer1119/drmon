local FieldRateController = require("drmon.controllers.field_rate_controller")
local FlowGateAdapter = require("drmon.flow_gate_adapter")
local OutputRateController = require("drmon.controllers.output_rate_controller")
local Persistence = require("drmon.persistence")
local Util = require("drmon.util")

local ReactorController = {}
ReactorController.__index = ReactorController

local DEFAULT_CONFIG = {
    targetFieldPercent = 55,
    minFieldPercent = 20,
    targetOutputRate = 0,
    maxTemperature = 7500,
    cutOffTemperature = 7800,
    outputRampRate = 1000000,
    inputReductionRampRate = 500000,
    minimumInputRate = 250000,
    preemptiveInputRatio = 0.5,
    fieldRecoveryWindow = 10,
    statePath = "drmon/reactor-controller.state",
}

local function assertNumber(name, value, minimum)
    assert(type(value) == "number", ("%s must be a number"):format(name))

    if minimum ~= nil then
        assert(value >= minimum, ("%s must be at least %s"):format(name, tostring(minimum)))
    end
end

local function assertPercent(name, value)
    assertNumber(name, value)
    assert(value >= 0 and value <= 100, ("%s must be between 0 and 100"):format(name))
end

local function resolvePeripheral(candidate, label)
    if type(candidate) == "string" then
        local wrapped = peripheral.wrap(candidate)
        assert(wrapped ~= nil, ("failed to wrap %s peripheral %s"):format(label, candidate))
        return wrapped
    end

    assert(type(candidate) == "table", ("%s must be a wrapped peripheral or peripheral name"):format(label))
    return candidate
end

local function validateConfig(config)
    assertPercent("targetFieldPercent", config.targetFieldPercent)
    assertPercent("minFieldPercent", config.minFieldPercent)
    assert(config.minFieldPercent <= config.targetFieldPercent, "minFieldPercent must not be higher than targetFieldPercent")

    assertNumber("targetOutputRate", config.targetOutputRate, 0)
    assertNumber("maxTemperature", config.maxTemperature, 0)
    assertNumber("cutOffTemperature", config.cutOffTemperature, 0)
    assert(config.maxTemperature <= config.cutOffTemperature, "maxTemperature must not be higher than cutOffTemperature")

    assertNumber("outputRampRate", config.outputRampRate, 0)
    assertNumber("inputReductionRampRate", config.inputReductionRampRate, 0)
    assertNumber("minimumInputRate", config.minimumInputRate, 250000)
    assertNumber("preemptiveInputRatio", config.preemptiveInputRatio, 0)
    assertNumber("fieldRecoveryWindow", config.fieldRecoveryWindow, 0.1)

    assert(type(config.statePath) == "string" and config.statePath ~= "", "statePath must be a non-empty string")
end

function ReactorController.new(reactorPeripheral, inputGatePeripheral, outputGatePeripheral, config)
    local inputConfig = config or {}
    local statePath = inputConfig.statePath or DEFAULT_CONFIG.statePath
    local store = Persistence.new(statePath)
    local storedState = store:load() or {}
    local storedConfig = storedState.config or {}

    local mergedConfig = Util.merge(DEFAULT_CONFIG, storedConfig)
    mergedConfig = Util.merge(mergedConfig, inputConfig)
    validateConfig(mergedConfig)

    local self = setmetatable({
        reactor = resolvePeripheral(reactorPeripheral, "reactor"),
        inputGate = FlowGateAdapter.new(resolvePeripheral(inputGatePeripheral, "input flow gate"), "Input flow gate"),
        outputGate = FlowGateAdapter.new(resolvePeripheral(outputGatePeripheral, "output flow gate"), "Output flow gate"),
        config = mergedConfig,
        store = store,
        fieldController = FieldRateController.new(),
        outputController = OutputRateController.new(),
        desiredEnabled = false,
        controlStatus = "stopped",
        lastTelemetry = nil,
        lastReactorInfo = nil,
        lastUpdateEpoch = nil,
        lastReactorCommandMarker = nil,
        lastObservedReactorStatus = nil,
        lastCommandedInputRate = 0,
        lastCommandedOutputRate = 0,
    }, ReactorController)

    Util.assertMethod(self.reactor, "getReactorInfo", "Reactor")
    Util.assertMethod(self.reactor, "chargeReactor", "Reactor")
    Util.assertMethod(self.reactor, "activateReactor", "Reactor")
    Util.assertMethod(self.reactor, "stopReactor", "Reactor")

    local currentInputRate = self.inputGate:takeControl()
    local currentOutputRate = self.outputGate:takeControl()
    local snapshot = self:_buildSnapshot(currentInputRate, currentOutputRate)

    self.lastCommandedInputRate = currentInputRate
    self.lastCommandedOutputRate = currentOutputRate
    self.lastObservedReactorStatus = snapshot.reactorStatus

    if snapshot.state == "running" or snapshot.state == "starting" then
        self.desiredEnabled = true
    elseif storedState.desiredEnabled ~= nil then
        self.desiredEnabled = storedState.desiredEnabled == true
    else
        self.desiredEnabled = false
    end

    self.controlStatus = self:_resolvePassiveStatus(snapshot.state)
    self.lastTelemetry = self:_composeTelemetry(snapshot, {
        currentInputRate = currentInputRate,
        currentOutputRate = currentOutputRate,
        previousInputRate = currentInputRate,
        previousOutputRate = currentOutputRate,
        appliedInputRate = currentInputRate,
        appliedOutputRate = currentOutputRate,
        inputDelta = 0,
        outputDelta = 0,
    })
    self.lastReactorInfo = Util.copy(snapshot.info)
    self:_saveState()

    return self
end

function ReactorController:_resolveDeltaTime(deltaTime)
    if deltaTime ~= nil then
        assert(type(deltaTime) == "number" and deltaTime > 0, "deltaTime must be a positive number when provided")

        if os.epoch then
            self.lastUpdateEpoch = os.epoch("utc")
        end

        return deltaTime
    end

    if not os.epoch then
        return 1
    end

    local now = os.epoch("utc")

    if not self.lastUpdateEpoch then
        self.lastUpdateEpoch = now
        return 1
    end

    local resolved = math.max((now - self.lastUpdateEpoch) / 1000, 0.05)
    self.lastUpdateEpoch = now

    return resolved
end

function ReactorController:_readReactorInfo()
    local info = self.reactor.getReactorInfo()
    assert(type(info) == "table", "getReactorInfo must return a table")
    return info
end

function ReactorController:_deriveState(status, fuelCapacity, fuelRemaining)
    if status == "running" then
        return "running"
    end

    if status == "warming_up" then
        return "starting"
    end

    if status == "stopping" or status == "cooling" then
        return "stopping"
    end

    if fuelCapacity <= 0 or fuelRemaining <= 0 then
        return "needs_fuel"
    end

    return "off"
end

function ReactorController:_buildSnapshot(currentInputRate, currentOutputRate)
    local info = self:_readReactorInfo()
    local maxFieldStrength = math.max(info.maxFieldStrength or 0, 0)
    local maxEnergySaturation = math.max(info.maxEnergySaturation or 0, 0)
    local fuelCapacity = math.max(info.maxFuelConversion or 0, 0)
    local fuelConverted = math.max(info.fuelConversion or 0, 0)
    local fuelRemaining = math.max(fuelCapacity - fuelConverted, 0)
    local reactorStatus = Util.normalizeStatus(info.status)
    local fieldPercent = Util.percent(math.max(info.fieldStrength or 0, 0), maxFieldStrength)
    local energySaturationPercent = Util.percent(math.max(info.energySaturation or 0, 0), maxEnergySaturation)
    local fuelPercent = Util.percent(fuelRemaining, fuelCapacity)

    return {
        info = info,
        reactorStatus = reactorStatus,
        state = self:_deriveState(reactorStatus, fuelCapacity, fuelRemaining),
        temperature = math.max(info.temperature or 0, 0),
        fieldStrength = math.max(info.fieldStrength or 0, 0),
        maxFieldStrength = maxFieldStrength,
        fieldPercent = fieldPercent,
        energySaturation = math.max(info.energySaturation or 0, 0),
        maxEnergySaturation = maxEnergySaturation,
        energySaturationPercent = energySaturationPercent,
        fuelConverted = fuelConverted,
        fuelCapacity = fuelCapacity,
        fuelRemaining = fuelRemaining,
        fuelPercent = fuelPercent,
        fuelConversionRate = math.max(info.fuelConversionRate or 0, 0),
        generationRate = math.max(info.generationRate or 0, 0),
        fieldDrainRate = math.max(info.fieldDrainRate or 0, 0),
        failSafe = info.failSafe == true,
        currentInputRate = Util.roundRate(currentInputRate or 0),
        currentOutputRate = Util.roundRate(currentOutputRate or 0),
    }
end

function ReactorController:_composeTelemetry(snapshot, details)
    local telemetry = Util.merge(snapshot, details or {})
    telemetry.currentInputRate = Util.roundRate(telemetry.currentInputRate or snapshot.currentInputRate or 0)
    telemetry.currentOutputRate = Util.roundRate(telemetry.currentOutputRate or snapshot.currentOutputRate or 0)
    telemetry.targetFieldPercent = self.config.targetFieldPercent
    telemetry.minFieldPercent = self.config.minFieldPercent
    telemetry.targetOutputRate = self.config.targetOutputRate
    telemetry.maxTemperature = self.config.maxTemperature
    telemetry.cutOffTemperature = self.config.cutOffTemperature
    telemetry.minimumInputRate = self.config.minimumInputRate
    telemetry.desiredEnabled = self.desiredEnabled
    telemetry.controlStatus = self.controlStatus
    telemetry.netPositive = snapshot.generationRate - telemetry.currentInputRate
    telemetry.fieldMarginPercent = snapshot.fieldPercent - self.config.targetFieldPercent
    telemetry.isFieldAtTarget = snapshot.fieldPercent >= self.config.targetFieldPercent
    telemetry.isFieldAboveMinimum = snapshot.fieldPercent >= self.config.minFieldPercent
    telemetry.isAboveMaxTemperature = snapshot.temperature > self.config.maxTemperature
    telemetry.isAboveCutOffTemperature = snapshot.temperature > self.config.cutOffTemperature
    telemetry.isProducingTargetOutput = telemetry.currentOutputRate >= self.config.targetOutputRate
        and snapshot.fieldPercent >= self.config.targetFieldPercent
        and snapshot.temperature <= self.config.maxTemperature
    telemetry.info = Util.copy(snapshot.info)

    return telemetry
end

function ReactorController:_saveState()
    self.store:save({
        version = 1,
        desiredEnabled = self.desiredEnabled,
        controlStatus = self.controlStatus,
        inputRate = self.lastCommandedInputRate,
        outputRate = self.lastCommandedOutputRate,
        config = Util.copy(self.config),
    })
end

function ReactorController:_ensureTelemetry()
    if self.lastTelemetry == nil then
        self:refresh()
    end

    return self.lastTelemetry
end

function ReactorController:_resolvePassiveStatus(state)
    if not self.desiredEnabled then
        if state == "stopping" then
            return "stopping"
        end

        return "stopped"
    end

    if state == "needs_fuel" then
        return "needs_fuel"
    end

    if state == "starting" then
        return "charging_reactor"
    end

    if state == "stopping" then
        return "waiting_for_restart_window"
    end

    if state == "running" then
        return "adopted_running_reactor"
    end

    return "ready_to_start"
end

function ReactorController:_shouldEmergencyShutdown(snapshot)
    return snapshot.state == "running"
        and (snapshot.fieldPercent < self.config.minFieldPercent or snapshot.temperature > self.config.cutOffTemperature)
end

function ReactorController:_shouldShutdownForRefuel(snapshot)
    return snapshot.state == "running" and snapshot.fuelRemaining <= 0
end

function ReactorController:_isActivationReady(snapshot)
    return snapshot.reactorStatus == "warming_up"
        and snapshot.energySaturationPercent >= 50
        and snapshot.fieldPercent >= 50
        and snapshot.temperature > 2000
end

function ReactorController:_resetCommandMarkerIfNeeded(snapshot)
    if snapshot.reactorStatus ~= self.lastObservedReactorStatus then
        self.lastObservedReactorStatus = snapshot.reactorStatus
        self.lastReactorCommandMarker = nil
    end
end

function ReactorController:_issueReactorCommand(commandName, snapshot)
    local marker = ("%s:%s"):format(commandName, snapshot.reactorStatus)
    if self.lastReactorCommandMarker == marker then
        return false
    end

    self.reactor[commandName]()
    self.lastReactorCommandMarker = marker
    return true
end

function ReactorController:_applyRates(inputRate, outputRate)
    self.lastCommandedInputRate = self.inputGate:setRate(inputRate)
    self.lastCommandedOutputRate = self.outputGate:setRate(outputRate)
end

function ReactorController:_finalizeUpdate(snapshot, details)
    self.lastTelemetry = self:_composeTelemetry(snapshot, details)
    self.lastReactorInfo = Util.copy(snapshot.info)
    self:_saveState()
    return Util.copy(self.lastTelemetry)
end

function ReactorController:_resolveRunningStatus(outputMeta, snapshot, appliedOutputRate)
    if outputMeta.mode == "waiting_for_field" then
        return "throttled_waiting_for_field"
    end

    if outputMeta.mode == "temperature_limited" then
        return "throttled_high_temperature"
    end

    if outputMeta.mode == "ramping_output" then
        return "climbing_to_target_output"
    end

    if appliedOutputRate >= self.config.targetOutputRate and snapshot.fieldPercent >= self.config.targetFieldPercent then
        return "producing_target_output"
    end

    return "stabilizing_field"
end

function ReactorController:_buildStartupInputRate(snapshot, deltaTime)
    local startupTargetFieldPercent = math.max(self.config.targetFieldPercent, 50)

    local startupInputRate = self.fieldController:calculate({
        currentInputRate = snapshot.currentInputRate,
        fieldStrength = snapshot.fieldStrength,
        maxFieldStrength = snapshot.maxFieldStrength,
        fieldDrainRate = snapshot.fieldDrainRate,
        targetFieldPercent = startupTargetFieldPercent,
        minimumInputRate = self.config.minimumInputRate,
        inputReductionRampRate = self.config.inputReductionRampRate,
        fieldRecoveryWindow = self.config.fieldRecoveryWindow,
        deltaTime = deltaTime,
    })

    return startupInputRate
end

function ReactorController:refresh()
    local currentInputRate = self.inputGate:getRate()
    local currentOutputRate = self.outputGate:getRate()
    local snapshot = self:_buildSnapshot(currentInputRate, currentOutputRate)
    self:_resetCommandMarkerIfNeeded(snapshot)
    self.controlStatus = self:_resolvePassiveStatus(snapshot.state)
    self.lastReactorInfo = Util.copy(snapshot.info)
    self.lastTelemetry = self:_composeTelemetry(snapshot, {
        currentInputRate = currentInputRate,
        currentOutputRate = currentOutputRate,
        previousInputRate = currentInputRate,
        previousOutputRate = currentOutputRate,
        appliedInputRate = currentInputRate,
        appliedOutputRate = currentOutputRate,
        inputDelta = 0,
        outputDelta = 0,
    })

    return Util.copy(self.lastTelemetry)
end

function ReactorController:update(deltaTime)
    local resolvedDeltaTime = self:_resolveDeltaTime(deltaTime)
    local previousInputRate = self.inputGate:getRate()
    local previousOutputRate = self.outputGate:getRate()
    local snapshot = self:_buildSnapshot(previousInputRate, previousOutputRate)
    self:_resetCommandMarkerIfNeeded(snapshot)

    if not self.desiredEnabled then
        if snapshot.state == "running" or snapshot.state == "starting" then
            self:_issueReactorCommand("stopReactor", snapshot)
        end

        self.controlStatus = snapshot.state == "stopping" and "stopping" or "stopped"
        self:_applyRates(0, 0)

        return self:_finalizeUpdate(snapshot, {
            previousInputRate = previousInputRate,
            previousOutputRate = previousOutputRate,
            currentInputRate = 0,
            currentOutputRate = 0,
            appliedInputRate = 0,
            appliedOutputRate = 0,
            inputDelta = -previousInputRate,
            outputDelta = -previousOutputRate,
        })
    end

    if snapshot.state == "needs_fuel" then
        self.controlStatus = "needs_fuel"
        self:_applyRates(0, 0)

        return self:_finalizeUpdate(snapshot, {
            previousInputRate = previousInputRate,
            previousOutputRate = previousOutputRate,
            currentInputRate = 0,
            currentOutputRate = 0,
            appliedInputRate = 0,
            appliedOutputRate = 0,
            inputDelta = -previousInputRate,
            outputDelta = -previousOutputRate,
        })
    end

    if snapshot.state == "stopping" then
        self.controlStatus = "waiting_for_restart_window"
        self:_applyRates(0, 0)

        return self:_finalizeUpdate(snapshot, {
            previousInputRate = previousInputRate,
            previousOutputRate = previousOutputRate,
            currentInputRate = 0,
            currentOutputRate = 0,
            appliedInputRate = 0,
            appliedOutputRate = 0,
            inputDelta = -previousInputRate,
            outputDelta = -previousOutputRate,
        })
    end

    if snapshot.state == "off" then
        self:_issueReactorCommand("chargeReactor", snapshot)

        local startupInputRate = self:_buildStartupInputRate(snapshot, resolvedDeltaTime)
        self.controlStatus = "charging_reactor"
        self:_applyRates(startupInputRate, 0)

        return self:_finalizeUpdate(snapshot, {
            previousInputRate = previousInputRate,
            previousOutputRate = previousOutputRate,
            currentInputRate = startupInputRate,
            currentOutputRate = 0,
            appliedInputRate = startupInputRate,
            appliedOutputRate = 0,
            inputDelta = startupInputRate - previousInputRate,
            outputDelta = -previousOutputRate,
        })
    end

    if snapshot.state == "starting" then
        if self:_isActivationReady(snapshot) then
            self:_issueReactorCommand("activateReactor", snapshot)
            self.controlStatus = "activating_reactor"
        else
            self.controlStatus = "charging_reactor"
        end

        local startupInputRate = self:_buildStartupInputRate(snapshot, resolvedDeltaTime)
        self:_applyRates(startupInputRate, 0)

        return self:_finalizeUpdate(snapshot, {
            previousInputRate = previousInputRate,
            previousOutputRate = previousOutputRate,
            currentInputRate = startupInputRate,
            currentOutputRate = 0,
            appliedInputRate = startupInputRate,
            appliedOutputRate = 0,
            inputDelta = startupInputRate - previousInputRate,
            outputDelta = -previousOutputRate,
        })
    end

    if self:_shouldEmergencyShutdown(snapshot) then
        self.desiredEnabled = false
        self.controlStatus = snapshot.temperature > self.config.cutOffTemperature
            and "emergency_temperature_shutdown"
            or "emergency_field_shutdown"
        self:_issueReactorCommand("stopReactor", snapshot)
        self:_applyRates(0, 0)

        return self:_finalizeUpdate(snapshot, {
            previousInputRate = previousInputRate,
            previousOutputRate = previousOutputRate,
            currentInputRate = 0,
            currentOutputRate = 0,
            appliedInputRate = 0,
            appliedOutputRate = 0,
            inputDelta = -previousInputRate,
            outputDelta = -previousOutputRate,
        })
    end

    if self:_shouldShutdownForRefuel(snapshot) then
        self.desiredEnabled = false
        self.controlStatus = "refuel_shutdown"
        self:_issueReactorCommand("stopReactor", snapshot)
        self:_applyRates(0, 0)

        return self:_finalizeUpdate(snapshot, {
            previousInputRate = previousInputRate,
            previousOutputRate = previousOutputRate,
            currentInputRate = 0,
            currentOutputRate = 0,
            appliedInputRate = 0,
            appliedOutputRate = 0,
            inputDelta = -previousInputRate,
            outputDelta = -previousOutputRate,
        })
    end

    local plannedInputRate, fieldMeta = self.fieldController:calculate({
        currentInputRate = previousInputRate,
        fieldStrength = snapshot.fieldStrength,
        maxFieldStrength = snapshot.maxFieldStrength,
        fieldDrainRate = snapshot.fieldDrainRate,
        targetFieldPercent = self.config.targetFieldPercent,
        minimumInputRate = self.config.minimumInputRate,
        inputReductionRampRate = self.config.inputReductionRampRate,
        fieldRecoveryWindow = self.config.fieldRecoveryWindow,
        deltaTime = resolvedDeltaTime,
    })

    local plannedOutputRate, outputMeta = self.outputController:calculate({
        currentOutputRate = previousOutputRate,
        targetOutputRate = self.config.targetOutputRate,
        fieldPercent = snapshot.fieldPercent,
        targetFieldPercent = self.config.targetFieldPercent,
        temperature = snapshot.temperature,
        maxTemperature = self.config.maxTemperature,
        outputRampRate = self.config.outputRampRate,
        deltaTime = resolvedDeltaTime,
    })

    local outputDelta = plannedOutputRate - previousOutputRate
    local preemptiveInputBoost = 0

    if outputDelta > 0 then
        preemptiveInputBoost = Util.roundRate(outputDelta * self.config.preemptiveInputRatio)
        plannedInputRate = math.max(plannedInputRate, plannedInputRate + preemptiveInputBoost)
    end

    plannedInputRate = math.max(plannedInputRate, self.config.minimumInputRate)
    plannedInputRate = Util.roundRate(plannedInputRate)
    plannedOutputRate = Util.roundRate(plannedOutputRate)

    self.controlStatus = self:_resolveRunningStatus(outputMeta, snapshot, plannedOutputRate)
    self:_applyRates(plannedInputRate, plannedOutputRate)

    return self:_finalizeUpdate(snapshot, {
        currentInputRate = plannedInputRate,
        currentOutputRate = plannedOutputRate,
        previousInputRate = previousInputRate,
        previousOutputRate = previousOutputRate,
        appliedInputRate = plannedInputRate,
        appliedOutputRate = plannedOutputRate,
        inputDelta = plannedInputRate - previousInputRate,
        outputDelta = plannedOutputRate - previousOutputRate,
        preemptiveInputBoost = preemptiveInputBoost,
        fieldMode = fieldMeta.mode,
        outputMode = outputMeta.mode,
        idealFieldInputRate = fieldMeta.idealInputRate,
        idealOutputRate = outputMeta.idealOutputRate,
    })
end

function ReactorController:start()
    self.desiredEnabled = true
    self.controlStatus = "start_requested"
    self:_saveState()
end

function ReactorController:stop()
    self.desiredEnabled = false
    self.controlStatus = "stop_requested"
    self:_saveState()
end

function ReactorController:isEnabled()
    return self.desiredEnabled
end

function ReactorController:setConfig(overrides)
    local mergedConfig = Util.merge(self.config, overrides or {})
    validateConfig(mergedConfig)
    self.config = mergedConfig
    self:_saveState()
end

function ReactorController:getConfig()
    return Util.copy(self.config)
end

function ReactorController:setTargetFieldPercent(targetFieldPercent)
    self:setConfig({ targetFieldPercent = targetFieldPercent })
end

function ReactorController:setMinFieldPercent(minFieldPercent)
    self:setConfig({ minFieldPercent = minFieldPercent })
end

function ReactorController:setTargetOutputRate(targetOutputRate)
    self:setConfig({ targetOutputRate = targetOutputRate })
end

function ReactorController:setMaxTemperature(maxTemperature)
    self:setConfig({ maxTemperature = maxTemperature })
end

function ReactorController:setCutOffTemperature(cutOffTemperature)
    self:setConfig({ cutOffTemperature = cutOffTemperature })
end

function ReactorController:setOutputRampRate(outputRampRate)
    self:setConfig({ outputRampRate = outputRampRate })
end

function ReactorController:setInputReductionRampRate(inputReductionRampRate)
    self:setConfig({ inputReductionRampRate = inputReductionRampRate })
end

function ReactorController:setMinimumInputRate(minimumInputRate)
    self:setConfig({ minimumInputRate = minimumInputRate })
end

function ReactorController:setPreemptiveInputRatio(preemptiveInputRatio)
    self:setConfig({ preemptiveInputRatio = preemptiveInputRatio })
end

function ReactorController:setFieldRecoveryWindow(fieldRecoveryWindow)
    self:setConfig({ fieldRecoveryWindow = fieldRecoveryWindow })
end

function ReactorController:getTelemetry()
    return Util.copy(self:_ensureTelemetry())
end

function ReactorController:getControlStatus()
    return self:_ensureTelemetry().controlStatus
end

function ReactorController:getStatus()
    return self:getControlStatus()
end

function ReactorController:getState()
    return self:_ensureTelemetry().state
end

function ReactorController:getCurrentState()
    return self:getState()
end

function ReactorController:getFieldPercent()
    return self:_ensureTelemetry().fieldPercent
end

function ReactorController:getFieldStrength()
    return self:_ensureTelemetry().fieldStrength
end

function ReactorController:getEnergySaturationPercent()
    return self:_ensureTelemetry().energySaturationPercent
end

function ReactorController:getEnergySaturation()
    return self:_ensureTelemetry().energySaturation
end

function ReactorController:getFuelPercent()
    return self:_ensureTelemetry().fuelPercent
end

function ReactorController:getFuelRemaining()
    return self:_ensureTelemetry().fuelRemaining
end

function ReactorController:getFuelUsageRate()
    return self:_ensureTelemetry().fuelConversionRate
end

function ReactorController:getCurrentTemperature()
    return self:_ensureTelemetry().temperature
end

function ReactorController:getCurrentInputRate()
    return self:_ensureTelemetry().currentInputRate
end

function ReactorController:getCurrentGateInputRate()
    return self:getCurrentInputRate()
end

function ReactorController:getCurrentOutputRate()
    return self:_ensureTelemetry().currentOutputRate
end

function ReactorController:getCurrentGateOutputRate()
    return self:getCurrentOutputRate()
end

function ReactorController:getCurrentGenerationRate()
    return self:_ensureTelemetry().generationRate
end

function ReactorController:getCurrentReactorGenerationRate()
    return self:getCurrentGenerationRate()
end

function ReactorController:getTargetOutputRate()
    return self.config.targetOutputRate
end

function ReactorController:getNetPositiveRate()
    return self:_ensureTelemetry().netPositive
end

function ReactorController:getNetPositive()
    return self:getNetPositiveRate()
end

function ReactorController:getFieldDrainRate()
    return self:_ensureTelemetry().fieldDrainRate
end

function ReactorController:getTargetFieldPercent()
    return self.config.targetFieldPercent
end

function ReactorController:getMinimumFieldPercent()
    return self.config.minFieldPercent
end

function ReactorController:isBelowTargetField()
    return self:getFieldPercent() < self.config.targetFieldPercent
end

function ReactorController:isBelowMinimumField()
    return self:getFieldPercent() < self.config.minFieldPercent
end

function ReactorController:isAboveMaxTemperature()
    return self:getCurrentTemperature() > self.config.maxTemperature
end

function ReactorController:isAboveCutOffTemperature()
    return self:getCurrentTemperature() > self.config.cutOffTemperature
end

function ReactorController:isThrottled()
    local status = self:getControlStatus()
    return status == "throttled_waiting_for_field" or status == "throttled_high_temperature"
end

function ReactorController:hasFuel()
    return self:getFuelRemaining() > 0
end

function ReactorController:needsFuel()
    return self:getState() == "needs_fuel"
end

function ReactorController:isRunning()
    return self:getState() == "running"
end

function ReactorController:isStarting()
    return self:getState() == "starting"
end

function ReactorController:isStopped()
    local state = self:getState()
    return state == "off" or state == "needs_fuel"
end

function ReactorController:getFailSafeState()
    return self:_ensureTelemetry().failSafe
end

function ReactorController:getReactorInfo()
    self:_ensureTelemetry()
    return Util.copy(self.lastReactorInfo)
end

return ReactorController
