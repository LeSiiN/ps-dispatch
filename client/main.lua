QBCore = exports['qb-core']:GetCoreObject()
PlayerData = {}
inHuntingZone, inNoDispatchZone = false, false
local huntingZones, nodispatchZones, huntingBlips = {} , {}, {}

local blips = {}
local radius2 = {}
local alertsMuted = false
local alertsDisabled = false
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
            mapImage = Config.MdtMapImage or false,
            unattendedAfter = Config.UnattendedAfter or 0,
            pinnedCodes = Config.PinnedCodes or {},
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

local function openMenu()
    if not isJobValid(PlayerData.job.type) then return end

    local calls = lib.callback.await('ps-dispatch:callback:getCalls', false)
    if #calls == 0 then
        lib.notify({ description = locale('no_calls'), position = 'top', type = 'error' })
    else
        SendNUIMessage({ action = 'setDispatchs', data = calls, })
        toggleUI(true)
    end
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

    if not waypointCooldown and lib.table.contains(data.jobs, PlayerData.job.type) then
        SetNewWaypoint(data.coords.x, data.coords.y)
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
    local at = data.displayCoords or data.coords
    blip, radius = createBlipData({ x = at.x, y = at.y, z = data.coords.z or 0 }, blipData.radius, sprite, color, scale, flash)
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

local function addBlip(data, blipData)
    -- Defensive: an alert whose codeName has no blip config and no inline
    -- alert table gets no blip/sound rather than a nil-index error.
    if type(blipData) ~= 'table' then return end
    -- A merged repeat of an existing call keeps its original blip: the fade
    -- thread for data.id is still running, spawning a second one would leak
    -- the first handle and double up map markers.
    if not (data.merged and blips[data.id]) then
        CreateThread(function()
            createBlip(data, blipData)
        end)
    end
    if not alertsMuted then
        if blipData.sound == "Lose_1st" then
            PlaySound(-1, blipData.sound, blipData.sound2, 0, 0, 1)
        elseif Config.LocalSounds ~= false then
            -- Local playback: same interact-sound file, minus one server
            -- round-trip per alert (the old path went client -> server ->
            -- back to this client).
            TriggerEvent("InteractSound_CL:PlayOnOne", blipData.sound or blipData.alert.sound, 0.25)
        else
            TriggerServerEvent("InteractSound_SV:PlayOnSource", blipData.sound or blipData.alert.sound, 0.25)
        end
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

    addBlip(data, Config.Blips[data.codeName] or data.alert)

    RespondToDispatch:disable(false)
    OpenDispatchMenu:disable(true)

    respondWindowToken = respondWindowToken + 1
    local token = respondWindowToken
    SetTimeout(timer, function()
        if token ~= respondWindowToken then return end -- a newer alert owns the window
        OpenDispatchMenu:disable(false)
        RespondToDispatch:disable(true)
    end)
end)

RegisterNetEvent('ps-dispatch:client:openMenu', function(data)
    if not isJobValid(PlayerData.job.type) then return end
    if not IsOnDuty() then return end

    if #data == 0 then
        lib.notify({ description = locale('no_calls'), position = 'top', type = 'error' })
    else
        toggleUI(true)
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
    SetNewWaypoint(data.coords.x, data.coords.y)
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
if Config.TestCommand then
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
                if i < #sequence then Wait(10000) end
            end
        end)
    end, false)
end
