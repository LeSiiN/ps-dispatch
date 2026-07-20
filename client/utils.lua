function GetPlayerHeading()
    local heading = GetEntityHeading(cache.ped)

    if heading >= 315 or heading < 45 then
        return locale('north')
    elseif heading >= 45 and heading < 135 then
        return locale('west')
    elseif heading >= 135 and heading < 225 then
        return locale('south')
    elseif heading >= 225 and heading < 315 then
        return locale('east')
    end
end

function GetPlayerGender()
    local gender = locale('male')
    if QBCore.Functions.GetPlayerData().charinfo.gender == 1 then
        gender = locale('female')
    end
    return gender
end

function GetIsHandcuffed()
    -- Standard Lua instead of CfxLua's `?.` so the file passes plain luac.
    local pd = QBCore.Functions.GetPlayerData()
    return pd and pd.metadata and pd.metadata.ishandcuffed
end

function IsOnDuty()
    if Config.OnDutyOnly then
        if QBCore.Functions.GetPlayerData().job.onduty then
            return true
        else
            return false
        end
    end
    return true
end

---@return boolean
local function HasPhone()
    for _, item in ipairs(Config.PhoneItems) do
        if QBCore.Functions.HasItem(item) then
            return true
        end
    end
    return false
end

---@param coords table
---@return string
function GetStreetAndZone(coords)
    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z))
    -- Unnamed roads (dirt tracks, most of Cayo) return an empty street —
    -- blindly concatenating produced leading-comma strings like ", Cayo
    -- Perico". Join only the parts that exist.
    local parts = {}
    if street and street ~= '' then parts[#parts + 1] = street end
    if zone and zone ~= '' and zone ~= 'NULL' then parts[#parts + 1] = zone end
    return table.concat(parts, ', ')
end

---@param vehicle string
---@return string
local function getVehicleColor(vehicle)
    local vehicleColor1, vehicleColor2 = GetVehicleColours(vehicle)
    local color1 = Config.Colors[tostring(vehicleColor1)]
    local color2 = Config.Colors[tostring(vehicleColor2)]

    if color1 and color2 then
        return color2 .. " on " .. color1
    elseif color1 then
        return color1
    elseif color2 then
        return color2
    else
        return "Unknown"
    end
end

---@param vehicle string
---@return string
local function getVehicleDoors(vehicle)
    local doorCount = 0

    if GetEntityBoneIndexByName(vehicle, 'door_pside_f') ~= -1 then doorCount = doorCount + 1 end
    if GetEntityBoneIndexByName(vehicle, 'door_pside_r') ~= -1 then doorCount = doorCount + 1 end
    if GetEntityBoneIndexByName(vehicle, 'door_dside_f') ~= -1 then doorCount = doorCount + 1 end
    if GetEntityBoneIndexByName(vehicle, 'door_dside_r') ~= -1 then doorCount = doorCount + 1 end

    if doorCount == 2 then
        doorCount = locale('two_door')
    elseif doorCount == 3 then
        doorCount = locale('three_door')
    elseif doorCount == 4 then
        doorCount = locale('four_door')
    else
        doorCount = 'unknown'
    end

    return doorCount
end

---@param vehicle string
---@return table
function GetVehicleData(vehicle)
    local data = {}

    local vehicleClass = {
        [0] = locale('compact'),
        [1] = locale('sedan'),
        [2] = locale('suv'),
        [3] = locale('coupe'),
        [4] = locale('muscle'),
        [5] = locale('sports_classic'),
        [6] = locale('sports'),
        [7] = locale('super'),
        [8] = locale('motorcycle'),
        [9] = locale('offroad'),
        [10] = locale('industrial'),
        [11] = locale('utility'),
        [12] = locale('van'),
        [17] = locale('service'),
        [19] = locale('military'),
        [20] = locale('truck')
    }

    data.class = vehicleClass[GetVehicleClass(vehicle)] or "Unknown"
    data.name = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
    data.plate = GetVehicleNumberPlateText(vehicle)
    data.doors = getVehicleDoors(vehicle)
    data.color = getVehicleColor(vehicle)
    data.id = NetworkGetNetworkIdFromEntity(vehicle)

    return data
end

function PhoneAnimation()
    lib.requestAnimDict("cellphone@in_car@ds", 500)

    if not IsEntityPlayingAnim(cache.ped, "cellphone@in_car@ds", "cellphone_call_listen_base", 3) then
        TaskPlayAnim(cache.ped, "cellphone@in_car@ds", "cellphone_call_listen_base", 3.0, 3.0, -1, 50, 0, false, false, false)
    end

    Wait(2500)
    StopEntityAnim(cache.ped, "cellphone_call_listen_base", "cellphone@in_car@ds", 3)
end

---@param message string
---@return boolean
function IsCallAllowed(message)
    local msgLength = string.len(message)

    if msgLength == 0 then return false end
    if GetIsHandcuffed() then return false end
    if Config.PhoneRequired and not HasPhone() then QBCore.Functions.Notify('You need a communications device for this.', 'error', 5000) return false end

    return true
end

local weaponTable = {
    [584646201]   = "AP-Pistol",
    [453432689]   = "Pistol",
    [3219281620]  = "Pistol MK2",
    [1593441988]  = "Combat Pistol",
    [-1716589765] = "Heavy Pistol",
    [-1076751822] = "SNS-Pistol",
    [-771403250]  = "Desert Eagle",
    [137902532]   = "Vintage Pistol",
    [-598887786]  = "Marksman Pistol",
    [-1045183535] = "Revolver",
    [911657153]   = "Taser",
    [324215364]   = "Micro-SMG",
    [-619010992]  = "Machine-Pistol",
    [736523883]   = "SMG",
    [2024373456]  = "SMG MK2",
    [-270015777]  = "Assault SMG",
    [171789620]   = "Combat PDW",
    [-1660422300] = "Combat MG",
    [3686625920]  = "Combat MG MK2",
    [1627465347]  = "Gusenberg",
    [-1121678507] = "Mini SMG",
    [-1074790547] = "Assaultrifle",
    [961495388]   = "Assaultrifle MK2",
    [-2084633992] = "Carbinerifle",
    [4208062921]  = "Carbinerifle MK2",
    [-1357824103] = "Advancedrifle",
    [-1063057011] = "Specialcarbine",
    [2132975508]  = "Bulluprifle",
    [1649403952]  = "Compactrifle",
    [100416529]   = "Sniperrifle",
    [205991906]   = "Heavy Sniper",
    [177293209]   = "Heavy Sniper MK2",
    [-952879014]  = "Marksmanrifle",
    [487013001]   = "Pumpshotgun",
    [2017895192]  = "Sawnoff Shotgun",
    [-1654528753] = "Bullupshotgun",
    [-494615257]  = "Assaultshotgun",
    [-1466123874] = "Musket",
    [984333226]   = "Heavyshotgun",
    [-275439685]  = "Doublebarrel Shotgun",
    [317205821]   = "Autoshotgun",
    [-1568386805] = "GRENADE LAUNCHER",
    [-1312131151] = "RPG",
    [125959754]   = "Compactlauncher"
}

function GetWeaponName()
    local currentWeapon = GetSelectedPedWeapon(cache.ped)
    return weaponTable[currentWeapon] or "Unknown"
end
