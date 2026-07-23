local M = {}


function M.new()

    return {

        reactor = nil,
        input = nil,
        output = nil,

        connected = false,

        currentOutput = 0
    }

end



function M.connect(self)

    self.reactor = peripheral.find("draconic_reactor")

    local gates = { peripheral.find("flow_gate") }

    if not self.reactor or #gates < 2 then

        self.connected = false
        return false

    end

    self.input = gates[1]
    self.output = gates[2]

    self.input.setOverrideEnabled(true)
    self.output.setOverrideEnabled(true)

    self.connected = true

    return true

end



function M.safeCall(self, method, ...)

    if not self.connected then
        return nil
    end

    local ok, result = pcall(
        self.reactor[method],
        ...
    )

    if not ok then

        self.connected = false
        return nil

    end

    return result

end



function M.stop(self)

    self:safeCall("stopReactor")

end



function M.charge(self)

    self:safeCall("chargeReactor")

end



function M.activate(self)

    self:safeCall("activateReactor")

end


function M.info(self)

    return self:safeCall("getReactorInfo")

end



function M.setGates(
    self,
    input,
    output
)

    if not self.connected then
        return
    end

    -- IMPORTANT:
    -- input first to protect shield

    pcall(self.input.setFlowOverride, input)

    pcall(self.output.setFlowOverride, output)

end


return M
