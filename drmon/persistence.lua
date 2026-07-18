local Persistence = {}
Persistence.__index = Persistence

function Persistence.new(path)
    assert(type(path) == "string" and path ~= "", "statePath must be a non-empty string")

    return setmetatable({
        path = path,
    }, Persistence)
end

function Persistence:load()
    if not fs.exists(self.path) then
        return nil
    end

    local handle = assert(fs.open(self.path, "r"), ("failed to open state file for reading: %s"):format(self.path))
    local raw = handle.readAll()
    handle.close()

    if raw == "" then
        return nil
    end

    local data = textutils.unserialize(raw)
    assert(type(data) == "table", ("state file is corrupt or unreadable: %s"):format(self.path))

    return data
end

function Persistence:save(data)
    assert(type(data) == "table", "state data must be a table")

    local directory = fs.getDir(self.path)
    if directory ~= "" then
        fs.makeDir(directory)
    end

    local handle = assert(fs.open(self.path, "w"), ("failed to open state file for writing: %s"):format(self.path))
    handle.write(textutils.serialize(data))
    handle.close()
end

return Persistence
