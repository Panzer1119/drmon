local CONFIG_FILE = "reactor_controller.cfg"

local defaultConfig = {
    targetFieldPercent = 10,
    minFieldPercent = 5,

    maxTemperature = 8000,

    requestedOutputRate = 1000000,
    minimumInputRate = 250000,
    chargeRate = 1000000,

    outputRampPercent = 0.05,
    outputRampMinimum = 10000,

    desiredState = "off",

    loopDelay = 0.1
}


local M = {}


local function copyDefaults(target)
    for k, v in pairs(defaultConfig) do
        if target[k] == nil then
            target[k] = v
        end
    end
end


function M.load()

    if not fs.exists(CONFIG_FILE) then
        M.save(defaultConfig)
        data = {}
        copyDefaults(data)
        return data
    end


    local file = fs.open(CONFIG_FILE,"r")
    local data = textutils.unserialize(file.readAll())
    file.close()


    if type(data) ~= "table" then
        data = {}
    end


    copyDefaults(data)

    return data
end



function M.save(config)

    local file = fs.open(CONFIG_FILE,"w")

    file.write(textutils.serialize(config))

    file.close()

end


return M
