QBCore = exports['qb-core']:GetCoreObject()
PlayerData = {}
inHuntingZone, inNoDispatchZone = false, false
local huntingZones, nodispatchZones, huntingBlips = {} , {}, {}

local blips = {}
local radius2 = {}
local alertsMuted = false
local alertsDisabled = false

-- Per-player settings mirrored from the dispatch settings modal. Declared up
-- here with the other module state on purpose: the helpers below read them,
-- and a Lua local is only visible from its declaration line onward.
local prefBlips = true
local prefPriorityOnly = false
local prefMutedCodes = {}

--- Usable map position for an alert, or nil when it has none.
-- Targeted alerts are allowed to carry no coords at all (a plate check or a
-- record lookup answers a question, it does not point at a place), so every
-- map-related step has to tolerate their absence rather than assume a point.
---@param data table
---@return table|nil
local function alertPosition(data)
    local at = data.displayCoords or data.coords
    if type(at) ~= 'table' and type(at) ~= 'vector3' then return nil end
    local x, y = tonumber(at.x), tonumber(at.y)
    if not x or not y then return nil end
    return { x = x, y = y, z = tonumber(at.z) or tonumber(data.coords and data.coords.z) or 0.0 }
end

local waypointCooldown = false

-- Functions
---@param bool boolean Toggles visibilty of the menu
local function toggleUI(bool)
    SetNuiFocus(bool, bool)
    SendNUIMessage({ action = "setVisible", data = bool })
end

-- Zone Functions --
local function removeZones()
    -- Hunting Zone --
    for i = 1, #huntingZones do
        huntingZones[i]:remove()
    end
    -- No Dispatch Zone --
    for i = 1, #nodispatchZones do
        nodispatchZones[i]:remove()
    end
    -- Hunting Blips --
    for i = 1, #huntingBlips do
        RemoveBlip(huntingBlips[i])
    end
    -- Reset the stored values too
    huntingZones, nodispatchZones, huntingBlips = {} , {}, {}
end

local function createZones()
    -- Hunting Zone --
    if Config.Locations['HuntingZones'][1] then
    	for _, hunting in pairs(Config.Locations["HuntingZones"]) do
            -- Creates the Blips
            if Config.EnableHuntingBlip then
                local blip = AddBlipForCoord(hunting.coords.x, hunting.coords.y, hunting.coords.z)
                local huntingradius = AddBlipForRadius(hunting.coords.x, hunting.coords.y, hunting.coords.z, hunting.radius)
                SetBlipSprite(blip, 442)
                SetBlipAsShortRange(blip, true)
                SetBlipScale(blip, 0.8)
                SetBlipColour(blip, 0)
                SetBlipColour(huntingradius, 0)
                SetBlipAlpha(huntingradius, 40)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(hunting.label)
                EndTextCommandSetBlipName(blip)
                huntingBlips[#huntingBlips+1] = blip
                huntingBlips[#huntingBlips+1] = huntingradius
            end
            -- Creates the Sphere --
            local huntingZone = lib.zones.sphere({
                coords = hunting.coords,
                radius = hunting.radius,
                debug = Config.Debug,
                onEnter = function()
                    inHuntingZone = true
                end,
                onExit = function()
                    inHuntingZone = false
                end
            })
            huntingZones[#huntingZones+1] = huntingZone
    	end
    end
    -- No Dispatch Zone --
    if Config.Locations['NoDispatchZones'][1] then
    	for _, nodispatch in pairs(Config.Locations["NoDispatchZones"]) do
            local nodispatchZone = lib.zones.box({
                coords = nodispatch.coords,
                size = vec3(nodispatch.length, nodispatch.width, nodispatch.maxZ - nodispatch.minZ),
                rotation = nodispatch.heading,
                debug = Config.Debug,
                onEnter = function()
                    inNoDispatchZone = true
                end,
                onExit = function()
                    inNoDispatchZone = false
                end
            })
            nodispatchZones[#nodispatchZones+1] = nodispatchZone
    	end
    end
end

local function setupDispatch()
    local playerInfo = QBCore.Functions.GetPlayerData()
    local locales = lib.getLocales()
    PlayerData = {
        charinfo = {
            firstname = playerInfo.charinfo.firstname,
            lastname = playerInfo.charinfo.lastname
        },
        metadata = {
            callsign = playerInfo.metadata.callsign
        },
        citizenid = playerInfo.citizenid,
        job = {
            type = playerInfo.job.type,
            name = playerInfo.job.name,
            label = playerInfo.job.label
        },
    }

    Wait(1000)

    SendNUIMessage({
        action = "setupUI",
        data = {
            locales = locales,
            player = PlayerData,
            keybind = Config.RespondKeybind,
            maxCallList = Config.MaxCallList,
            maxVisibleAlerts = Config.MaxVisibleAlerts or 4,
            alertPosition = Config.AlertPosition or 'top-right',
            -- Map thumbnails read the MDT's map image over NUI. Standalone
            -- installs (no MDT, or a differently named one) must not end up
            -- with a broken image request per alert, so the resource is
            -- resolved from the configured URL and checked here — the NUI
            -- never even learns about an image it cannot load. The NUI-side
            -- probe stays as a second net for started-but-file-missing.
            mapImage = (function()
                local url = Config.MdtMapImage
                if type(url) ~= 'string' or url == '' then return false end
                local res = url:match('^nui://([^/]+)/')
                if res and GetResourceState(res) ~= 'started' then return false end
                return url
            end)(),
            -- Whether the plate scanner log exists at all. When off, the NUI
            -- drops the tab bar entirely rather than showing a lone tab.
            platesEnabled = not (Config.PlateScanner and Config.PlateScanner.Enabled == false),
            unattendedAfter = Config.UnattendedAfter or 0,
            pinnedCodes = Config.PinnedCodes or {},
            -- Every alert type this server can produce, so the settings modal
            -- can offer per-type mutes without hardcoding a list.
            alertTypes = (function()
                local list = {}
                for codeName in pairs(Config.Blips or {}) do list[#list + 1] = codeName end
                table.sort(list)
                return list
            end)(),
        }
    })
end

---@param data string | table -- The player job or an array of jobs to check against
---@return boolean -- Returns true if the job is valid
local function isJobValid(data)
    if PlayerData.job == nil then return false end
    local jobType = PlayerData.job.type
    local jobName = PlayerData.job.name

    if type(data) == "string" then
        return lib.table.contains(Config.Jobs, data) or lib.table.contains(Config.Jobs, jobName)
    elseif type(data) == "table" then
        return lib.table.contains(data, jobType) or lib.table.contains(data, jobName)
    end

    return false
end

-- The call the on-screen alert belongs to, and when that alert disappears.
-- Opening the menu while an alert is up jumps straight to that call instead
-- of dropping the officer into an unsorted list.
local activeAlertId = nil
local activeAlertUntil = 0

local function currentAlertCallId()
    if activeAlertId and GetGameTimer() < activeAlertUntil then
        return activeAlertId
    end
    return nil
end

local function openMenu()
    if not isJobValid(PlayerData.job.type) then return end

    local calls = lib.callback.await('ps-dispatch:callback:getCalls', false)
    -- The menu now holds the plate log too, so "no calls" is no longer the same
    -- as "nothing to show" — an officer with checks logged and a quiet board
    -- still needs to get in.
    local plateCount = GetPlateHitCount and GetPlateHitCount() or 0

    if #calls == 0 and plateCount == 0 then
        lib.notify({ description = locale('no_calls'), position = 'top', type = 'error' })
        return
    end

    -- Plate log first: the NUI decides which tab to open on, and it can only
    -- do that once it knows whether there are entries.
    if PushPlateHits then PushPlateHits() end
    SendNUIMessage({ action = 'setDispatchs', data = calls, })
    -- Alert still on screen? Open straight onto that call, expanded.
    SendNUIMessage({ action = 'focusCall', data = currentAlertCallId() })
    -- Those popups have served their purpose now that the same calls are
    -- on screen in the menu — clear the stack instead of letting it hover
    -- over the panel. Alerts arriving WHILE the menu is open still show:
    -- the menu list is a snapshot, so they'd be missed otherwise.
    SendNUIMessage({ action = 'clearAlerts' })
    activeAlertId = nil
    toggleUI(true)
end

local function setWaypoint()
    if not isJobValid(PlayerData.job.type) then return end
    if not IsOnDuty() then return end

    local data = lib.callback.await('ps-dispatch:callback:getLatestDispatch', false)

    if not data then return end

    if data.alertTime == nil then data.alertTime = Config.AlertTime end

    -- Freshness: only respond while the alert is still on screen. The old
    -- check compared `data.time` (unix ms from the server) against
    -- `GetGameTimer() * 1000` (client uptime in ms, times a thousand) — two
    -- unrelated clocks, so the guard never did what it was meant to.
    if (GetCloudTimeAsInt() - math.floor(data.time / 1000)) > data.alertTime then return end

    local timer = data.alertTime * 1000

    local at = alertPosition(data)
    if not at then return end -- an alert without a position cannot be routed to

    if not waypointCooldown and lib.table.contains(data.jobs, PlayerData.job.type) then
        SetNewWaypoint(at.x, at.y)
        TriggerServerEvent('ps-dispatch:server:attach', data.id, PlayerData)
        -- Local bridge event so companion resources (e.g. ps-mdt's automatic
        -- officer status) can react to a self-attach made through dispatch
        -- itself. No-op if nothing listens.
        TriggerEvent('ps-dispatch:client:selfAttach', data.id)
        -- Flip the popup's respond button into its "Responding" state.
        SendNUIMessage({ action = 'callResponded', data = data.id })
        lib.notify({ description = locale('waypoint_set'), position = 'top', type = 'success' })
        waypointCooldown = true
        SetTimeout(timer, function()
            waypointCooldown = false
        end)
    end
end

local function randomOffset(baseX, baseY, offset)
    local randomX = baseX + math.random(-offset, offset)
    local randomY = baseY + math.random(-offset, offset)

    return randomX, randomY
end

local function createBlipData(coords, radius, sprite, color, scale, flash)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    local radiusBlip = AddBlipForRadius(coords.x, coords.y, coords.z, radius)

    SetBlipFlashes(blip, flash)
    SetBlipSprite(blip, sprite or 161)
    SetBlipHighDetail(blip, true)
    SetBlipScale(blip, scale or 1.0)
    SetBlipColour(blip, color or 84)
    SetBlipAlpha(blip, 255)
    SetBlipAsShortRange(blip, false)
    SetBlipCategory(blip, 2)
    SetBlipColour(radiusBlip, color or 84)
    SetBlipAlpha(radiusBlip, 128)

    return blip, radiusBlip
end

local function createBlip(data, blipData)
    local blip, radius = nil, nil
    local sprite = blipData.sprite or blipData.alert.sprite or 161
    local color = blipData.color or blipData.alert.color or 84
    local scale = blipData.scale or blipData.alert.scale or 1.0
    local flash = blipData.flash or false

    -- The server resolves ONE offset per call (data.displayCoords), shared
    -- by every officer's blip AND the NUI map thumbnail. Previously each
    -- client rolled its own random offset, so no two officers saw the same
    -- spot — and the thumbnail pointed at the exact location, defeating the
    -- offset entirely.
    local at = alertPosition(data)
    if not at then return end
    blip, radius = createBlipData(at, blipData.radius, sprite, color, scale, flash)
    blips[data.id] = blip
    radius2[data.id] = radius

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(data.code .. ' - ' .. data.message)
    EndTextCommandSetBlipName(blip)

    -- Fade the radius in 16 coarse steps instead of 128 single-alpha ticks:
    -- visually identical, but the per-blip thread wakes 8× less often. The
    -- table entries are cleared afterwards — previously blips[]/radius2[]
    -- grew forever (one dead handle per alert for the whole session).
    local totalMs = (blipData.length or blipData.alert.length) * 60000
    local steps = 16
    local radiusAlpha = 128
    for _ = 1, steps do
        Wait(totalMs / steps)
        radiusAlpha = math.max(0, radiusAlpha - (128 / steps))
        SetBlipAlpha(radius, math.floor(radiusAlpha))
    end

    RemoveBlip(radius)
    RemoveBlip(blip)
    if blips[data.id] == blip then blips[data.id] = nil end
    if radius2[data.id] == radius then radius2[data.id] = nil end
end

--- Play an alert's sound through the game's own audio.
-- Priority calls get their own, sharper pair so urgent traffic is audible as
-- urgent. An alert may still override both by carrying a complete native pair
-- (`sound` + `sound2`) in Config.Blips.
---@param data table The call (only `priority` is read)
---@param blipData table|nil The alert's Config.Blips entry
local function playAlertSound(data, blipData)
    local cfg = Config.AlertSounds or {}
    local pair

    if data and data.priority == 1 then
        pair = cfg.priority
    end
    if not pair and type(blipData) == 'table' then
        local name = blipData.sound or (blipData.alert and blipData.alert.sound)
        local ref = blipData.sound2 or (blipData.alert and blipData.alert.sound2)
        -- Only a COMPLETE pair is a usable native sound; a lone `sound` is a
        -- leftover interact-sound filename and would play nothing.
        if name and ref then pair = { audioName = name, audioRef = ref } end
    end
    pair = pair or cfg.default or { audioName = 'Lose_1st', audioRef = 'GTAO_FM_Events_Soundset' }

    PlaySound(-1, pair.audioName, pair.audioRef, 0, 0, 1)
end

local function addBlip(data, blipData)
    -- Defensive: an alert whose codeName has no blip config and no inline
    -- alert table gets no blip/sound rather than a nil-index error.
    if type(blipData) ~= 'table' then return end
    -- No position means no marker — nothing to pin to the map.
    if not alertPosition(data) then return end
    -- A merged repeat of an existing call keeps its original blip: the fade
    -- thread for data.id is still running, spawning a second one would leak
    -- the first handle and double up map markers.
    if not (data.merged and blips[data.id]) then
        CreateThread(function()
            createBlip(data, blipData)
        end)
    end
end

-- Keybind
local RespondToDispatch = lib.addKeybind({
    name = 'RespondToDispatch',
    description = 'Set waypoint to last call location',
    defaultKey = Config.RespondKeybind,
    onPressed = setWaypoint,
})

local OpenDispatchMenu = lib.addKeybind({
    name = 'OpenDispatchMenu',
    description = 'Open Dispatch Menu',
    defaultKey = Config.OpenDispatchMenu,
    onPressed = openMenu,
})

-- Events
-- Server detached us from another call (one-call-per-unit rule): drop that
-- popup's "Responding" state.
RegisterNetEvent('ps-dispatch:client:detachedFrom', function(id)
    SendNUIMessage({ action = 'callUnresponded', data = id })
end)

-- ── Per-player settings (dispatch settings modal) ────────────────────────────
-- The modal owns these; Lua mirrors the two that must gate work BEFORE the
-- NUI ever sees an alert (blip creation and priority filtering). Defaults
-- match the modal's own defaults, so an untouched install behaves as before.

RegisterNUICallback('setDispatchPrefs', function(data, cb)
    if type(data) == 'table' then
        if type(data.blips) == 'boolean' then prefBlips = data.blips end
        if type(data.priorityOnly) == 'boolean' then prefPriorityOnly = data.priorityOnly end
        -- Per-player alert-type mutes, stored as a set for O(1) lookups on
        -- the hot notify path.
        if type(data.mutedCodes) == 'table' then
            prefMutedCodes = {}
            for _, code in ipairs(data.mutedCodes) do
                if type(code) == 'string' then prefMutedCodes[code] = true end
            end
        end
    end
    cb('ok')
end)

-- A call was closed by an officer: drop its blip and let the NUI remove it
-- from the menu and the alert stack.
RegisterNetEvent('ps-dispatch:client:callCleared', function(id)
    if blips[id] then RemoveBlip(blips[id]) blips[id] = nil end
    if radius2[id] then RemoveBlip(radius2[id]) radius2[id] = nil end
    SendNUIMessage({ action = 'callCleared', data = id })
end)

-- Dispatcher note added/changed/removed on a call.
RegisterNetEvent('ps-dispatch:client:callNote', function(payload)
    SendNUIMessage({ action = 'callNote', data = payload })
end)

-- Live "N responding" updates for visible alert popups.
RegisterNetEvent('ps-dispatch:client:unitCount', function(payload)
    SendNUIMessage({ action = 'unitCount', data = payload })
end)

-- Generation token for the respond-keybind window. The old implementation
-- polled `while timerCheck do Wait(1000)` for the full alert duration — one
-- polling thread per alert — and `timerCheck` was a GLOBAL shared by all of
-- them, so overlapping alerts terminated each other's windows early and the
-- keybinds flipped back at the wrong time. Now each alert bumps the token
-- and a single deferred check re-enables the keybinds only if no newer alert
-- has extended the window since.
local respondWindowToken = 0

RegisterNetEvent('ps-dispatch:client:notify', function(data)
    if data.alertTime == nil then data.alertTime = Config.AlertTime end
    local timer = data.alertTime * 1000

    if alertsDisabled then return end
    if not isJobValid(data.jobs) then return end
    if not IsOnDuty() then return end

    -- Log plate checks before the popup filters below. Muting the 'platecheck'
    -- type is about screen noise, not about forgetting what you looked up —
    -- the log is exactly where a muted check should still end up.
    if CapturePlateCheck then CapturePlateCheck(data) end
    -- "Priority alerts only": routine chatter is dropped entirely (no popup,
    -- no blip, no sound). Assignments addressed to this unit always pass.
    if prefPriorityOnly and data.priority ~= 1 and not data.assigned then return end
    -- Personal alert-type mutes (settings modal). Assignments addressed to
    -- this unit are never muted.
    if data.codeName and prefMutedCodes[data.codeName] and not data.assigned then return end

    -- Straight-line distance to the call at the moment it comes in — the
    -- single most useful fact for deciding whether to respond, and the menu
    -- can't provide it (server data has no receiver position). Metres;
    -- formatted NUI-side.
    local dc = data.displayCoords or data.coords
    if dc and dc.x then
        local pcoords = GetEntityCoords(cache.ped or PlayerPedId())
        local dx, dy = pcoords.x - dc.x, pcoords.y - dc.y
        data.distance = math.floor(math.sqrt(dx * dx + dy * dy))
    end

    SendNUIMessage({
        action = 'newCall',
        data = {
            data = data,
            timer = timer,
        }
    })

    local blipCfg = Config.Blips[data.codeName] or data.alert
    if prefBlips then
        addBlip(data, blipCfg)
    end
    -- Sound is deliberately NOT tied to the blip preference: it used to live
    -- inside addBlip, so switching "Map Blips" off in the settings silently
    -- killed alert audio as well. Muting the map must not mute the radio.
    -- Sound is deliberately NOT tied to the blip preference: it used to live
    -- inside addBlip, so switching "Map Blips" off silently killed alert
    -- audio too. Muting the map must not mute the radio.
    if not alertsMuted then
        playAlertSound(data, blipCfg)
    end

    -- Only the respond keybind is gated by the alert window. The menu key is
    -- a separate bind (Config.OpenDispatchMenu), so disabling it here just
    -- swallowed presses during the very seconds an officer is most likely to
    -- want the menu.
    RespondToDispatch:disable(false)

    activeAlertId = data.id
    activeAlertUntil = GetGameTimer() + timer

    respondWindowToken = respondWindowToken + 1
    local token = respondWindowToken
    SetTimeout(timer, function()
        if token ~= respondWindowToken then return end -- a newer alert owns the window
        RespondToDispatch:disable(true)
    end)
end)

RegisterNetEvent('ps-dispatch:client:openMenu', function(data)
    if not isJobValid(PlayerData.job.type) then return end
    if not IsOnDuty() then return end

    -- The menu now holds the plate log as well, so "no calls" is no longer the
    -- same as "nothing to show" — an officer with scanner hits and a quiet
    -- board still needs to get in.
    local plateCount = GetPlateHitCount and GetPlateHitCount() or 0

    if #data == 0 and plateCount == 0 then
        lib.notify({ description = locale('no_calls'), position = 'top', type = 'error' })
    else
        toggleUI(true)
        -- Plate log first: the NUI decides which tab to open on, and it can
        -- only do that once it knows whether there are hits. The Lua list is
        -- the source of truth — the NUI store is empty after any UI reload.
        if PushPlateHits then PushPlateHits() end
        SendNUIMessage({ action = 'setDispatchs', data = data, })
    end
end)

-- EventHandlers
RegisterNetEvent("QBCore:Client:OnJobUpdate", setupDispatch)

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    setupDispatch()
    createZones()
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', removeZones)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    setupDispatch()
    -- Restart parity: zones were only ever created on OnPlayerLoaded, so a
    -- resource restart silently killed hunting/no-dispatch detection until
    -- the next relog. (This is also why resmon showed ~0.03ms after joining
    -- but 0.00 after a restart — the cost IS the ox_lib zone frame loop, and
    -- after a restart it simply wasn't running anymore. With empty zone
    -- lists in the config there are no zones and no frame loop at all.)
    if LocalPlayer.state.isLoggedIn then
        createZones()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    removeZones()
end)

-- NUICallbacks
RegisterNUICallback("hideUI", function(_, cb)
    toggleUI(false)
    cb("ok")
end)

RegisterNUICallback("attachUnit", function(data, cb)
    TriggerServerEvent('ps-dispatch:server:attach', data.id, PlayerData)
    local at = alertPosition(data)
    if at then SetNewWaypoint(at.x, at.y) end
    TriggerEvent('ps-dispatch:client:selfAttach', data.id)
    SendNUIMessage({ action = 'callResponded', data = data.id })
    cb("ok")
end)

RegisterNUICallback("detachUnit", function(data, cb)
    TriggerServerEvent('ps-dispatch:server:detach', data.id, PlayerData)
    DeleteWaypoint()
    TriggerEvent('ps-dispatch:client:selfDetach', data.id)
    SendNUIMessage({ action = 'callUnresponded', data = data.id })
    cb("ok")
end)

RegisterNUICallback("toggleMute", function(data, cb)
    local muteStatus = data.boolean and locale('muted') or locale('unmuted')
    lib.notify({ description = locale('alerts') .. muteStatus, position = 'top', type = 'warning' })
    alertsMuted = data.boolean
    cb("ok")
end)

RegisterNUICallback("toggleAlerts", function(data, cb)
    local muteStatus = data.boolean and locale('disabled') or locale('enabled')
    lib.notify({ description = locale('alerts') .. muteStatus, position = 'top', type = 'warning' })
    alertsDisabled = data.boolean
    cb("ok")
end)

RegisterNUICallback("clearBlips", function(data, cb)
    lib.notify({ description = locale('blips_cleared'), position = 'top', type = 'success' })
    for _, v in pairs(blips) do
        RemoveBlip(v)
    end
    for _, v in pairs(radius2) do
        RemoveBlip(v)
    end
    blips, radius2 = {}, {}
    cb("ok")
end)

RegisterNUICallback("clearCall", function(data, cb)
    TriggerServerEvent('ps-dispatch:server:clearCall', data.id)
    cb('ok')
end)

RegisterNUICallback("setCallNote", function(data, cb)
    TriggerServerEvent('ps-dispatch:server:setCallNote', data.id, data.note)
    cb('ok')
end)

RegisterNUICallback("getStats", function(_, cb)
    local st = lib.callback.await('ps-dispatch:callback:getStats', false)
    SendNUIMessage({ action = 'stats', data = st })
    cb("ok")
end)

RegisterNUICallback("refreshAlerts", function(data, cb)
    lib.notify({ description = locale('alerts_refreshed'), position = 'top', type = 'success' })
    local data = lib.callback.await('ps-dispatch:callback:getCalls', false)
    SendNUIMessage({ action = 'setDispatchs', data = data, })
    cb("ok")
end)


-- ── Test sequence (Config.TestCommand) ───────────────────────────────────────
-- Fires one representative alert every 10 seconds, each exercising a
-- different card section: vehicle strip, weapon banner, priority styling,
-- person line, quoted note — and finally two identical alerts back-to-back
-- to demonstrate the ×N merge. Deterministic on purpose: the scripted
-- scenarios don't require holding a weapon or sitting in a vehicle.
-- Sound diagnostics: prints every gate that can silence an alert and plays
-- the configured default through whichever backend is actually active.
if Config.TestCommand then
    -- /dispatchsound                      -> plays routine, then priority
    -- /dispatchsound <audioName> <audioRef> -> tries an arbitrary pair, so a
    --                                          replacement can be auditioned
    --                                          without editing the config.
    RegisterCommand('dispatchsound', function(_, args)
        if alertsMuted then
            lib.notify({ description = 'Alerts are muted (settings > Alert Sounds)', type = 'error' })
            return
        end

        if args and args[1] and args[2] then
            PlaySound(-1, args[1], args[2], 0, 0, 1)
            lib.notify({ description = ('Played %s / %s'):format(args[1], args[2]), type = 'inform' })
            return
        end

        local cfg = Config.AlertSounds or {}
        print(('[ps-dispatch] default=%s/%s | priority=%s/%s')
            :format(tostring(cfg.default and cfg.default.audioName),
                tostring(cfg.default and cfg.default.audioRef),
                tostring(cfg.priority and cfg.priority.audioName),
                tostring(cfg.priority and cfg.priority.audioRef)))
        playAlertSound({ priority = 2 })
        SetTimeout(1400, function() playAlertSound({ priority = 1 }) end)
        lib.notify({ description = 'Routine sound, then priority sound', type = 'inform' })
    end, false)

    RegisterCommand(Config.TestCommand, function()
        CreateThread(function()
            local res = GetCurrentResourceName()
            local coords = GetEntityCoords(cache.ped or PlayerPedId())

            local sequence = {
                -- 1: vehicle strip showcase
                function()
                    exports[res]:CustomAlert({
                        message = 'Vehicle Theft', dispatchCode = 'test-vehicle', code = '10-16',
                        icon = 'fas fa-car', priority = 2, coords = coords,
                        model = 'Sultan RS', plate = 'PS 12345', firstColor = 'Metallic Red',
                        class = 'Sports', doorCount = 4, jobs = { 'leo' },
                    })
                end,
                -- 2: priority + weapon banner + automatic fire
                function()
                    exports[res]:CustomAlert({
                        message = 'Shots Fired', dispatchCode = 'test-shots', code = '10-71',
                        icon = 'fas fa-gun', priority = 1, coords = coords,
                        weapon = 'Assault Rifle', automaticGunfire = true, jobs = { 'leo' },
                    })
                end,
                -- 3-7: stock alerts, no prerequisites
                function() exports[res]:Fight() end,
                function() exports[res]:DrugSale() end,
                function() exports[res]:SuspiciousActivity() end,
                function() exports[res]:HouseRobbery() end,
                function() exports[res]:Explosion() end,
                -- 8: person line + quoted note (911-style)
                function()
                    exports[res]:CustomAlert({
                        message = '911 Call', dispatchCode = 'test-911', code = '911',
                        icon = 'fas fa-phone', priority = 2, coords = coords,
                        name = 'John Doe', gender = true, number = '555-0173',
                        information = 'Caller reports a suspect fleeing on foot towards the alley, wearing a red hoodie.',
                        jobs = { 'leo' },
                    })
                end,
                -- 9: merge demo — same alert twice within seconds -> ×2
                function()
                    local merge = function()
                        exports[res]:CustomAlert({
                            message = 'Gun Shots', dispatchCode = 'test-merge', code = '10-71',
                            icon = 'fas fa-gun', priority = 2, coords = coords, jobs = { 'leo' },
                        })
                    end
                    merge()
                    SetTimeout(3000, merge)
                end,
            }

            lib.notify({ description = ('Dispatch test: %d alerts, 10s apart'):format(#sequence), type = 'inform' })
            for i = 1, #sequence do
                sequence[i]()
                if i < #sequence then Wait(math.random(2000,10000)) end
            end
        end)
    end, false)
end