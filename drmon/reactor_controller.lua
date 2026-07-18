local FieldController = require("drmon.field_controller")
local OutputController = require("drmon.output_controller")

local ReactorController = {}
ReactorController.__index = ReactorController

local MODE_RUNNING = "running"
local MODE_STOPPED = "stopped"

local STATE_OFF = "off"
local STATE_NEEDS_FUEL = "needs_fuel"
local STATE_STARTING = "starting"
local STATE_RUNNING = "running"
local STATE_STOPPING = "stopping"

local DEFAULT_CONFIG = {
    targetFieldPercent = 55,
    minFieldPercent = 35,
    targetOutputRate = 0,
    maxTemperature = 7800,
    cutOffTemperature = 8200,
    rateRampPerSecond = 500000,
    outputRampPerSecond = nil,
    inputRampDownPerSecond = nil,
    minInputRate = 250000,
    outputBoostCompensationRatio = 0.5,
    fieldResponseMultiplier = 4,
    fieldTrimMultiplier = 0.5,
    startupInputRate = 500000,
    statePath = "/drmon/reactor_controller_state.txt",
}

local EMPTY_REACTOR_INFO = {
    temperature = 0,
    fieldStrength = 0,
    maxFieldStrength = 0,
    energySaturation = 0,
    maxEnergySaturation = 0,
    fuelConversion = 0,
    maxFuelConversion = 0,
    generationRate = 0,
    fieldDrainRate = 0,
    fuelConversionRate = 0,
    status = "unknown",
    failSafe = false,
}

local PeripheralBinding = {}
PeripheralBinding.__index = PeripheralBinding

local function copyTable(source)
    local copy = {}

    for key, value in pairs(source) do
        if type(value) == "table" then
            copy[key] = copyTable(value)
        else
            copy[key] = value
        end
    end

    return copy
end

local function copyArray(source)
    local copy = {}

    for index = 1, #source do
        copy[index] = source[index]
    end

    return copy
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end

    if value > maximum then
        return maximum
    end

    return value
end

local function normalizeRate(value)
    return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

local function normalizePercent(current, maximum)
    if maximum == nil or maximum <= 0 then
        return 0
    end

    return clamp((current / maximum) * 100, 0, 100)
end

local function normalizeStatus(value)
    return tostring(value or "unknown"):gsub("%s+", "_"):lower()
end

local function getRemainingFuel(info)
    return math.max(0, (tonumber(info.maxFuelConversion) or 0) - (tonumber(info.fuelConversion) or 0))
end

local function hasFuel(info)
    return getRemainingFuel(info) > 0
end

local function expectNumber(name, value)
    if type(value) ~= "number" then
        error(string.format("%s must be a number", name), 3)
    end
end

local function expectNonNegative(name, value)
    expectNumber(name, value)

    if value < 0 then
        error(string.format("%s must be non-negative", name), 3)
    end
end

local function mergeInto(target, values)
    if type(values) ~= "table" then
        return
    end

    for key, value in pairs(values) do
        target[key] = value
    end
end

local function normalizeConfig(baseConfig, overrides)
    local config = copyTable(DEFAULT_CONFIG)

    mergeInto(config, baseConfig)
    mergeInto(config, overrides)

    if type(overrides) == "table" and overrides.rateRampPerSecond ~= nil then
        if overrides.outputRampPerSecond == nil then
            config.outputRampPerSecond = overrides.rateRampPerSecond
        end

        if overrides.inputRampDownPerSecond == nil then
            config.inputRampDownPerSecond = overrides.rateRampPerSecond
        end
    end

    if config.outputRampPerSecond == nil then
        config.outputRampPerSecond = config.rateRampPerSecond
    end

    if config.inputRampDownPerSecond == nil then
        config.inputRampDownPerSecond = config.rateRampPerSecond
    end

    config.minInputRate = math.max(config.minInputRate, 250000)
    config.startupInputRate = math.max(config.startupInputRate, config.minInputRate)

    expectNonNegative("targetFieldPercent", config.targetFieldPercent)
    expectNonNegative("minFieldPercent", config.minFieldPercent)
    expectNonNegative("targetOutputRate", config.targetOutputRate)
    expectNonNegative("maxTemperature", config.maxTemperature)
    expectNonNegative("cutOffTemperature", config.cutOffTemperature)
    expectNonNegative("rateRampPerSecond", config.rateRampPerSecond)
    expectNonNegative("outputRampPerSecond", config.outputRampPerSecond)
    expectNonNegative("inputRampDownPerSecond", config.inputRampDownPerSecond)
    expectNonNegative("minInputRate", config.minInputRate)
    expectNonNegative("outputBoostCompensationRatio", config.outputBoostCompensationRatio)
    expectNonNegative("fieldResponseMultiplier", config.fieldResponseMultiplier)
    expectNonNegative("fieldTrimMultiplier", config.fieldTrimMultiplier)
    expectNonNegative("startupInputRate", config.startupInputRate)

    if config.targetFieldPercent > 100 then
        error("targetFieldPercent must be at most 100", 3)
    end

    if config.minFieldPercent > 100 then
        error("minFieldPercent must be at most 100", 3)
    end

    if config.minFieldPercent >= config.targetFieldPercent then
        error("minFieldPercent must be lower than targetFieldPercent", 3)
    end

    if config.cutOffTemperature <= config.maxTemperature then
        error("cutOffTemperature must be greater than maxTemperature", 3)
    end

    if type(config.statePath) ~= "string" or config.statePath == "" then
        error("statePath must be a non-empty string", 3)
    end

    return config
end

function PeripheralBinding._resolveName(reference)
    if type(peripheral) ~= "table" or type(peripheral.getName) ~= "function" then
        return nil
    end

    local ok, name = pcall(peripheral.getName, reference)

    if ok then
        return name
    end

    return nil
end

function PeripheralBinding.new(reference, label)
    if reference == nil then
        error(string.format("%s peripheral is required", label), 3)
    end

    local self = setmetatable({
        label = label,
        reference = reference,
        name = nil,
        lastError = nil,
    }, PeripheralBinding)

    if type(reference) == "string" then
        self.name = reference
    else
        self.name = PeripheralBinding._resolveName(reference) or label
    end

    return self
end

function PeripheralBinding:_resolve()
    if type(self.reference) == "table" then
        return self.reference
    end

    if type(peripheral) ~= "table" or type(peripheral.wrap) ~= "function" then
        return nil, string.format("%s peripheral API is unavailable", self.label)
    end

    local wrapped = peripheral.wrap(self.reference)

    if wrapped == nil then
        return nil, string.format("%s peripheral %s is unavailable", self.label, tostring(self.reference))
    end

    return wrapped
end

function PeripheralBinding:call(methodName, ...)
    local wrapped, resolveError = self:_resolve()

    if wrapped == nil then
        self.lastError = resolveError
        return false, resolveError
    end

    local method = wrapped[methodName]

    if type(method) ~= "function" then
        local message = string.format("%s is missing method %s", self.label, tostring(methodName))
        self.lastError = message
        return false, message
    end

    local ok, result1, result2, result3, result4, result5 = pcall(method, wrapped, ...)

    if not ok then
        local message = string.format("%s.%s failed: %s", self.label, tostring(methodName), tostring(result1))
        self.lastError = message
        return false, message
    end

    self.lastError = nil
    return true, result1, result2, result3, result4, result5
end

function PeripheralBinding:getName()
    return self.name or tostring(self.reference)
end

local function loadState(path)
    if type(fs) ~= "table" or type(fs.exists) ~= "function" or type(fs.open) ~= "function" then
        return nil, "fs API is unavailable"
    end

    if not fs.exists(path) then
        return nil
    end

    local handle = fs.open(path, "r")

    if handle == nil then
        return nil, string.format("failed to open state file %s", path)
    end

    local contents = handle.readAll()
    handle.close()

    if contents == nil or contents == "" then
        return nil
    end

    if type(textutils) ~= "table" or type(textutils.unserialize) ~= "function" then
        return nil, "textutils API is unavailable"
    end

    local state = textutils.unserialize(contents)

    if type(state) ~= "table" then
        return nil, string.format("state file %s is corrupt", path)
    end

    return state
end

function ReactorController.defaultConfig()
    return copyTable(DEFAULT_CONFIG)
end

local function normalizeReactorInfo(info)
    local normalized = copyTable(EMPTY_REACTOR_INFO)

    normalized.temperature = tonumber(info.temperature) or 0
    normalized.fieldStrength = tonumber(info.fieldStrength) or 0
    normalized.maxFieldStrength = tonumber(info.maxFieldStrength) or 0
    normalized.energySaturation = tonumber(info.energySaturation) or 0
    normalized.maxEnergySaturation = tonumber(info.maxEnergySaturation) or 0
    normalized.fuelConversion = tonumber(info.fuelConversion) or 0
    normalized.maxFuelConversion = tonumber(info.maxFuelConversion) or 0
    normalized.generationRate = tonumber(info.generationRate) or 0
    normalized.fieldDrainRate = tonumber(info.fieldDrainRate) or 0
    normalized.fuelConversionRate = tonumber(info.fuelConversionRate) or 0
    normalized.status = normalizeStatus(info.status)
    normalized.failSafe = not not info.failSafe

    return normalized
end

function ReactorController:_deriveState(info)
    local status = normalizeStatus(info.status)

    if status == "running" or status == "online" then
        return STATE_RUNNING
    end

    if status == "warming_up" or status == "charging" or status == "charged" then
        return STATE_STARTING
    end

    if status == "stopping" or status == "cooling" or status == "cooling_down" then
        return STATE_STOPPING
    end

    if hasFuel(info) then
        return STATE_OFF
    end

    return STATE_NEEDS_FUEL
end

function ReactorController:_readReactorInfo()
    local ok, infoOrError = self._reactor:call("getReactorInfo")

    if not ok then
        return nil, infoOrError
    end

    if type(infoOrError) ~= "table" then
        return nil, "reactor.getReactorInfo returned invalid data"
    end

    return normalizeReactorInfo(infoOrError)
end

function ReactorController:_readGateState(binding)
    local state = {
        name = binding:getName(),
        connected = false,
        flow = nil,
        overrideEnabled = false,
        error = nil,
    }

    local flowOk, flowOrError = binding:call("getFlow")
    if flowOk then
        state.flow = normalizeRate(flowOrError)
    else
        state.error = flowOrError
    end

    local overrideOk, overrideOrError = binding:call("getOverrideEnabled")
    if overrideOk then
        state.overrideEnabled = not not overrideOrError
    else
        state.error = state.error or overrideOrError
    end

    state.connected = flowOk and overrideOk
    return state
end

function ReactorController:_collectSnapshot(deltaTime)
    local warnings = {}
    local freshInfo, reactorError = self:_readReactorInfo()

    if freshInfo then
        self._lastInfo = freshInfo
    elseif reactorError then
        warnings[#warnings + 1] = reactorError
    end

    local inputGateState = self:_readGateState(self._inputGate)
    if inputGateState.error then
        warnings[#warnings + 1] = inputGateState.error
    end

    local outputGateState = self:_readGateState(self._outputGate)
    if outputGateState.error then
        warnings[#warnings + 1] = outputGateState.error
    end

    local info = self._lastInfo or copyTable(EMPTY_REACTOR_INFO)
    local currentState = self:_deriveState(info)

    local currentInputRate = inputGateState.flow
    if currentInputRate == nil then
        currentInputRate = self._appliedInputRate or self._desiredInputRate or 0
    end

    local currentOutputRate = outputGateState.flow
    if currentOutputRate == nil then
        currentOutputRate = self._appliedOutputRate or self._desiredOutputRate or 0
    end

    return {
        deltaTime = math.max(0, tonumber(deltaTime) or 0),
        info = info,
        warnings = warnings,
        reactorAvailable = freshInfo ~= nil,
        inputGate = inputGateState,
        outputGate = outputGateState,
        currentState = currentState,
        currentInputRate = normalizeRate(currentInputRate),
        currentOutputRate = normalizeRate(currentOutputRate),
        fieldPercent = normalizePercent(info.fieldStrength, info.maxFieldStrength),
        energySaturationPercent = normalizePercent(info.energySaturation, info.maxEnergySaturation),
        remainingFuel = getRemainingFuel(info),
        fuelPercent = normalizePercent(getRemainingFuel(info), info.maxFuelConversion),
    }
end

function ReactorController:_getStartupInputRate(snapshot)
    return normalizeRate(math.max(
        self._config.startupInputRate,
        self._config.minInputRate,
        snapshot.currentInputRate,
        self._config.targetOutputRate
    ))
end

function ReactorController:_getStoppingInputRate(snapshot)
    return normalizeRate(math.max(
        self._config.minInputRate,
        snapshot.currentInputRate,
        snapshot.info.fieldDrainRate
    ))
end

function ReactorController:_canActivate(snapshot)
    return snapshot.info.status == "warming_up"
        and snapshot.energySaturationPercent >= 50
        and snapshot.fieldPercent >= 50
        and snapshot.info.temperature >= 2000
end

function ReactorController:_shouldShutdown(snapshot)
    if snapshot.currentState ~= STATE_RUNNING then
        return false
    end

    if snapshot.info.temperature >= self._config.cutOffTemperature then
        return true, "emergency", "temperature_cutoff"
    end

    if snapshot.fieldPercent <= self._config.minFieldPercent then
        return true, "emergency", "field_below_minimum"
    end

    if snapshot.remainingFuel <= 0 then
        return true, "normal", "refuel_required"
    end

    return false
end

function ReactorController:_recordAction(plan, action)
    plan.actions[#plan.actions + 1] = action
end

function ReactorController:_callReactor(methodName, plan, actionName)
    local ok, resultOrError = self._reactor:call(methodName)

    if ok then
        self:_recordAction(plan, actionName)
        return true
    end

    plan.warnings[#plan.warnings + 1] = resultOrError
    return false
end

function ReactorController:_applyGate(binding, gateState, desiredRate)
    if not gateState.connected then
        return false, gateState.error or string.format("%s is unavailable", gateState.name)
    end

    if not gateState.overrideEnabled then
        local overrideOk, overrideOrError = binding:call("setOverrideEnabled", true)

        if not overrideOk then
            return false, overrideOrError
        end

        gateState.overrideEnabled = true
    end

    if gateState.flow ~= desiredRate then
        local flowOk, flowOrError = binding:call("setFlowOverride", desiredRate)

        if not flowOk then
            return false, flowOrError
        end

        gateState.flow = desiredRate
    end

    gateState.connected = true
    return true
end

function ReactorController:_persistState()
    if type(fs) ~= "table"
        or type(fs.open) ~= "function"
        or type(fs.getDir) ~= "function"
        or type(fs.exists) ~= "function"
        or type(fs.move) ~= "function"
        or type(fs.delete) ~= "function"
        or type(fs.makeDir) ~= "function" then
        return false, "fs API is unavailable"
    end

    if type(textutils) ~= "table" or type(textutils.serialize) ~= "function" then
        return false, "textutils API is unavailable"
    end

    local directory = fs.getDir(self._statePath)
    if directory ~= "" and not fs.exists(directory) then
        fs.makeDir(directory)
    end

    local temporaryPath = self._statePath .. ".tmp"
    local handle = fs.open(temporaryPath, "w")

    if handle == nil then
        return false, string.format("failed to write state file %s", temporaryPath)
    end

    handle.write(textutils.serialize({
        version = 1,
        requestedMode = self._requestedMode,
        desiredInputRate = self._desiredInputRate,
        desiredOutputRate = self._desiredOutputRate,
        appliedInputRate = self._appliedInputRate,
        appliedOutputRate = self._appliedOutputRate,
        lastShutdownReason = self._lastShutdownReason,
        config = copyTable(self._config),
    }))
    handle.close()

    if fs.exists(self._statePath) then
        fs.delete(self._statePath)
    end

    fs.move(temporaryPath, self._statePath)
    return true
end

function ReactorController:_makeStatus(info, state, currentInputRate, currentOutputRate, controlStatus, warnings, actions)
    local remainingFuel = getRemainingFuel(info)
    local fieldPercent = normalizePercent(info.fieldStrength, info.maxFieldStrength)
    local energySaturationPercent = normalizePercent(info.energySaturation, info.maxEnergySaturation)
    local fuelPercent = normalizePercent(remainingFuel, info.maxFuelConversion)
    local isThrottled = controlStatus == "throttled_field" or controlStatus == "throttled_temperature"
    local producingTarget = self._config.targetOutputRate <= 0 or currentOutputRate >= self._config.targetOutputRate

    return {
        currentState = state,
        requestedMode = self._requestedMode,
        controlStatus = controlStatus,
        productionStatus = controlStatus,
        reactorStatus = info.status,
        fieldPercent = fieldPercent,
        energySaturationPercent = energySaturationPercent,
        fuelPercent = fuelPercent,
        fuelUsageRate = info.fuelConversionRate,
        currentTemperature = info.temperature,
        currentInputRate = currentInputRate,
        inputFluxRate = currentInputRate,
        currentGenerationRate = info.generationRate,
        currentOutputRate = currentOutputRate,
        outputFluxRate = currentOutputRate,
        targetOutputRate = self._config.targetOutputRate,
        desiredInputRate = self._desiredInputRate,
        desiredOutputRate = self._desiredOutputRate,
        netPositiveRate = info.generationRate - currentInputRate,
        fieldDrainRate = info.fieldDrainRate,
        remainingFuel = remainingFuel,
        targetFieldPercent = self._config.targetFieldPercent,
        minFieldPercent = self._config.minFieldPercent,
        maxTemperature = self._config.maxTemperature,
        cutOffTemperature = self._config.cutOffTemperature,
        belowTargetField = fieldPercent < self._config.targetFieldPercent,
        belowMinimumField = fieldPercent <= self._config.minFieldPercent,
        aboveMaxTemperature = info.temperature >= self._config.maxTemperature,
        aboveCutOffTemperature = info.temperature >= self._config.cutOffTemperature,
        isThrottled = isThrottled,
        waitingForField = controlStatus == "throttled_field",
        producingTargetOutput = producingTarget,
        lastShutdownReason = self._lastShutdownReason,
        hasFuel = remainingFuel > 0,
        peripherals = {
            reactor = self._lastPeripheralHealth.reactor,
            inputGate = self._lastPeripheralHealth.inputGate,
            outputGate = self._lastPeripheralHealth.outputGate,
        },
        warnings = copyArray(warnings),
        actions = copyArray(actions),
    }
end

function ReactorController:_publishStatus(snapshot, state, controlStatus, actions, warnings)
    self._lastWarnings = copyArray(warnings)
    self._lastError = self._lastWarnings[1]
    self._lastTelemetry = self:_makeStatus(
        snapshot.info,
        state,
        self._appliedInputRate,
        self._appliedOutputRate,
        controlStatus,
        warnings,
        actions
    )

    local persisted, persistError = self:_persistState()
    if not persisted then
        self._lastWarnings[#self._lastWarnings + 1] = persistError
        self._lastTelemetry.warnings[#self._lastTelemetry.warnings + 1] = persistError
        self._lastError = self._lastError or persistError
    end

    return copyTable(self._lastTelemetry)
end

function ReactorController:_applyPlan(snapshot, plan)
    plan.desiredInputRate = normalizeRate(plan.desiredInputRate)
    plan.desiredOutputRate = normalizeRate(plan.desiredOutputRate)

    if plan.keepInputMinimum then
        plan.desiredInputRate = math.max(plan.desiredInputRate, self._config.minInputRate)
    end

    self._desiredInputRate = plan.desiredInputRate
    self._desiredOutputRate = plan.desiredOutputRate

    local inputApplied = false
    local outputApplied = false

    local inputOk, inputError = self:_applyGate(self._inputGate, snapshot.inputGate, plan.desiredInputRate)
    if inputOk then
        self._appliedInputRate = plan.desiredInputRate
        inputApplied = true
    else
        plan.warnings[#plan.warnings + 1] = inputError
        self._appliedInputRate = snapshot.currentInputRate
    end

    local outputOk, outputError = self:_applyGate(self._outputGate, snapshot.outputGate, plan.desiredOutputRate)
    if outputOk then
        self._appliedOutputRate = plan.desiredOutputRate
        outputApplied = true
    else
        plan.warnings[#plan.warnings + 1] = outputError
        self._appliedOutputRate = snapshot.currentOutputRate
    end

    self._lastPeripheralHealth = {
        reactor = snapshot.reactorAvailable,
        inputGate = inputApplied or snapshot.inputGate.connected,
        outputGate = outputApplied or snapshot.outputGate.connected,
    }

    return self:_publishStatus(snapshot, plan.reportedState, plan.controlStatus, plan.actions, plan.warnings)
end

function ReactorController:_holdRates(snapshot, controlStatus)
    self._desiredInputRate = snapshot.currentInputRate
    self._desiredOutputRate = snapshot.currentOutputRate
    self._appliedInputRate = snapshot.currentInputRate
    self._appliedOutputRate = snapshot.currentOutputRate
    self._lastPeripheralHealth = {
        reactor = snapshot.reactorAvailable,
        inputGate = snapshot.inputGate.connected,
        outputGate = snapshot.outputGate.connected,
    }

    return self:_publishStatus(snapshot, snapshot.currentState, controlStatus, {}, snapshot.warnings)
end

function ReactorController.new(reactorPeripheral, inputGatePeripheral, outputGatePeripheral, config)
    local requestedConfig = config or {}
    local statePath = requestedConfig.statePath or DEFAULT_CONFIG.statePath
    local persistedState, stateError = loadState(statePath)
    local mergedConfig = normalizeConfig(persistedState and persistedState.config or nil, requestedConfig)

    local self = setmetatable({
        _config = mergedConfig,
        _statePath = mergedConfig.statePath,
        _reactor = PeripheralBinding.new(reactorPeripheral, "reactor"),
        _inputGate = PeripheralBinding.new(inputGatePeripheral, "input gate"),
        _outputGate = PeripheralBinding.new(outputGatePeripheral, "output gate"),
        _fieldController = FieldController.new({
            responseMultiplier = mergedConfig.fieldResponseMultiplier,
            trimMultiplier = mergedConfig.fieldTrimMultiplier,
        }),
        _outputController = OutputController.new(),
        _requestedMode = persistedState and persistedState.requestedMode or MODE_STOPPED,
        _desiredInputRate = normalizeRate(persistedState and persistedState.desiredInputRate or 0),
        _desiredOutputRate = normalizeRate(persistedState and persistedState.desiredOutputRate or 0),
        _appliedInputRate = normalizeRate(persistedState and persistedState.appliedInputRate or 0),
        _appliedOutputRate = normalizeRate(persistedState and persistedState.appliedOutputRate or 0),
        _lastShutdownReason = persistedState and persistedState.lastShutdownReason or nil,
        _lastInfo = nil,
        _lastWarnings = {},
        _lastError = stateError,
        _lastTelemetry = nil,
        _lastPeripheralHealth = {
            reactor = false,
            inputGate = false,
            outputGate = false,
        },
    }, ReactorController)

    local bootstrapSnapshot = self:_collectSnapshot(0)
    if stateError then
        bootstrapSnapshot.warnings[#bootstrapSnapshot.warnings + 1] = stateError
    end

    self._appliedInputRate = bootstrapSnapshot.currentInputRate
    self._appliedOutputRate = bootstrapSnapshot.currentOutputRate
    self._desiredInputRate = bootstrapSnapshot.currentInputRate
    self._desiredOutputRate = bootstrapSnapshot.currentOutputRate
    self._lastPeripheralHealth = {
        reactor = bootstrapSnapshot.reactorAvailable,
        inputGate = bootstrapSnapshot.inputGate.connected,
        outputGate = bootstrapSnapshot.outputGate.connected,
    }

    local bootstrapControlStatus = "stopped"
    if self._requestedMode == MODE_RUNNING then
        if bootstrapSnapshot.currentState == STATE_RUNNING then
            bootstrapControlStatus = "holding_output"
        elseif bootstrapSnapshot.currentState == STATE_STARTING or bootstrapSnapshot.currentState == STATE_OFF then
            bootstrapControlStatus = "starting"
        elseif bootstrapSnapshot.currentState == STATE_NEEDS_FUEL then
            bootstrapControlStatus = "needs_fuel"
        elseif bootstrapSnapshot.currentState == STATE_STOPPING then
            bootstrapControlStatus = "stopping"
        end
    end

    self._lastTelemetry = self:_makeStatus(
        bootstrapSnapshot.info,
        bootstrapSnapshot.currentState,
        self._appliedInputRate,
        self._appliedOutputRate,
        bootstrapControlStatus,
        bootstrapSnapshot.warnings,
        {}
    )
    self._lastWarnings = copyArray(bootstrapSnapshot.warnings)
    self._lastError = self._lastWarnings[1]

    return self
end

function ReactorController:getConfig()
    return copyTable(self._config)
end

function ReactorController:setConfig(config)
    if type(config) ~= "table" then
        error("config must be a table", 2)
    end

    self._config = normalizeConfig(self._config, config)
    self._statePath = self._config.statePath
    self._fieldController:updateConfig({
        responseMultiplier = self._config.fieldResponseMultiplier,
        trimMultiplier = self._config.fieldTrimMultiplier,
    })

    local persisted, persistError = self:_persistState()
    if not persisted then
        self._lastError = persistError
        self._lastWarnings[#self._lastWarnings + 1] = persistError
    end

    return self:getConfig()
end

function ReactorController:setTargetFieldPercent(value)
    return self:setConfig({ targetFieldPercent = value })
end

function ReactorController:setMinFieldPercent(value)
    return self:setConfig({ minFieldPercent = value })
end

function ReactorController:setTargetOutputRate(value)
    return self:setConfig({ targetOutputRate = value })
end

function ReactorController:setMaxTemperature(value)
    return self:setConfig({ maxTemperature = value })
end

function ReactorController:setCutOffTemperature(value)
    return self:setConfig({ cutOffTemperature = value })
end

function ReactorController:setRateRampPerSecond(value)
    return self:setConfig({
        rateRampPerSecond = value,
        outputRampPerSecond = value,
        inputRampDownPerSecond = value,
    })
end

function ReactorController:start()
    self._requestedMode = MODE_RUNNING
    self._lastShutdownReason = nil

    local persisted, persistError = self:_persistState()
    if not persisted then
        self._lastError = persistError
        self._lastWarnings[#self._lastWarnings + 1] = persistError
    end
end

function ReactorController:stop()
    self._requestedMode = MODE_STOPPED

    local persisted, persistError = self:_persistState()
    if not persisted then
        self._lastError = persistError
        self._lastWarnings[#self._lastWarnings + 1] = persistError
    end
end

function ReactorController:isRunningRequested()
    return self._requestedMode == MODE_RUNNING
end

function ReactorController:update(deltaTime)
    if deltaTime ~= nil and type(deltaTime) ~= "number" then
        error("deltaTime must be a number when provided", 2)
    end

    local snapshot = self:_collectSnapshot(deltaTime or 1)

    self._appliedInputRate = snapshot.currentInputRate
    self._appliedOutputRate = snapshot.currentOutputRate

    if not snapshot.reactorAvailable then
        return self:_holdRates(snapshot, "peripheral_error")
    end

    local plan = {
        desiredInputRate = snapshot.currentInputRate,
        desiredOutputRate = snapshot.currentOutputRate,
        keepInputMinimum = false,
        reportedState = snapshot.currentState,
        controlStatus = "holding_output",
        actions = {},
        warnings = copyArray(snapshot.warnings),
    }

    if self._requestedMode == MODE_STOPPED then
        plan.desiredOutputRate = 0

        if snapshot.currentState == STATE_RUNNING or snapshot.currentState == STATE_STARTING then
            self:_callReactor("stopReactor", plan, "stop_reactor")
            plan.desiredInputRate = self:_getStoppingInputRate(snapshot)
            plan.keepInputMinimum = true
            plan.reportedState = STATE_STOPPING
            plan.controlStatus = "stopping"
        elseif snapshot.currentState == STATE_STOPPING then
            plan.desiredInputRate = self:_getStoppingInputRate(snapshot)
            plan.keepInputMinimum = true
            plan.reportedState = STATE_STOPPING
            plan.controlStatus = "stopping"
        else
            plan.desiredInputRate = 0
            plan.controlStatus = "stopped"
        end

        return self:_applyPlan(snapshot, plan)
    end

    if snapshot.currentState == STATE_NEEDS_FUEL then
        plan.desiredInputRate = 0
        plan.desiredOutputRate = 0
        plan.controlStatus = "needs_fuel"
        plan.reportedState = STATE_NEEDS_FUEL
        return self:_applyPlan(snapshot, plan)
    end

    if snapshot.currentState == STATE_OFF then
        self:_callReactor("chargeReactor", plan, "charge_reactor")
        plan.desiredInputRate = self:_getStartupInputRate(snapshot)
        plan.desiredOutputRate = 0
        plan.keepInputMinimum = true
        plan.reportedState = STATE_STARTING
        plan.controlStatus = "starting"
        return self:_applyPlan(snapshot, plan)
    end

    if snapshot.currentState == STATE_STARTING then
        plan.desiredInputRate = self:_getStartupInputRate(snapshot)
        plan.desiredOutputRate = 0
        plan.keepInputMinimum = true
        plan.reportedState = STATE_STARTING
        plan.controlStatus = "starting"

        if self:_canActivate(snapshot) then
            self:_callReactor("activateReactor", plan, "activate_reactor")
        end

        return self:_applyPlan(snapshot, plan)
    end

    if snapshot.currentState == STATE_STOPPING then
        plan.desiredInputRate = self:_getStoppingInputRate(snapshot)
        plan.desiredOutputRate = 0
        plan.keepInputMinimum = true
        plan.reportedState = STATE_STOPPING
        plan.controlStatus = "stopping"
        return self:_applyPlan(snapshot, plan)
    end

    local shouldShutdown, shutdownKind, shutdownReason = self:_shouldShutdown(snapshot)
    if shouldShutdown then
        self._requestedMode = MODE_STOPPED
        self._lastShutdownReason = shutdownReason
        self:_callReactor("stopReactor", plan, "stop_reactor")
        plan.desiredInputRate = self:_getStoppingInputRate(snapshot)
        plan.desiredOutputRate = 0
        plan.keepInputMinimum = true
        plan.reportedState = STATE_STOPPING
        plan.controlStatus = shutdownKind == "emergency" and "shutdown_requested" or "refuel_shutdown"
        return self:_applyPlan(snapshot, plan)
    end

    local fieldResult = self._fieldController:calculate({
        currentInputRate = snapshot.currentInputRate,
        minInputRate = self._config.minInputRate,
        fieldDrainRate = snapshot.info.fieldDrainRate,
        fieldPercent = snapshot.fieldPercent,
        targetFieldPercent = self._config.targetFieldPercent,
        deltaTime = snapshot.deltaTime,
        inputRampDownPerSecond = self._config.inputRampDownPerSecond,
    })

    local outputResult = self._outputController:calculate({
        currentOutputRate = snapshot.currentOutputRate,
        targetOutputRate = self._config.targetOutputRate,
        fieldPercent = snapshot.fieldPercent,
        targetFieldPercent = self._config.targetFieldPercent,
        currentTemperature = snapshot.info.temperature,
        maxTemperature = self._config.maxTemperature,
        deltaTime = snapshot.deltaTime,
        outputRampUpPerSecond = self._config.outputRampPerSecond,
    })

    plan.desiredInputRate = fieldResult.desiredInputRate
    plan.desiredOutputRate = outputResult.desiredOutputRate
    plan.keepInputMinimum = true
    plan.reportedState = STATE_RUNNING

    if outputResult.delta > 0 then
        local compensatedInputRate = plan.desiredInputRate + (outputResult.delta * self._config.outputBoostCompensationRatio)
        plan.desiredInputRate = math.max(plan.desiredInputRate, compensatedInputRate)
    end

    if outputResult.reason == "waiting_for_field" then
        plan.controlStatus = "throttled_field"
    elseif outputResult.reason == "waiting_for_temperature" then
        plan.controlStatus = "throttled_temperature"
    elseif outputResult.reason == "ramping_output" then
        plan.controlStatus = "ramping_output"
    elseif outputResult.reason == "at_target_output" then
        plan.controlStatus = "at_target_output"
    elseif outputResult.reason == "reducing_output" then
        plan.controlStatus = "reducing_output"
    else
        plan.controlStatus = "idle_output"
    end

    return self:_applyPlan(snapshot, plan)
end

function ReactorController:getStatus()
    if self._lastTelemetry ~= nil then
        return copyTable(self._lastTelemetry)
    end

    local info = self._lastInfo or copyTable(EMPTY_REACTOR_INFO)
    return self:_makeStatus(
        info,
        self:_deriveState(info),
        self._appliedInputRate or 0,
        self._appliedOutputRate or 0,
        "stopped",
        self._lastWarnings,
        {}
    )
end

function ReactorController:getCurrentState()
    return self:getStatus().currentState
end

function ReactorController:getFieldPercent()
    return self:getStatus().fieldPercent
end

function ReactorController:getEnergySaturationPercent()
    return self:getStatus().energySaturationPercent
end

function ReactorController:getFuelPercent()
    return self:getStatus().fuelPercent
end

function ReactorController:getFuelUsageRate()
    return self:getStatus().fuelUsageRate
end

function ReactorController:getCurrentTemperature()
    return self:getStatus().currentTemperature
end

function ReactorController:getCurrentInputRate()
    return self:getStatus().currentInputRate
end

function ReactorController:getCurrentGateInput()
    return self:getCurrentInputRate()
end

function ReactorController:getCurrentGenerationRate()
    return self:getStatus().currentGenerationRate
end

function ReactorController:getCurrentOutputRate()
    return self:getStatus().currentOutputRate
end

function ReactorController:getCurrentGateOutput()
    return self:getCurrentOutputRate()
end

function ReactorController:getTargetOutputRate()
    return self:getStatus().targetOutputRate
end

function ReactorController:getNetPositiveRate()
    return self:getStatus().netPositiveRate
end

function ReactorController:getControlStatus()
    return self:getStatus().controlStatus
end

function ReactorController:getLastWarnings()
    return copyArray(self._lastWarnings)
end

function ReactorController:getLastError()
    return self._lastError
end

function ReactorController:isFieldBelowTarget()
    return self:getStatus().belowTargetField
end

function ReactorController:isFieldBelowMinimum()
    return self:getStatus().belowMinimumField
end

function ReactorController:isAboveMaxTemperature()
    return self:getStatus().aboveMaxTemperature
end

function ReactorController:isAboveCutOffTemperature()
    return self:getStatus().aboveCutOffTemperature
end

function ReactorController:isThrottled()
    return self:getStatus().isThrottled
end

function ReactorController:isProducingTargetOutput()
    return self:getStatus().producingTargetOutput
end

function ReactorController:hasPeripheralIssues()
    local status = self:getStatus()
    return not (status.peripherals.reactor and status.peripherals.inputGate and status.peripherals.outputGate)
end

return ReactorController
