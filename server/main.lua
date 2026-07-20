local calls = {}
local callCount = 0

-- QBCore is only needed for the job-filtered broadcast; keep the resource
-- functional without it (falls back to the old broadcast-to-everyone).
local QBCore = nil
pcall(function() QBCore = exports['qb-core']:GetCoreObject() end)

---@param data table
-- Resolve blip metadata ONCE server-side from the shared config: the display
-- position (randomly offset when the alert type wants imprecision) and the
-- search radius. Every officer's blip, the map thumbnail and the menu then
-- agree on the same spot — and the exact location never leaves the server's
-- visuals for offset alerts.
local function resolveBlipMeta(data)
    local blip = Config.Blips and Config.Blips[data.codeName] or nil
    local radius = blip and tonumber(blip.radius) or 0
    if radius and radius > 0 then data.mapRadius = radius end
    if blip and blip.offset then
        local off = math.floor(tonumber(Config.MaxOffset) or 100)
        data.displayCoords = {
            x = data.coords.x + math.random(-off, off),
            y = data.coords.y + math.random(-off, off),
        }
    end
end

-- Fields a merged report may overwrite on the existing call. Deliberately a
-- whitelist: id, units, count and the escalation/hotspot bookkeeping have to
-- survive a merge untouched.
local MERGE_REFRESH_FIELDS = {
    'weapon', 'automaticGunFire', 'automaticGunfire', 'information',
    'vehicle', 'plate', 'color', 'class', 'doors', 'heading',
    'street', 'gender', 'name', 'number', 'model',
}

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
                resolveBlipMeta(call)      -- keep display offset/radius in step
                -- Descriptive details follow the LATEST report too. Keeping
                -- only the first one meant a shooter who swapped from a
                -- pistol to a rifle was still broadcast as "pistol" for the
                -- rest of the merge window — a merge is one incident, but the
                -- freshest description of it is the useful one.
                for _, key in ipairs(MERGE_REFRESH_FIELDS) do
                    if data[key] ~= nil then call[key] = data[key] end
                end
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
    cleared = 0,        -- calls closed by an officer (rather than expiring)
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
        cleared = stats.cleared,
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

    resolveBlipMeta(data)
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
    local src = source
    if type(player) == 'table' and player.citizenid then
        attachedBy[src] = player.citizenid
        -- One call per unit: attaching somewhere implicitly detaches
        -- everywhere else. The origin client gets told which calls it left
        -- so those popups drop their "Responding" state.
        for i = 1, #calls do
            local call = calls[i]
            if call.id ~= id and call.units then
                local removed = false
                for j = #call.units, 1, -1 do
                    if call.units[j].citizenid == player.citizenid then
                        table.remove(call.units, j)
                        removed = true
                    end
                end
                if removed then
                    broadcastUnitCount(call)
                    TriggerClientEvent('ps-dispatch:client:detachedFrom', src, call.id)
                end
            end
        end
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

-- ── Targeted alerts ──────────────────────────────────────────────────────────
-- Send an alert to SPECIFIC players instead of a whole job — e.g. the MDT
-- pushing a custom assignment to one patrol. Usage from any server script:
--
--   exports['ps-dispatch']:SendTargetedAlert({ srcA, srcB }, {
--       message = 'Check on subject', code = '10-25', icon = 'fas fa-envelope',
--       coords = vector3(x, y, z), street = 'Alta Street',
--       information = 'Sent by dispatch', priority = 2,
--       addToList = false, -- true: also appears in everyone's call menu
--   })
--
-- Targeted alerts skip merge/hotspot/stat handling by design: they are
-- direct messages, not incident reports.
local function sendTargetedAlert(targets, data)
    if type(targets) == 'number' then targets = { targets } end
    if type(targets) ~= 'table' or #targets == 0 then return false end
    if type(data) ~= 'table' or type(data.message) ~= 'string' then return false end

    callCount = callCount + 1
    data.id = callCount
    data.time = os.time() * 1000
    data.units = data.units or {}
    data.responses = {}
    data.count = 1
    data.priority = data.priority or 2
    data.code = data.code or 'DIRECT'
    data.codeName = data.codeName or 'targeted'
    data.icon = data.icon or 'fas fa-envelope'
    -- Receiving clients gate on jobs + duty; default lets any officer pass.
    data.jobs = (type(data.jobs) == 'table' and #data.jobs > 0) and data.jobs or { 'leo', 'ems' }
    -- Custom codeNames won't be in Config.Blips, and the client's blip path
    -- dereferences the blip table unconditionally — without this fallback a
    -- targeted alert with an unknown code would error client-side.
    if not (Config.Blips and Config.Blips[data.codeName]) and type(data.alert) ~= 'table' then
        data.alert = {
            sprite = 488, color = 3, scale = 1.0, length = 2, radius = 0,
            sound = 'Lose_1st', sound2 = 'GTAO_FM_Events_Soundset',
            offset = false, flash = false,
        }
    end
    if data.coords and data.coords.x then resolveBlipMeta(data) end

    if data.addToList then
        if #calls >= Config.MaxCallList then table.remove(calls, 1) end
        calls[#calls + 1] = data
    end
    data.addToList = nil

    for i = 1, #targets do
        local target = tonumber(targets[i])
        if target and target > 0 then
            TriggerClientEvent('ps-dispatch:client:notify', target, data)
        end
    end
    return true
end

exports('SendTargetedAlert', sendTargetedAlert)

-- Same thing as a server event for resources that prefer events over
-- exports. Guarded so only server-side triggers are honored — a client must
-- never be able to push targeted alerts to other players.
RegisterNetEvent('ps-dispatch:server:targetAlert', function(targets, data)
    if source and tonumber(source) and tonumber(source) > 0 then return end
    sendTargetedAlert(targets, data)
end)

-- ── Call lifecycle: clearing and dispatcher notes ────────────────────────────

---@param src number
---@param call table
---@return boolean # true when this player's job is targeted by the call
-- Both actions below mutate a call everyone can see, so they are limited to
-- players the call was actually broadcast to. Without QBCore we cannot tell
-- jobs apart and fall back to allowing it, matching FilteredBroadcast.
local function mayModifyCall(src, call)
    if not QBCore then return true end
    local player = QBCore.Functions.GetPlayer(src)
    local job = player and player.PlayerData and player.PlayerData.job
    if not job or type(call.jobs) ~= 'table' then return false end
    return lib.table.contains(call.jobs, job.type) or lib.table.contains(call.jobs, job.name)
end

---@param id number
---@return table|nil call, number|nil index
local function findCall(id)
    id = tonumber(id)
    if not id then return nil, nil end
    for i = 1, #calls do
        if calls[i].id == id then return calls[i], i end
    end
    return nil, nil
end

-- Close a call for everyone. Until now the only way out of the list was the
-- 30-minute expiry sweep, so handled calls lingered and the Active Calls
-- board filled up with work that was long finished.
RegisterServerEvent('ps-dispatch:server:clearCall', function(id)
    local src = source
    local call, index = findCall(id)
    if not call or not index then return end
    if not mayModifyCall(src, call) then return end

    table.remove(calls, index)
    stats.cleared = stats.cleared + 1

    -- Announce to the call's audience so every open menu drops it, then to
    -- the clearing player specifically: they may have already moved out of
    -- the job filter's reach (off duty) but still deserve the confirmation.
    if Config.FilteredBroadcast == false or not QBCore then
        TriggerClientEvent('ps-dispatch:client:callCleared', -1, call.id)
    else
        for target, player in pairs(QBCore.Functions.GetQBPlayers()) do
            local job = player.PlayerData and player.PlayerData.job
            if job and (lib.table.contains(call.jobs, job.type) or lib.table.contains(call.jobs, job.name)) then
                TriggerClientEvent('ps-dispatch:client:callCleared', target, call.id)
            end
        end
        TriggerClientEvent('ps-dispatch:client:callCleared', src, call.id)
    end
end)

-- Dispatcher note: free text pinned to a call and shared with every unit on
-- it — "suspect fled north on foot", "use the rear entrance".
RegisterServerEvent('ps-dispatch:server:setCallNote', function(id, note)
    local src = source
    local call = findCall(id)
    if not call then return end
    if not mayModifyCall(src, call) then return end

    if type(note) ~= 'string' then note = '' end
    note = note:gsub('%s+$', ''):sub(1, 240)
    call.dispatchNote = note ~= '' and note or nil

    local payload = { id = call.id, note = call.dispatchNote }
    if Config.FilteredBroadcast == false or not QBCore then
        TriggerClientEvent('ps-dispatch:client:callNote', -1, payload)
    else
        for target, player in pairs(QBCore.Functions.GetQBPlayers()) do
            local job = player.PlayerData and player.PlayerData.job
            if job and (lib.table.contains(call.jobs, job.type) or lib.table.contains(call.jobs, job.name)) then
                TriggerClientEvent('ps-dispatch:client:callNote', target, payload)
            end
        end
    end
end)
