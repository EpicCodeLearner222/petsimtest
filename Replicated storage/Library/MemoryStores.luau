--!strict
-- Path: ReplicatedStorage/Modules/MemoryStores/MemoryStoreManager
local MemoryStoreService = game:GetService("MemoryStoreService")

local MemoryStoreManager = {}

-- Configuration -----------------------------------------------------------------
local RETRY_COUNT = 5                     -- number of attempts on failure
local RETRY_DELAY_BASE = 2                -- seconds, exponential backoff
local DEFAULT_TTL = 60                    -- default time‑to‑live in seconds (0 = no expiry)

-- Internal utilities ------------------------------------------------------------
local function waitWithBackoff(attempt)
    local delay = RETRY_DELAY_BASE * (2 ^ (attempt - 1))
    wait(delay)
end

-- Wrapper for operations with retry logic
local function withRetry(operation)
    for attempt = 1, RETRY_COUNT do
        local success, result = pcall(operation)
        if success then
            return result
        else
            if attempt == RETRY_COUNT then
                error("MemoryStore operation failed after " .. RETRY_COUNT .. " attempts: " .. tostring(result))
            else
                waitWithBackoff(attempt)
            end
        end
    end
    return nil -- should never reach here
end

-- Public API --------------------------------------------------------------------
-- Maps (key‑value storage) ------------------------------------------------------
--[[
    Sets a key‑value pair in a MemoryStoreMap.
    Parameters:
        mapName : string – name of the map
        key     : string – key within the map
        value   : any   – value to store (must be serializable)
        ttl     : number? – time‑to‑live in seconds (defaults to DEFAULT_TTL)
]]
function MemoryStoreManager.SetMapEntry(mapName, key, value, ttl)
    ttl = ttl or DEFAULT_TTL
    local map = MemoryStoreService:GetMap(mapName)
    withRetry(function()
        map:SetAsync(key, value, ttl)
    end)
end

--[[
    Retrieves a value from a MemoryStoreMap.
    Returns:
        value : any – stored value, or nil if not found
]]
function MemoryStoreManager.GetMapEntry(mapName, key)
    local map = MemoryStoreService:GetMap(mapName)
    return withRetry(function()
        return map:GetAsync(key)
    end)
end

--[[
    Removes a key from a MemoryStoreMap.
]]
function MemoryStoreManager.RemoveMapEntry(mapName, key)
    local map = MemoryStoreService:GetMap(mapName)
    withRetry(function()
        map:RemoveAsync(key)
    end)
end

--[[
    Atomically updates a map entry. Useful for counters or complex updates.
    The updater function receives the current value (or nil) and returns the new value.
    Example: 
        MemoryStoreManager.UpdateMapEntry("analytics", "clicks", function(current)
            return (current or 0) + 1
        end)
]]
function MemoryStoreManager.UpdateMapEntry(mapName, key, updater, ttl)
    ttl = ttl or DEFAULT_TTL
    local map = MemoryStoreService:GetMap(mapName)
    local newValue = withRetry(function()
        return map:UpdateAsync(key, updater, ttl)
    end)
    return newValue
end

-- Queues (FIFO / message queues) ------------------------------------------------
--[[
    Adds an item to a MemoryStoreQueue.
    Parameters:
        queueName : string – name of the queue
        value     : any   – item to add
        ttl       : number? – time‑to‑live in seconds (defaults to DEFAULT_TTL)
]]
function MemoryStoreManager.AddToQueue(queueName, value, ttl)
    ttl = ttl or DEFAULT_TTL
    local queue = MemoryStoreService:GetQueue(queueName)
    withRetry(function()
        queue:AddAsync(value, ttl)
    end)
end

--[[
    Reads (and optionally removes) items from a queue.
    Parameters:
        queueName : string – name of the queue
        count     : number – max number of items to read (default 1)
        remove    : boolean – if true, items are removed after reading (default false)
    Returns:
        items : table – array of items, each containing {id = string, value = any}
]]
function MemoryStoreManager.ReadQueue(queueName, count, remove)
    count = count or 1
    remove = remove or false
    local queue = MemoryStoreService:GetQueue(queueName)
    return withRetry(function()
        return queue:ReadAsync(count, remove)
    end)
end

--[[
    Removes specific items from a queue by their IDs (obtained from ReadAsync).
]]
function MemoryStoreManager.RemoveFromQueue(queueName, itemIds)
    local queue = MemoryStoreService:GetQueue(queueName)
    withRetry(function()
        queue:RemoveAsync(itemIds)
    end)
end

-- Sorted Maps (leaderboards / scoring) ------------------------------------------
--[[
    Adds or updates a score in a sorted map.
    Parameters:
        mapName : string – name of the sorted map
        key     : string – item identifier (e.g., player ID)
        score   : number – score to set
        ttl     : number? – time‑to‑live in seconds for the entire entry (0 = no expiry)
]]
function MemoryStoreManager.SetSortedMapScore(mapName, key, score, ttl)
    ttl = ttl or 0  -- sorted maps typically don't auto‑expire, but allow it
    local sortedMap = MemoryStoreService:GetSortedMap(mapName)
    withRetry(function()
        sortedMap:SetAsync(key, score, ttl)
    end)
end

--[[
    Gets a score from a sorted map.
]]
function MemoryStoreManager.GetSortedMapScore(mapName, key)
    local sortedMap = MemoryStoreService:GetSortedMap(mapName)
    return withRetry(function()
        return sortedMap:GetAsync(key)
    end)
end

--[[
    Gets a range of entries from a sorted map.
    Parameters:
        mapName  : string
        startKey : string? – starting key (nil = start from beginning)
        count    : number  – number of entries to fetch
        ascending: boolean – true for ascending order, false for descending (default false)
    Returns:
        entries : table – array of {key = string, score = number}
]]
function MemoryStoreManager.GetSortedMapRange(mapName, startKey, count, ascending)
    local sortedMap = MemoryStoreService:GetSortedMap(mapName)
    return withRetry(function()
        return sortedMap:GetRangeAsync(startKey, count, ascending)
    end)
end

--[[
    Removes an entry from a sorted map.
]]
function MemoryStoreManager.RemoveSortedMapEntry(mapName, key)
    local sortedMap = MemoryStoreService:GetSortedMap(mapName)
    withRetry(function()
        sortedMap:RemoveAsync(key)
    end)
end

-- Convenience Helpers for Analytics ---------------------------------------------
--[[
    Increments a counter in a map by a given delta (default 1).
    Example: MemoryStoreManager.IncrementCounter("daily_clicks", "2025-04-01", 1)
]]
function MemoryStoreManager.IncrementCounter(mapName, key, delta, ttl)
    delta = delta or 1
    return MemoryStoreManager.UpdateMapEntry(mapName, key, function(current)
        return (current or 0) + delta
    end, ttl)
end

--[[
    Logs an error or debug message to a queue for later consumption.
    The data table can contain any fields (e.g., message, timestamp, stack).
]]
function MemoryStoreManager.LogEvent(queueName, data, ttl)
    ttl = ttl or 300  -- 5 minutes default for logs
    MemoryStoreManager.AddToQueue(queueName, data, ttl)
end

return MemoryStoreManager
