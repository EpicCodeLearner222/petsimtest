--!strict
-- Path: ReplicatedStorage/Library/Worlds/Worlds.luau

local MemoryStore = require(script.Parent.Parent.MemoryStores)

-- Utility to log errors to MemoryStore
local function logError(worldName, errMsg)
    local errorData = {
        type = "WorldsModule",
        world = worldName or "Unknown",
        message = errMsg,
        timestamp = os.time()
    }
    -- Use the MemoryStore queue for error logging (5 minute TTL)
    MemoryStore.LogEvent("world_errors", errorData, 300)
end

-- Build the world registry ----------------------------------------------------
local worldsByName = {}
local worldsByNumber = {}
local worldsList = {}   -- ordered list of worlds (by number)

-- Scan the folder (parent of this script) for module scripts
local folder = script.Parent
for _, child in ipairs(folder:GetChildren()) do
    if child:IsA("ModuleScript") then
        local worldName = child.Name
        local success, module = pcall(require, child)
        if not success then
            -- Require failed – log error and skip this world
            logError(worldName, "Require failed: " .. tostring(module))
            warn("[Worlds] Failed to load world '" .. worldName .. "': " .. tostring(module))
            continue
        end

        -- Validate that module has WorldData
        if type(module) ~= "table" or type(module.WorldData) ~= "table" then
            logError(worldName, "Module does not return a table with WorldData field")
            warn("[Worlds] World '" .. worldName .. "' is missing WorldData field")
            continue
        end

        local data = module.WorldData

        -- Validate required fields (Name and Number are essential)
        if not data.Name or type(data.Name) ~= "string" then
            logError(worldName, "WorldData missing Name (string)")
            warn("[Worlds] World '" .. worldName .. "' missing Name")
            continue
        end
        if not data.Number or type(data.Number) ~= "number" then
            logError(worldName, "WorldData missing Number (number)")
            warn("[Worlds] World '" .. worldName .. "' missing Number")
            continue
        end

        -- Check for duplicate name
        if worldsByName[data.Name] then
            logError(worldName, "Duplicate world name: " .. data.Name)
            warn("[Worlds] Duplicate world name '" .. data.Name .. "' – skipping " .. worldName)
            continue
        end
        -- Check for duplicate number
        if worldsByNumber[data.Number] then
            logError(worldName, "Duplicate world number: " .. tostring(data.Number))
            warn("[Worlds] Duplicate world number " .. tostring(data.Number) .. " – skipping " .. worldName)
            continue
        end

        -- Optional fields – ensure Teleport is a CFrame (or handle if missing)
        if data.Teleport == nil then
            logError(worldName, "WorldData missing Teleport – using default")
            warn("[Worlds] World '" .. data.Name .. "' missing Teleport, using default CFrame")
            data.Teleport = CFrame.new(0, 5, 0)
        elseif not data.Teleport:IsA("CFrame") then
            logError(worldName, "Teleport is not a CFrame")
            warn("[Worlds] World '" .. data.Name .. "' Teleport is not a CFrame, using default")
            data.Teleport = CFrame.new(0, 5, 0)
        end

        -- If Interactive is missing, set to empty table
        if data.Interactive == nil then
            data.Interactive = {}
        end
        -- If Breakables is missing, set to empty table
        if data.Breakables == nil then
            data.Breakables = {}
        end

        -- Ensure Cost is a number (default 0)
        if data.Cost == nil then
            data.Cost = 0
        elseif type(data.Cost) ~= "number" then
            logError(worldName, "Cost is not a number, setting to 0")
            data.Cost = 0
        end

        -- Insert into registry
        worldsByName[data.Name] = data
        worldsByNumber[data.Number] = data
        worldsList[data.Number] = data   -- direct index by number (if numbers are consecutive)

        print("[Worlds] Loaded world: " .. data.Name .. " (#" .. data.Number .. ")")
    end
end

-- Sort worldsList by number for ordered iteration
local sortedWorlds = {}
for _, world in pairs(worldsByName) do
    table.insert(sortedWorlds, world)
end
table.sort(sortedWorlds, function(a, b) return a.Number < b.Number end)

-- Public API -------------------------------------------------------------------
local Worlds = {}

--[[
    Returns all world data as a table indexed by name.
]]
function Worlds.GetAllByName()
    return worldsByName
end

--[[
    Returns all world data as a table indexed by number.
]]
function Worlds.GetAllByNumber()
    return worldsByNumber
end

--[[
    Returns a list of worlds sorted by their Number.
]]
function Worlds.GetSortedList()
    return sortedWorlds
end

--[[
    Gets a world by its name.
    Returns nil if not found.
]]
function Worlds.GetByName(name)
    return worldsByName[name]
end

--[[
    Gets a world by its number.
    Returns nil if not found.
]]
function Worlds.GetByNumber(num)
    return worldsByNumber[num]
end

--[[
    Returns the total number of worlds loaded.
]]
function Worlds.GetCount()
    local count = 0
    for _ in pairs(worldsByName) do count = count + 1 end
    return count
end

return Worlds
