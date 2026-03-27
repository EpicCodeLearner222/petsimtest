--!strict
-- Path: ReplicatedStorage.Library.DataStores.DataStoreManager
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")

local DataStoreManager = {}

-- Configuration -----------------------------------------------------------------
local RETRY_COUNT = 5                     -- number of attempts on failure
local RETRY_DELAY_BASE = 2                -- seconds, exponential backoff
local DEFAULT_LOCK_DURATION = 60          -- seconds a lock is held
local LOCK_KEY_PREFIX = "lock_"           -- prefix for lock keys

-- Internal utilities ------------------------------------------------------------
local function getDataStore(storeName, scope)
    return DataStoreService:GetDataStore(storeName, scope)
end

local function getLockMap()
    return MemoryStoreService:GetMap("DataStoreLocks")
end

local function generateLockToken()
    return HttpService:GenerateGUID(false)
end

local function waitWithBackoff(attempt)
    local delay = RETRY_DELAY_BASE * (2 ^ (attempt - 1))
    wait(delay)
end

-- Public API --------------------------------------------------------------------
--[[
    Retrieves data from a DataStore. Locking is optional.

    Parameters:
        storeName   : string  – name of the DataStore
        key         : string  – key within the DataStore
        scope       : string? – DataStore scope (default nil)
        useLock     : boolean – if true, acquire a lock for DEFAULT_LOCK_DURATION seconds
        lockDuration: number? – override lock duration (only if useLock = true)

    Returns:
        data       : any – stored value (or nil if not found)
        lockToken  : string – token needed to release lock (only if lock acquired)
        error      : string – error message if any
]]
function DataStoreManager.GetAsync(storeName, key, scope, useLock, lockDuration)
    local ds = getDataStore(storeName, scope)
    local lockMap = getLockMap()
    local lockKey = LOCK_KEY_PREFIX .. key
    local lockToken = nil

    -- Acquire lock if requested
    if useLock then
        local duration = lockDuration or DEFAULT_LOCK_DURATION
        lockToken = generateLockToken()
        local success, err = pcall(function()
            lockMap:SetAsync(lockKey, lockToken, duration)
        end)
        if not success then
            return nil, nil, "Failed to acquire lock: " .. tostring(err)
        end
    end

    -- Get data with retries
    local data, err
    for attempt = 1, RETRY_COUNT do
        local success, result = pcall(function()
            return ds:GetAsync(key)
        end)
        if success then
            data = result
            err = nil
            break
        else
            err = tostring(result)
            if attempt < RETRY_COUNT then
                waitWithBackoff(attempt)
            end
        end
    end

    -- If get failed, release lock before returning
    if err then
        if lockToken then
            pcall(function()
                lockMap:RemoveAsync(lockKey, lockToken)
            end)
        end
        return nil, nil, "GetAsync failed: " .. err
    end

    return data, lockToken, nil
end

--[[
    Saves data to a DataStore. If a lockToken is provided, it must match the
    current lock for the key; otherwise the save is rejected.

    Parameters:
        storeName : string  – name of the DataStore
        key       : string  – key within the DataStore
        value     : any     – data to save (must be serializable)
        scope     : string? – DataStore scope (default nil)
        lockToken : string? – token obtained from GetAsync (optional)

    Returns:
        success : boolean – true if saved successfully
        error   : string  – error message if any
]]
function DataStoreManager.SetAsync(storeName, key, value, scope, lockToken)
    local ds = getDataStore(storeName, scope)
    local lockMap = getLockMap()
    local lockKey = LOCK_KEY_PREFIX .. key

    -- Verify lock token if provided
    if lockToken then
        local currentToken = pcall(function()
            return lockMap:GetAsync(lockKey)
        end)
        if currentToken ~= lockToken then
            return false, "Lock token mismatch or lock expired"
        end
    end

    -- Set data with retries
    for attempt = 1, RETRY_COUNT do
        local success, err = pcall(function()
            ds:SetAsync(key, value)
        end)
        if success then
            -- Release lock after successful save
            if lockToken then
                pcall(function()
                    lockMap:RemoveAsync(lockKey, lockToken)
                end)
            end
            return true, nil
        else
            if attempt < RETRY_COUNT then
                waitWithBackoff(attempt)
            else
                return false, tostring(err)
            end
        end
    end
    return false, "Max retries reached"
end

--[[
    Performs an atomic update using DataStore:UpdateAsync. Locking is optional.

    Parameters:
        storeName   : string   – name of the DataStore
        key         : string   – key within the DataStore
        updater     : function – function that receives the current value and returns the new value
        scope       : string?  – DataStore scope (default nil)
        useLock     : boolean  – if true, acquire a lock before update
        lockDuration: number?  – lock duration (only if useLock = true)

    Returns:
        newValue : any – the updated value (or nil on failure)
        error    : string – error message if any
]]
function DataStoreManager.UpdateAsync(storeName, key, updater, scope, useLock, lockDuration)
    local ds = getDataStore(storeName, scope)
    local lockMap = getLockMap()
    local lockKey = LOCK_KEY_PREFIX .. key
    local lockToken = nil

    -- Acquire lock if requested
    if useLock then
        local duration = lockDuration or DEFAULT_LOCK_DURATION
        lockToken = generateLockToken()
        local lockSuccess, lockErr = pcall(function()
            lockMap:SetAsync(lockKey, lockToken, duration)
        end)
        if not lockSuccess then
            return nil, "Failed to acquire lock: " .. tostring(lockErr)
        end
    end

    -- Perform atomic update
    local success, result
    for attempt = 1, RETRY_COUNT do
        local ok, data = pcall(function()
            return ds:UpdateAsync(key, updater)
        end)
        if ok then
            success = true
            result = data
            break
        else
            if attempt < RETRY_COUNT then
                waitWithBackoff(attempt)
            else
                success = false
                result = tostring(data)
            end
        end
    end

    -- Release lock if we acquired one
    if lockToken then
        pcall(function()
            lockMap:RemoveAsync(lockKey, lockToken)
        end)
    end

    if success then
        return result, nil
    else
        return nil, result
    end
end

--[[
    Explicitly releases a lock, if you need to do so before the TTL expires.
]]
function DataStoreManager.ReleaseLock(storeName, key, lockToken, scope)
    local lockMap = getLockMap()
    local lockKey = LOCK_KEY_PREFIX .. key
    local success, err = pcall(function()
        lockMap:RemoveAsync(lockKey, lockToken)
    end)
    return success, err
end

return DataStoreManager
