--!strict
-- Path: ServerScriptService/MainPlayerData.luau

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Require dependencies
local DataStoreManager = require(ReplicatedStorage.Library.DataStores)
local CurrencyDefs = {}  -- will be populated from all currency modules

-- Populate CurrencyDefs by scanning the Currency folder
local CurrencyFolder = ReplicatedStorage.Library.Currency
for _, module in ipairs(CurrencyFolder:GetChildren()) do
    if module:IsA("ModuleScript") then
        local currencyName = module.Name
        local def = require(module)
        CurrencyDefs[currencyName] = def
    end
end

-- Configuration ----------------------------------------------------------------
local DATA_STORE_NAME = "PlayerData"
local DATA_STORE_SCOPE = "v1"
local LOCK_DURATION = 30  -- seconds

-- Private storage --------------------------------------------------------------
local playerDataCache = {}   -- [player] = data table
local playerLocks = {}       -- [player] = lock token

-- Helper: Get initial data structure ------------------------------------------
local function getDefaultData()
    local data = {}
    for currencyName, def in pairs(CurrencyDefs) do
        data[currencyName] = def.StartingBalance or 0
    end
    data.LastSaveTime = os.time()
    return data
end

-- Helper: Validate and sanitize loaded data -----------------------------------
local function validateData(data)
    if type(data) ~= "table" then
        return getDefaultData()
    end
    -- Ensure every defined currency exists; fill missing with default starting balance
    for currencyName, def in pairs(CurrencyDefs) do
        if data[currencyName] == nil then
            data[currencyName] = def.StartingBalance or 0
        elseif type(data[currencyName]) ~= "number" then
            data[currencyName] = def.StartingBalance or 0
        end
    end
    -- Remove any extra keys that aren't currencies (optional, but keep LastSaveTime)
    for key in pairs(data) do
        if key ~= "LastSaveTime" and CurrencyDefs[key] == nil then
            data[key] = nil
        end
    end
    if type(data.LastSaveTime) ~= "number" then
        data.LastSaveTime = os.time()
    end
    return data
end

-- Load player data from DataStore ---------------------------------------------
local function loadPlayerData(player)
    local playerKey = "Player_" .. player.UserId
    local data, lockToken, err = DataStoreManager.GetAsync(
        DATA_STORE_NAME,
        playerKey,
        DATA_STORE_SCOPE,
        true,          -- useLock = true
        LOCK_DURATION
    )
    if err then
        warn("Failed to load data for", player.Name, ":", err)
        return false
    end
    if data == nil then
        data = getDefaultData()
    else
        data = validateData(data)
    end
    playerDataCache[player] = data
    playerLocks[player] = lockToken
    return true
end

-- Save player data to DataStore ------------------------------------------------
local function savePlayerData(player)
    local data = playerDataCache[player]
    if not data then return false end
    local lockToken = playerLocks[player]
    if not lockToken then
        warn("No lock token for", player.Name, "– cannot save")
        return false
    end
    -- Update last save time
    data.LastSaveTime = os.time()
    local success, err = DataStoreManager.SetAsync(
        DATA_STORE_NAME,
        "Player_" .. player.UserId,
        data,
        DATA_STORE_SCOPE,
        lockToken
    )
    if not success then
        warn("Failed to save data for", player.Name, ":", err)
        return false
    end
    return true
end

-- Public API (exposed via global or module) -----------------------------------
--[[
    Get the current balance of a currency for a player.
]]
local function getBalance(player, currencyName)
    local data = playerDataCache[player]
    if not data then return nil end
    return data[currencyName]
end

--[[
    Add a certain amount to a player's currency.
    Returns the new balance.
]]
local function addCurrency(player, currencyName, amount)
    local data = playerDataCache[player]
    if not data then return nil end
    if type(amount) ~= "number" or amount <= 0 then
        error("Amount must be a positive number")
    end
    local current = data[currencyName] or 0
    local new = current + amount
    data[currencyName] = new
    return new
end

--[[
    Remove a certain amount from a player's currency (if enough).
    Returns true if successful, false if insufficient balance.
]]
local function removeCurrency(player, currencyName, amount)
    local data = playerDataCache[player]
    if not data then return false end
    if type(amount) ~= "number" or amount <= 0 then
        error("Amount must be a positive number")
    end
    local current = data[currencyName] or 0
    if current < amount then return false end
    data[currencyName] = current - amount
    return true
end

--[[
    Set a player's currency balance directly.
]]
local function setBalance(player, currencyName, amount)
    local data = playerDataCache[player]
    if not data then return false end
    if type(amount) ~= "number" then
        error("Amount must be a number")
    end
    data[currencyName] = amount
    return true
end

--[[
    Force a save for a player (useful before critical operations).
]]
local function savePlayer(player)
    return savePlayerData(player)
end

--[[
    Get the entire data table (use cautiously).
]]
local function getData(player)
    return playerDataCache[player]
end

-- Player connection handlers ---------------------------------------------------
local function onPlayerAdded(player)
    -- Load data (will yield)
    local success = loadPlayerData(player)
    if not success then
        -- If loading fails, we can still let them play with default data,
        -- but they won't be able to save.
        playerDataCache[player] = getDefaultData()
        warn("Using default data for", player.Name, "– saving disabled")
        -- In a real game, you might want to retry or kick the player.
    end
end

local function onPlayerRemoving(player)
    -- Save data on leave
    savePlayerData(player)
    -- Clean up cache
    playerDataCache[player] = nil
    playerLocks[player] = nil
end

-- Initialization --------------------------------------------------------------
if RunService:IsServer() then
    -- Connect existing players
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(onPlayerAdded, player)
    end
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)
end

-- Make functions globally available for other scripts
-- (You can also require this script from other server scripts)
_G.PlayerData = {
    GetBalance = getBalance,
    AddCurrency = addCurrency,
    RemoveCurrency = removeCurrency,
    SetBalance = setBalance,
    SavePlayer = savePlayer,
    GetData = getData,
    CurrencyDefs = CurrencyDefs  -- expose definitions if needed
}
