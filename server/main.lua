local calls = {}
local callCount = 0

-- QBCore is only needed for the job-filtered broadcast; keep the resource
-- functional without it (falls back to the old broadcast-to-everyone).
local QBCore = nil
pcall(function() QBCore = exports['qb-core']:GetCoreObject() end)

---@param data table Freshly reported alert
---@return table|nil The existing call this alert merged into, or nil
-- Repeated identical alerts (same alert type, close together in time AND
-- space) collapse into one call with a bumped `count` instead of stacking a
-- new popup + blip + list entry per occurrence — think six shots-fired
-- reports from one shootout. The old code tried this with
-- `calls[#calls] == data`, which compares table IDENTITY in Lua and
-- therefore never matched anything.
local function tryMergeCall(data)
    local merge = Config.CallMerge
    if not merge or merge.Enabled == false then return nil end

    local windowMs = (merge.Window or 45) * 1000
    local radiusSq = (merge.Radius or 50.0) ^ 2
    local now = os.time() * 1000

    for i = #calls, 1, -1 do
        local call = calls[i]
        if (now - call.time) > windowMs then break end -- list is time-ordered
        if call.codeName == data.codeName then
            local dx = (call.coords.x or 0) - (data.coords.x or 0)
            local dy = (call.coords.y or 0) - (data.coords.y or 0)
            if (dx * dx + dy * dy) <= radiusSq then
                call.count = (call.count or 1) + 1
                call.time = now
                call.coords = data.coords -- follow the most recent sighting
                if data.information then call.information = data.information end
                -- Escalation: a call this many reports deep is no longer
                -- routine. The rebroadcast carries the new priority, so a
                -- popup still on screen flips red in place.
                local escalateAt = merge.EscalateAt or 0
                if escalateAt > 0 and call.count >= escalateAt and call.priority ~= 1 then
                    call.priority = 1
                    call.escalated = true
                end
                return call
            end
        end
    end
    return nil
end

---@param data table The call to deliver
-- Sends the alert only to players whose job matches the call's target jobs.
-- The old `TriggerClientEvent(..., -1)` shipped every alert to EVERY client
-- (including all civilians), each of which then filtered it away — wasted
-- bandwidth and event handling that scales with slot count.
local function broadcastCall(data)
    if Config.FilteredBroadcast == false or not QBCore then
        TriggerClientEvent('ps-dispatch:client:notify', -1, data)
        return
    end

    local players = QBCore.Functions.GetQBPlayers()
    for src, player in pairs(players) do
        local job = player.PlayerData and player.PlayerData.job
        if job and (lib.table.contains(data.jobs, job.type) or lib.table.contains(data.jobs, job.name)) then
            if Config.FilterOnDuty == false or job.onduty then
                TriggerClientEvent('ps-dispatch:client:notify', src, data)
            end
        end
    end
end

-- src -> citizenid of the last attach, so a disconnect can clean the unit
-- out of every call. Without this, players who crash or log out while
-- attached stay listed on calls as ghost units for the rest of the session.
local attachedBy = {}

-- Windowed per-player rate limit for the (fully client-driven) notify event.
local notifyBuckets = {}
local function notifyAllowed(src)
    local rl = Config.NotifyRateLimit
    if not rl or not src or src <= 0 then return true end
    local now = os.clock()
    local bucket = notifyBuckets[src]
    if not bucket then bucket = {} notifyBuckets[src] = bucket end
    local cutoff = now - (rl.Window or 10)
    local kept = {}
    for i = 1, #bucket do
        if bucket[i] > cutoff then kept[#kept + 1] = bucket[i] end
    end
    notifyBuckets[src] = kept
    if #kept >= (rl.Max or 12) then return false end
    kept[#kept + 1] = now
    return true
end

-- Minimal shape validation — everything in `data` arrives from a client.
local function sanitizeNotify(data)
    if type(data) ~= 'table' then return nil end
    if type(data.message) ~= 'string' or data.message == '' then return nil end
    if type(data.coords) ~= 'table' and type(data.coords) ~= 'vector3' then return nil end
    if not tonumber(data.coords.x) or not tonumber(data.coords.y) then return nil end
    if type(data.jobs) ~= 'table' or #data.jobs == 0 then return nil end
    data.message = data.message:sub(1, 128)
    if type(data.information) == 'string' then data.information = data.information:sub(1, 256) end
    return data
end

---@param call table
-- Tiny live update whenever a unit attaches/detaches, so alert popups can
-- show "N responding" in real time. Same job/duty filter as full alerts.
local function broadcastUnitCount(call)
    local payload = { id = call.id, count = #(call.units or {}) }
    if Config.FilteredBroadcast == false or not QBCore then
        TriggerClientEvent('ps-dispatch:client:unitCount', -1, payload)
        return
    end
    for src, player in pairs(QBCore.Functions.GetQBPlayers()) do
        local job = player.PlayerData and player.PlayerData.job
        if job and type(call.jobs) == 'table'
            and (lib.table.contains(call.jobs, job.type) or lib.table.contains(call.jobs, job.name)) then
            if Config.FilterOnDuty == false or job.onduty then
                TriggerClientEvent('ps-dispatch:client:unitCount', src, payload)
            end
        end
    end
end

-- ── Hotspot tracking ─────────────────────────────────────────────────────────
-- Rolling timestamps of SEPARATE calls per street (merges don't count; those
-- are one incident). Pruned on every touch, so the table only ever holds
-- entries inside the window.
local streetHits = {}
local function registerHotspot(street)
    local hs = Config.Hotspot
    if not hs or hs.Enabled == false then return nil end
    if type(street) ~= 'string' or street == '' then return nil end
    local now = os.time()
    local cutoff = now - (hs.Window or 30) * 60
    local hits = streetHits[street]
    if not hits then hits = {} streetHits[street] = hits end
    local kept = {}
    for i = 1, #hits do
        if hits[i] > cutoff then kept[#kept + 1] = hits[i] end
    end
    kept[#kept + 1] = now
    streetHits[street] = kept
    if #kept >= (hs.Threshold or 3) then return #kept end
    return nil
end

-- ── Session statistics ───────────────────────────────────────────────────────
-- Aggregated since resource start; surfaced in the dispatch menu.
local stats = {
    calls = 0,          -- unique calls (merges are one call)
    mergedReports = 0,  -- extra reports folded into existing calls
    answered = 0,       -- calls that received at least one unit
    responseSum = 0,    -- ms from call creation to FIRST attach
    byCode = {},        -- codeName -> count
}

lib.callback.register('ps-dispatch:callback:getStats', function()
    local topCode, topCount = nil, 0
    for code, n in pairs(stats.byCode) do
        if n > topCount then topCode, topCount = code, n end
    end
    return {
        calls = stats.calls,
        mergedReports = stats.mergedReports,
        answered = stats.answered,
        avgResponseMs = stats.answered > 0 and math.floor(stats.responseSum / stats.answered) or 0,
        topCode = topCode,
        topCount = topCount,
    }
end)

-- Functions
exports('GetDispatchCalls', function()
    return calls
end)

-- Events
RegisterServerEvent('ps-dispatch:server:notify', function(data)
    local src = source
    if not notifyAllowed(src) then return end
    data = sanitizeNotify(data)
    if not data then return end

    -- Spam collapse: identical nearby alert within the merge window bumps the
    -- existing call (marked `merged`) instead of creating a new one.
    local mergedCall = tryMergeCall(data)
    if mergedCall then
        mergedCall.merged = true
        stats.mergedReports = stats.mergedReports + 1
        broadcastCall(mergedCall)
        return
    end

    data.hotspot = registerHotspot(data.street)
    stats.calls = stats.calls + 1
    if data.codeName then
        stats.byCode[data.codeName] = (stats.byCode[data.codeName] or 0) + 1
    end

    callCount = callCount + 1
    data.id = callCount
    data.time = os.time() * 1000
    data.units = {}
    data.responses = {}
    data.count = 1
    data.merged = nil

    if #calls >= Config.MaxCallList then
        table.remove(calls, 1)
    end

    calls[#calls + 1] = data

    broadcastCall(data)
end)

RegisterServerEvent('ps-dispatch:server:attach', function(id, player)
    if type(player) == 'table' and player.citizenid then
        attachedBy[source] = player.citizenid
    end
    for i=1, #calls do
        if calls[i]['id'] == id then
            for j = 1, #calls[i]['units'] do
                if calls[i]['units'][j]['citizenid'] == player.citizenid then
                    return
                end
            end
            local firstUnit = #calls[i]['units'] == 0
            calls[i]['units'][#calls[i]['units'] + 1] = player
            if firstUnit and not calls[i].answeredTracked then
                calls[i].answeredTracked = true
                stats.answered = stats.answered + 1
                stats.responseSum = stats.responseSum + math.max(0, os.time() * 1000 - calls[i].time)
            end
            broadcastUnitCount(calls[i])
            return
        end
    end
end)

RegisterServerEvent('ps-dispatch:server:detach', function(id, player)
    for i = #calls, 1, -1 do
        if calls[i]['id'] == id then
            if calls[i]['units'] and (#calls[i]['units'] or 0) > 0 then
                for j = #calls[i]['units'], 1, -1 do
                    if calls[i]['units'][j]['citizenid'] == player.citizenid then
                        table.remove(calls[i]['units'], j)
                    end
                end
                broadcastUnitCount(calls[i])
            end
            return
        end
    end
end)

-- Callbacks
lib.callback.register('ps-dispatch:callback:getLatestDispatch', function(source)
    return calls[#calls]
end)

lib.callback.register('ps-dispatch:callback:getCalls', function(source)
    return calls
end)

-- Commands
lib.addCommand('dispatch', {
    help = locale('open_dispatch')
}, function(source, raw)
    TriggerClientEvent("ps-dispatch:client:openMenu", source, calls)
end)

lib.addCommand('911', {
    help = 'Send a message to 911',
    params = { { name = 'message', type = 'string', help = '911 Message' }},
}, function(source, args, raw)
    local fullMessage = raw:sub(5)
    TriggerClientEvent('ps-dispatch:client:sendEmergencyMsg', source, fullMessage, "911", false)
end)
lib.addCommand('911a', {
    help = 'Send an anonymous message to 911',
    params = { { name = 'message', type = 'string', help = '911 Message' }},
}, function(source, args, raw)
    local fullMessage = raw:sub(5)
    TriggerClientEvent('ps-dispatch:client:sendEmergencyMsg', source, fullMessage, "911", true)
end)

lib.addCommand('311', {
    help = 'Send a message to 311',
    params = { { name = 'message', type = 'string', help = '311 Message' }},
}, function(source, args, raw)
    local fullMessage = raw:sub(5)
    TriggerClientEvent('ps-dispatch:client:sendEmergencyMsg', source, fullMessage, "311", false)
end)

lib.addCommand('311a', {
    help = 'Send an anonymous message to 311',
    params = { { name = 'message', type = 'string', help = '311 Message' }},
}, function(source, args, raw)
    local fullMessage = raw:sub(5)
    TriggerClientEvent('ps-dispatch:client:sendEmergencyMsg', source, fullMessage, "311", true)
end)

-- ── Housekeeping ─────────────────────────────────────────────────────────────

-- Ghost-unit cleanup: a player who disconnects while attached is removed
-- from every call's unit list, so the menu never shows people who are gone.
AddEventHandler('playerDropped', function()
    local src = source
    notifyBuckets[src] = nil
    local citizenid = attachedBy[src]
    attachedBy[src] = nil
    if not citizenid then return end
    for i = 1, #calls do
        local units = calls[i].units
        if units then
            local before = #units
            for j = #units, 1, -1 do
                if units[j].citizenid == citizenid then
                    table.remove(units, j)
                end
            end
            if #units ~= before then broadcastUnitCount(calls[i]) end
        end
    end
end)

-- Call expiry: without a sweep, MaxCallList old calls sit in the menu for
-- the whole session. The list is time-ordered, so expired entries are always
-- a prefix and removal stops at the first fresh call.
if (Config.CallLifetime or 0) > 0 then
    CreateThread(function()
        local lifetimeMs = Config.CallLifetime * 60 * 1000
        while true do
            Wait(60000)
            local cutoff = os.time() * 1000 - lifetimeMs
            while calls[1] and calls[1].time < cutoff do
                table.remove(calls, 1)
            end
        end
    end)
end
