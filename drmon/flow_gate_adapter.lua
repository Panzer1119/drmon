local Util = require("drmon.util")

local FlowGateAdapter = {}
FlowGateAdapter.__index = FlowGateAdapter

function FlowGateAdapter.new(gate, label)
    local gateLabel = label or "Flow gate"
    assert(type(gate) == "table", ("%s must be a wrapped peripheral"):format(gateLabel))
    Util.assertMethod(gate, "setFlowOverride", gateLabel)
    Util.assertMethod(gate, "getFlow", gateLabel)
    Util.assertMethod(gate, "setOverrideEnabled", gateLabel)
    Util.assertMethod(gate, "getOverrideEnabled", gateLabel)

    return setmetatable({
        gate = gate,
        label = gateLabel,
    }, FlowGateAdapter)
end

function FlowGateAdapter:takeControl()
    local currentRate = self:getRate()

    if not self.gate.getOverrideEnabled() then
        self.gate.setOverrideEnabled(true)
    end

    self.gate.setFlowOverride(currentRate)
    return currentRate
end

function FlowGateAdapter:getRate()
    return Util.roundRate(self.gate.getFlow())
end

function FlowGateAdapter:getActualFlow()
    return self:getRate()
end

function FlowGateAdapter:isUsingOverride()
    return self.gate.getOverrideEnabled()
end

function FlowGateAdapter:setRate(rate)
    local normalizedRate = Util.roundRate(rate)

    if not self.gate.getOverrideEnabled() then
        self.gate.setOverrideEnabled(true)
    end

    self.gate.setFlowOverride(normalizedRate)
    return normalizedRate
end

return FlowGateAdapter
