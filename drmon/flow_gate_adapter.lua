local Util = require("drmon.util")

local FlowGateAdapter = {}
FlowGateAdapter.__index = FlowGateAdapter

local function hasMethod(object, methodName)
    return type(object[methodName]) == "function"
end

function FlowGateAdapter.new(gate, label)
    assert(type(gate) == "table", ("%s must be a wrapped peripheral"):format(label or "Flow gate"))

    local self = setmetatable({
        gate = gate,
        label = label or "Flow gate",
        supportsOverride = hasMethod(gate, "setOverrideEnabled")
            and hasMethod(gate, "getOverrideEnabled")
            and hasMethod(gate, "setFlowOverride")
            and hasMethod(gate, "getFlowOverride"),
    }, FlowGateAdapter)

    if not self.supportsOverride then
        Util.assertMethod(gate, "getSignalLowFlow", self.label)
        Util.assertMethod(gate, "setSignalLowFlow", self.label)
    end

    return self
end

function FlowGateAdapter:_readApproximateCurrentRate()
    if self.supportsOverride and self.gate.getOverrideEnabled() then
        return Util.roundRate(self.gate.getFlowOverride())
    end

    if hasMethod(self.gate, "getFlow") then
        return Util.roundRate(self.gate.getFlow())
    end

    if hasMethod(self.gate, "getSignalLowFlow") then
        return Util.roundRate(self.gate.getSignalLowFlow())
    end

    return 0
end

function FlowGateAdapter:takeControl()
    local currentRate = self:_readApproximateCurrentRate()

    if self.supportsOverride then
        if not self.gate.getOverrideEnabled() then
            self.gate.setOverrideEnabled(true)
        end

        self.gate.setFlowOverride(currentRate)
    end

    return currentRate
end

function FlowGateAdapter:getRate()
    if self.supportsOverride then
        if self.gate.getOverrideEnabled() then
            return Util.roundRate(self.gate.getFlowOverride())
        end

        return self:_readApproximateCurrentRate()
    end

    return Util.roundRate(self.gate.getSignalLowFlow())
end

function FlowGateAdapter:getActualFlow()
    if hasMethod(self.gate, "getFlow") then
        return Util.roundRate(self.gate.getFlow())
    end

    return self:getRate()
end

function FlowGateAdapter:isUsingOverride()
    return self.supportsOverride and self.gate.getOverrideEnabled()
end

function FlowGateAdapter:setRate(rate)
    local normalizedRate = Util.roundRate(rate)

    if self.supportsOverride then
        if not self.gate.getOverrideEnabled() then
            self.gate.setOverrideEnabled(true)
        end

        self.gate.setFlowOverride(normalizedRate)
        return normalizedRate
    end

    self.gate.setSignalLowFlow(normalizedRate)
    return normalizedRate
end

return FlowGateAdapter
