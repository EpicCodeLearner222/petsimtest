--!strict
-- Path: ReplicatedStorage/Library/Worlds.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryStoreManager = require(script.Parent.MemoryStores)   -- adjust path if needed

-- Configuration ----------------------------------------------------------------
local WORLDS_FOLDER = script.Parent.Worlds   -- folder containing world modules

-- Table to hold loaded worlds
local Worlds = {}

-- Table to track loaded world names for duplicate detection
local loadedNames = {}

-- Function to log errors using MemoryStore
local function logError(moduleName, err)
    local errorData = {
        source = "WorldsLoader",
        module = moduleName,
        error = tostring(err),
        timestamp = os.time(),
        stack = debug.traceback()
    }
    -- Use the LogEvent helper from MemoryStoreManager (assumed to exist)
    if MemoryStoreManager and MemoryStoreManager.LogEvent then
        MemoryStoreManager.LogEvent("error_logs", errorData, 3600)
    else
        warn("Could not log to MemoryStore – error details:", errorData)
    end
end

-- Scan the Worlds folder and load all module scripts
if WORLDS_FOLDER and WORLDS_FOLDER:IsA("Folder") then
    for _, child in ipairs(WORLDS_FOLDER:GetChildren()) do
        if child:IsA("ModuleScript") then
            local success, worldData = pcall(function()
                return require(child)
            end)
            if not success then
                warn("Failed to load world module:", child.Name, worldData)
                logError(child.Name, worldData)
            else
                -- Validate that worldData is a table
                if type(worldData) ~= "table" then
                    warn("World module", child.Name, "did not return a table")
                    logError(child.Name, "Return value is not a table")
                else
                    -- Determine the key for this world
                    local key = worldData.Name
                    if not key or type(key) ~= "string" then
                        key = child.Name   -- fallback to module file name
                    end

                    -- Check for duplicate keys
                    if loadedNames[key] then
                        warn("Duplicate world name '", key, "' found in module", child.Name, ". Skipping.")
                        logError(child.Name, "Duplicate world name: " .. key)
                    else
                        loadedNames[key] = true
                        Worlds[key] = worldData
                        print("Loaded world:", key)
                    end
                end
            end
        end
    end
else
    warn("Worlds folder not found at:", WORLDS_FOLDER and WORLDS_FOLDER:GetFullName() or "nil")
end

-- Optional: Helper function to get a world by name (with error handling)
function Worlds.GetWorld(name)
    local world = Worlds[name]
    if not world then
        warn("World not found:", name)
    end
    return world
end

-- Return the world table for other scripts
return Worlds
