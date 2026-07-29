-- ═══════════════════════════════════════════════════════════════════════════
--  Plate check log
-- ═══════════════════════════════════════════════════════════════════════════
-- A private log of the plate checks this officer has run.
--
-- Nothing feeds this deliberately. Plate checks already arrive here as ordinary
-- targeted alerts — ps-mdt's PlateCheckAlert sends them through
-- SendTargetedAlert with codeName 'platecheck' — so the log simply keeps the
-- ones that scroll past instead of asking the scanner to report twice.
--
-- The list lives on the officer's own client and never touches the server,
-- which is both the privacy guarantee and why no database is involved: a plate
-- check is an answer to one unit's question, not a dispatch event.

local resourceName = GetCurrentResourceName()

local function cfg()
    return (Config and Config.PlateScanner) or {}
end

--- Newest first, capped at Config.PlateScanner.MaxHits.
local plateHits = {}
local hitSeq = 0
local lastBackupAt = 0

local function pushHitsToNui()
    SendNUIMessage({ action = 'plateHits', data = plateHits })
end

--- Does this incoming alert belong in the plate log?
---@param data table the alert payload
---@return boolean
local function isPlateCheck(data)
    if not PlateTabAllowed() then return false end
    if type(data) ~= 'table' or type(data.plate) ~= 'string' then return false end

    local names = cfg().CodeNames
    if type(names) == 'table' and #names > 0 then
        for i = 1, #names do
            if data.codeName == names[i] then return true end
        end
        return false
    end

    -- No list configured: fall back to the convention the UI already uses —
    -- an alert carrying a footer is an ANSWER (plate check, record lookup)
    -- rather than a job. A vehicle-theft alert also carries a plate, but no
    -- footer, so this doesn't sweep real calls into the log.
    return type(data.footer) == 'table'
end

--- Does this player's job get the Plates tab? Enabled alone isn't enough:
--- the log is police work, and an EMS unit would carry an empty tab plus a tab
--- bar that switches between one panel and nothing.
---@return boolean
function PlateTabAllowed()
    if cfg().Enabled == false then return false end

    local allowed = cfg().Jobs
    if type(allowed) ~= 'table' or #allowed == 0 then return true end

    local jobType = PlayerData and PlayerData.job and PlayerData.job.type
    if not jobType then return false end
    for i = 1, #allowed do
        if allowed[i] == jobType then return true end
    end
    return false
end

--- The plate design of a vehicle currently in the world wearing this exact
--- plate, or nil if none is.
---
--- A plate check is a database lookup, so the alert carries no design — but the
--- officer who ran it is looking at the car as it arrives, so the answer is
--- usually right there. The match is on the exact plate string: a near-miss
--- never matches, and a vehicle that has already driven off simply yields nil
--- and the neutral badge. Nothing is guessed.
---@param plate string already normalised (no spaces, upper case)
---@return number|nil
local function findPlateIndex(plate)
    local ok, result = pcall(function()
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            local text = GetVehicleNumberPlateText(veh)
            if text and text:gsub('%s+', ''):upper() == plate then
                return GetVehicleNumberPlateTextIndex(veh)
            end
        end
        return nil
    end)
    if ok then return result end
    return nil
end

--- Street label for a set of coords, or nil.
---@param c table|nil
---@return string|nil
local function resolveStreet(c)
    if not c or not c.x or not GetStreetAndZone then return nil end
    local ok, label = pcall(GetStreetAndZone, vector3(c.x + 0.0, c.y + 0.0, (c.z or 0.0) + 0.0))
    if ok and type(label) == 'string' and label ~= '' then return label:sub(1, 64) end
    return nil
end

--- Record a plate check. Called from the notify handler, not by other
--- resources — see the header for why there is no export here.
---@param data table the alert payload
local function logPlateCheck(data)
    local plate = data.plate:gsub('%s+', ''):upper():sub(1, 12)
    if plate == '' then return end

    local function str(v, limit)
        if type(v) ~= 'string' then return nil end
        local t = v:gsub('^%s+', ''):gsub('%s+$', '')
        if t == '' then return nil end
        return t:sub(1, limit or 64)
    end

    local footer = type(data.footer) == 'table' and data.footer or nil

    hitSeq = hitSeq + 1
    local hit = {
        id      = hitSeq,
        plate   = plate,
        vehicle = str(data.vehicle, 48),
        -- The alert's own value wins when the querying resource sends one;
        -- otherwise read it off the car in front of the officer.
        plateIndex = tonumber(data.plateIndex) or findPlateIndex(plate),
        owner   = str(data.name, 48),
        -- The MDT already phrased the result; repeating that judgement here
        -- would only risk disagreeing with the alert the officer just read.
        summary = str(data.information, 160),
        -- PlateCheckAlert sends coords but no street name, so resolve it here.
        -- Only the label is kept — with no waypoint button there's no reason to
        -- hold on to the position itself.
        street  = str(data.street, 64) or resolveStreet(data.displayCoords or data.coords),
        footerText = footer and str(footer.text, 64) or nil,
        footerIcon = footer and str(footer.icon, 48) or nil,
        tone    = ((footer and footer.tone == 'alert') or (tonumber(data.priority) or 3) <= 1) and 'alert' or 'normal',
        time    = GetGameTimer(),
        -- os.* is server-only in FiveM's Lua; GetCloudTimeAsInt is the
        -- client-side wall clock, same as client/main.lua uses.
        stamp   = GetCloudTimeAsInt() * 1000,
    }

    -- The same plate answered again within a few seconds is a re-query, not a
    -- new event — refresh the entry rather than stacking duplicates.
    for i = 1, #plateHits do
        local existing = plateHits[i]
        if existing.plate == plate and (hit.time - existing.time) < 8000 then
            hit.id = existing.id
            plateHits[i] = hit
            pushHitsToNui()
            return
        end
    end

    table.insert(plateHits, 1, hit)

    local max = tonumber(cfg().MaxHits) or 40
    while #plateHits > max do table.remove(plateHits) end

    pushHitsToNui()
end

--- Entry point for client/main.lua's notify handler.
---@param data table
function CapturePlateCheck(data)
    if not isPlateCheck(data) then return end
    logPlateCheck(data)
end

--- How many checks are logged. Global so client/main.lua can decide whether
--- the menu has anything to show. Reports zero when the log is disabled, so
--- stale entries can't be the reason the menu opens on an empty call list.
---@return number
function GetPlateHitCount()
    if not PlateTabAllowed() then return 0 end
    return #plateHits
end

--- Re-send the log to the NUI. The Lua list is the source of truth and the
--- NUI store is empty after any UI reload.
function PushPlateHits()
    pushHitsToNui()
end

local function clearPlateHits(id)
    if id then
        for i = #plateHits, 1, -1 do
            if plateHits[i].id == id then table.remove(plateHits, i) break end
        end
    else
        plateHits = {}
    end
    pushHitsToNui()
end

-- ── NUI bridge ──────────────────────────────────────────────────────────────

RegisterNUICallback('getPlateHits', function(_, cb)
    cb(plateHits)
end)

RegisterNUICallback('clearPlateHits', function(data, cb)
    clearPlateHits(data and tonumber(data.id) or nil)
    cb('ok')
end)

-- Backup request. Routed through ps-dispatch's own OfficerBackup export rather
-- than a hand-rolled alert, so it lands on the board looking exactly like every
-- other backup call — same code, same blip, same sound. The plate stays on this
-- officer's screen; what backup needs is a position.
RegisterNUICallback('plateBackup', function(_, cb)
    if cfg().Enabled == false then cb({ ok = false, message = locale('plate_log_disabled') }) return end
    if cfg().BackupButton == false then cb({ ok = false, message = locale('plate_backup_disabled') }) return end

    local now = GetGameTimer()
    local cooldown = tonumber(cfg().BackupCooldownMs) or 15000
    if now - lastBackupAt < cooldown then
        cb({ ok = false, message = locale('plate_backup_cooldown') })
        return
    end
    lastBackupAt = now

    local ok = pcall(function() exports[resourceName]:PlateBackup() end)
    cb({ ok = ok, message = ok and nil or locale('plate_backup_failed') })
end)
-- A job change flips the answer, and setupUI only runs once. Without this a
-- cop who goes on as a medic keeps the tab, and vice versa keeps it hidden.
local function pushTabVisibility()
    SendNUIMessage({ action = 'platesEnabled', data = PlateTabAllowed() })
    if not PlateTabAllowed() then
        plateHits = {}
        pushHitsToNui()
    end
end

RegisterNetEvent('QBCore:Client:OnJobUpdate', function()
    CreateThread(function() Wait(500) pushTabVisibility() end)
end)

RegisterNetEvent('qbx_core:client:onJobUpdate', function()
    CreateThread(function() Wait(500) pushTabVisibility() end)
end)
