-- ═══════════════════════════════════════════════════════════════════════════
--  Major incidents
-- ═══════════════════════════════════════════════════════════════════════════
-- A supervisor marks a call as a major incident. It pins to the top of every
-- board, and units attached to it stop receiving routine chatter.
--
-- Several can run at once — two banks going up together is a real situation.
-- The state lives here and is broadcast whole on every change: the list is a
-- handful of entries, so diffing it would be more code than it saves.

local QBCore = nil
pcall(function() QBCore = exports['qb-core']:GetCoreObject() end)

local function cfg()
    return (Config and Config.MajorIncident) or {}
end

--- [callId] = { id, title, code, declaredBy, declaredByName, expiresAt }
local activeIncidents = {}

local function countActive()
    local n = 0
    for _ in pairs(activeIncidents) do n = n + 1 end
    return n
end

--- Flat list for the wire, newest first.
local function incidentList()
    local list = {}
    for _, inc in pairs(activeIncidents) do list[#list + 1] = inc end
    table.sort(list, function(a, b) return a.declaredAt > b.declaredAt end)
    return list
end

local function broadcastIncidents()
    TriggerClientEvent('ps-dispatch:client:incidents', -1, incidentList())
end

--- May this player declare or stand down an incident?
--- Grade is read server-side and re-checked on every action: the client hides
--- the button when it shouldn't be there, but that is cosmetics, not a guard.
---@param src number
---@return boolean
function MayDeclareIncident(src)
    if cfg().Enabled == false then return false end
    if not QBCore then return false end

    local player = QBCore.Functions.GetPlayer(src)
    if not player then return false end

    local job = player.PlayerData and player.PlayerData.job
    if not job then return false end

    local required = (cfg().Grades or {})[job.name]
    if required == nil then return false end

    local level = (job.grade and (job.grade.level or job.grade)) or 0
    return tonumber(level) ~= nil and tonumber(level) >= tonumber(required)
end

--- How the declaring unit is named on every other board.
---@param player table|nil the QBCore player object
---@return string
local function describeDeclarer(player)
    local data = player and player.PlayerData
    if not data then return locale('incident_supervisor') end

    local parts = {}

    local callsign = data.metadata and data.metadata.callsign
    if type(callsign) == 'string' and callsign ~= '' then
        parts[#parts + 1] = callsign
    end

    local grade = data.job and data.job.grade
    local rank = grade and (grade.name or grade.label)
    if type(rank) == 'string' and rank ~= '' then
        parts[#parts + 1] = rank
    end

    local ci = data.charinfo
    if ci and type(ci.lastname) == 'string' and ci.lastname ~= '' then
        local initial = ''
        if type(ci.firstname) == 'string' and ci.firstname ~= '' then
            initial = ci.firstname:sub(1, 1):upper() .. '. '
        end
        parts[#parts + 1] = initial .. ci.lastname
    end

    if #parts == 0 then return locale('incident_supervisor') end
    return table.concat(parts, ' · ')
end

--- Drop an incident, e.g. because its call was cleared. Global so main.lua can
--- call it without this file exposing its state.
---@param callId any
function DropIncident(callId)
    if callId == nil or not activeIncidents[callId] then return end
    activeIncidents[callId] = nil
    broadcastIncidents()
end

lib.callback.register('ps-dispatch:callback:mayDeclareIncident', function(source)
    return MayDeclareIncident(source)
end)

RegisterServerEvent('ps-dispatch:server:declareIncident', function(payload)
    local src = source
    if not MayDeclareIncident(src) then return end
    if type(payload) ~= 'table' or payload.id == nil then return end

    local id = payload.id
    local existing = activeIncidents[id]
    local duration = (tonumber(cfg().Duration) or 1800) * 1000
    local expiresAt = GetGameTimer() + duration

    if existing then
        -- Re-declaring extends rather than resets: a supervisor topping up a
        -- long incident shouldn't be able to shorten it by accident.
        if expiresAt > existing.expiresAt then existing.expiresAt = expiresAt end
        broadcastIncidents()
        return
    end

    local max = tonumber(cfg().MaxActive) or 3
    if countActive() >= max then
        TriggerClientEvent('ps-dispatch:client:incidentRejected', src, 'too_many', max)
        return
    end

    local player = QBCore and QBCore.Functions.GetPlayer(src)

    activeIncidents[id] = {
        id = id,
        title = type(payload.title) == 'string' and payload.title:sub(1, 64) or locale('incident_default_title'),
        code = type(payload.code) == 'string' and payload.code:sub(1, 12) or nil,
        street = type(payload.street) == 'string' and payload.street:sub(1, 64) or nil,
        declaredBy = player and player.PlayerData.citizenid or nil,
        -- "60 · Sergeant · J. Walker" — the way a unit is actually identified
        -- on the radio: callsign first, then who is behind it. Each part is
        -- dropped if the server doesn't provide it, so a missing rank leaves a
        -- shorter line rather than a stray separator.
        declaredByName = describeDeclarer(player),
        declaredAt = GetGameTimer(),
        expiresAt = expiresAt,
    }

    broadcastIncidents()
end)

RegisterServerEvent('ps-dispatch:server:standDownIncident', function(id)
    local src = source
    -- Anyone of the right grade may stand one down, not just whoever declared
    -- it — otherwise the state sticks when that player logs off or dies.
    if not MayDeclareIncident(src) then return end
    DropIncident(id)
end)

-- A freshly connected client has no state; hand it over on request.
lib.callback.register('ps-dispatch:callback:getIncidents', function()
    return incidentList()
end)

-- Automatic expiry. One timer for the whole table rather than one per
-- incident, so nothing leaks when an incident is stood down early.
CreateThread(function()
    while true do
        Wait(5000)
        if next(activeIncidents) then
            local now = GetGameTimer()
            local changed = false
            for id, inc in pairs(activeIncidents) do
                if now >= inc.expiresAt then
                    activeIncidents[id] = nil
                    changed = true
                end
            end
            if changed then broadcastIncidents() end
        end
    end
end)
