--!nonstrict
-- Store and clock injection allow tests to execute this exact persistence logic.
local DataService = {}
DataService.StoreName = "Flowers_PlayerData"
DataService.AutosaveSeconds = 60
DataService.LeaseSeconds = 180
DataService.MaxAttempts = 4 -- Initial call plus three retries.

function DataService.new(store, schema, dependencies)
    local wait = dependencies.wait
    local now = dependencies.now
    local token = dependencies.token
    local report = dependencies.report
    local service = {}

    local function retry(callback)
        local problem
        for attempt = 1, DataService.MaxAttempts do
            local ok, value = pcall(callback)
            if ok then return true, value end
            problem = value
            if attempt < DataService.MaxAttempts then wait(attempt * 2) end
        end
        report("[Flowers/Data] DataStore request failed: " .. tostring(problem))
        return false, nil
    end

    function service.Load(userId)
        local handle = {Key="Player_" .. tostring(userId), Token=token(),
            Writable=false, Busy=false, Closing=false, Closed=false}
        local ok, saved = retry(function()
            return store:UpdateAsync(handle.Key, function(old)
                local data
                if old == nil then data = schema.Default() else data = schema.Decode(old) end
                if not data then return nil end
                if old and old.session and old.session.token ~= handle.Token
                    and old.session.expires > now() then
                    error("Profile is active on another server")
                end
                data.session = {token=handle.Token, expires=now() + DataService.LeaseSeconds}
                return data
            end)
        end)
        if ok and saved and saved.session and saved.session.token == handle.Token then
            handle.Writable = true
            return handle, schema.Decode(saved)
        end
        report("[Flowers/Data] Temporary profile for " .. tostring(userId) .. "; saving disabled.")
        return handle, schema.Default()
    end

    function service.Save(handle, snapshot, release)
        if handle.Busy and not release then return false end
        if release then handle.Closing = true end
        while handle.Busy do wait(0.05) end
        if handle.Closed or (handle.Closing and not release) then return false end
        if not handle.Writable then
            if release then handle.Closed = true end
            return false
        end
        local data = schema.Decode(snapshot)
        if not data then
            report("[Flowers/Data] Invalid snapshot; existing data preserved.")
            return false
        end
        handle.Busy = true
        local ok, saved = retry(function()
            return store:UpdateAsync(handle.Key, function(old)
                if not schema.Decode(old) or not old.session
                    or old.session.token ~= handle.Token or old.session.expires <= now() then
                    return nil
                end
                local nextData = schema.Decode(data)
                if not release then
                    nextData.session = {token=handle.Token, expires=now() + DataService.LeaseSeconds}
                end
                return nextData
            end)
        end)
        handle.Busy = false
        if ok and not saved then handle.Writable = false end
        if release then handle.Closed = true end
        return ok and saved ~= nil
    end
    return service
end

return DataService
