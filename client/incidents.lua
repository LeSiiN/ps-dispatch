-- ═══════════════════════════════════════════════════════════════════════════
--  Major incidents (client)
-- ═══════════════════════════════════════════════════════════════════════════
-- Holds the incident list the server broadcasts, hands it to the NUI, and
-- decides whether an incoming routine alert should be quieted for this unit.

local function cfg()
    return (Config and Config.MajorIncident) or {}
end

--- Mirrors the server's list. Never written locally except from the broadcast.
local activeIncidents = {}

--- Call ids this player is attached to, refreshed from the menu payload. Used
--- to decide whether the suppression applies — being attached is what opts a
--- unit into the quiet, so it has to be known client-side.
local attachedCallIds = {}

local function pushIncidentsToNui()
    SendNUIMessage({ action = 'incidents', data = activeIncidents })
end

RegisterNetEvent('ps-dispatch:client:incidents', function(list)
    activeIncidents = type(list) == 'table' and list or {}
    pushIncidentsToNui()
end)

-- The server sends a reason code, not a sentence, so the text lands in the
-- language of whoever is reading it rather than whatever the server runs.
RegisterNetEvent('ps-dispatch:client:incidentRejected', function(reason, arg)
    local message
    if reason == 'too_many' then
        message = locale('incident_too_many', tostring(arg))
    else
        message = tostring(reason)
    end
    SendNUIMessage({ action = 'incidentRejected', data = message })
end)

--- Is this player working any declared incident?
---@return boolean
local function onIncident()
    if #activeIncidents == 0 then return false end
    for i = 1, #activeIncidents do
        if attachedCallIds[activeIncidents[i].id] then return true end
    end
    return false
end

--- Should this alert be quieted because the player is working an incident?
--- Called from the notify handler in client/main.lua.
---
--- The carve-outs mirror the existing "priority only" preference exactly:
--- priority 1 always lands, and anything addressed to this unit always lands.
--- Consistency matters more here than cleverness — an officer who already
--- understands one filter understands this one.
---@param data table the alert payload
---@return boolean quiet
function IncidentQuiets(data)
    if cfg().Enabled == false or cfg().QuietRoutine == false then return false end
    if type(data) ~= 'table' then return false end
    -- `<= 1` so the new critical tier counts as urgent too; a plain `== 1`
    -- would have quieted the most important alert there is.
    if (tonumber(data.priority) or 3) <= 1 or data.assigned then return false end
    -- An alert about an incident the player is working is never chatter.
    if data.id and attachedCallIds[data.id] then return false end
    return onIncident()
end

--- Track which calls this player is attached to. Fed from the menu payload,
--- which already carries the unit list for every call.
---@param calls table
function SyncAttachedCalls(calls)
    attachedCallIds = {}
    if type(calls) ~= 'table' then return end

    local myCitizenId = PlayerData and PlayerData.citizenid
    if not myCitizenId then return end

    for i = 1, #calls do
        local call = calls[i]
        local units = call and call.units
        if type(units) == 'table' then
            for j = 1, #units do
                if units[j] and units[j].citizenid == myCitizenId then
                    attachedCallIds[call.id] = true
                    break
                end
            end
        end
    end
end

-- Attaching and detaching happen without reopening the menu, so the list has
-- to follow those events too. Both already exist for exactly this kind of
-- local bookkeeping.
RegisterNetEvent('ps-dispatch:client:selfAttach', function(id)
    if id ~= nil then attachedCallIds[id] = true end
end)

RegisterNetEvent('ps-dispatch:client:selfDetach', function(id)
    if id ~= nil then attachedCallIds[id] = nil end
end)

-- ── NUI bridge ──────────────────────────────────────────────────────────────

RegisterNUICallback('declareIncident', function(data, cb)
    if type(data) == 'table' and data.id ~= nil then
        TriggerServerEvent('ps-dispatch:server:declareIncident', data)
    end
    cb('ok')
end)

RegisterNUICallback('standDownIncident', function(data, cb)
    if type(data) == 'table' and data.id ~= nil then
        TriggerServerEvent('ps-dispatch:server:standDownIncident', data.id)
    end
    cb('ok')
end)

-- Pull the current list on join: a client connecting mid-incident would
-- otherwise see nothing until the next change.
CreateThread(function()
    Wait(4000)
    if cfg().Enabled == false then return end
    local list = lib.callback.await('ps-dispatch:callback:getIncidents', false)
    if type(list) == 'table' then
        activeIncidents = list
        pushIncidentsToNui()
    end

    -- Whether this player may declare is a grade question, and grades live on
    -- the server. The UI only uses the answer to show or hide the button; the
    -- server re-checks on every declare regardless.
    local may = lib.callback.await('ps-dispatch:callback:mayDeclareIncident', false)
    SendNUIMessage({ action = 'mayDeclareIncident', data = may == true })
end)

-- Job changes mid-session (promotion, going off duty) change the answer.
RegisterNetEvent('QBCore:Client:OnJobUpdate', function()
    if cfg().Enabled == false then return end
    CreateThread(function()
        Wait(500)
        local may = lib.callback.await('ps-dispatch:callback:mayDeclareIncident', false)
        SendNUIMessage({ action = 'mayDeclareIncident', data = may == true })
    end)
end)