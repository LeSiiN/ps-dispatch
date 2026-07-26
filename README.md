# PS Dispatch

Integrated with [ps-mdt](https://github.com/Project-Sloth/ps-mdt)

For all support questions, ask in our [Discord](https://www.discord.gg/projectsloth) support chat. 
Do not create issues on GitHub if you need help. Issues are for bug reporting and new features only.

# Depedency
1. [qb-core](https://github.com/qbcore-framework/qb-core)
2. [ox_lib](https://github.com/overextended/ox_lib)
3. [ps-mdt](https://github.com/Project-Sloth/ps-mdt) - Optional but highly recommended.

# Installation
* Download ZIP
* Make sure your [qb-core](https://github.com/qbcore-framework/qb-core) is fully updated to the latest version.
* Drag and drop resource into your server files
* Start resource through server.cfg
* Drag and drop sounds folder into interact-sound\client\html\sounds
* Configure your [language](https://github.com/Project-Sloth/ps-dispatch#change-language)
* Restart your server.

# Preview

<img src="https://r2.fivemanage.com/image/nESTkFw4aLN6.png" width="450">
<img src="https://r2.fivemanage.com/image/PUnOJqjeitEB.png" width="450">
<img src="https://r2.fivemanage.com/image/NmJPUpcNi4p1.png" width="450">

## Dispatch Menu
<img src="https://r2.fivemanage.com/image/rHccyBS2y48f.png" width="450">
<img src="https://r2.fivemanage.com/image/rhMK7Kwt91rg.jpg" width="450">

## Plates Tab
<img src="https://r2.fivemanage.com/image/7tARMHrRj7JN.png" width="450">

# Change Language.

- Place this `setr ox:locale en` inside your `server.cfg`
- Change the `en` to your desired language!
  
**Supported Languages:**
| **Alias**     | **Language Names** |
|--------------|---------------|
|en      |English    |
|de      |German     |
|nl      |Dutch      |
|cs      |Czech      |
|pt-br      |Brazilian Portuguese      |
|es      |Spanish      |

# Preset Alert Exports.

```lua
- exports['ps-dispatch']:ArtGalleryRobbery()
- exports['ps-dispatch']:CarBoosting(vehicle)
- exports['ps-dispatch']:CarJacking(vehicle)
- exports['ps-dispatch']:CustomAlert()
- exports['ps-dispatch']:DeceasedPerson()
- exports['ps-dispatch']:DrugBoatRobbery()
- exports['ps-dispatch']:DrugSale()
- exports['ps-dispatch']:EmsDown()
- exports['ps-dispatch']:Explosion()
- exports['ps-dispatch']:Fight()
- exports['ps-dispatch']:FleecaBankRobbery(camId)
- exports['ps-dispatch']:HouseRobbery()
- exports['ps-dispatch']:HumaneRobbery()
- exports['ps-dispatch']:Hunting()
- exports['ps-dispatch']:InjuriedPerson()
- exports['ps-dispatch']:OfficerDown()
- exports['ps-dispatch']:OfficerBackup()
- exports['ps-dispatch']:OfficerInDistress()
- exports['ps-dispatch']:PacificBankRobbery(camId)
- exports['ps-dispatch']:PaletoBankRobbery(camId)
- exports['ps-dispatch']:PrisonBreak()
- exports['ps-dispatch']:Shooting()
- exports['ps-dispatch']:SignRobbery()
- exports['ps-dispatch']:SpeedingVehicle(vehicle)
- exports['ps-dispatch']:StoreRobbery(camId)
- exports['ps-dispatch']:SuspiciousActivity()
- exports['ps-dispatch']:TrainRobbery()
- exports['ps-dispatch']:UndergroundRobbery()
- exports['ps-dispatch']:UnionRobbery()
- exports['ps-dispatch']:VangelicoRobbery(camId)
- exports['ps-dispatch']:VanRobbery()
- exports['ps-dispatch']:VehicleShooting(vehicle)
- exports['ps-dispatch']:VehicleTheft(vehicle)
- exports['ps-dispatch']:YachtHeist()
- exports['ps-dispatch']:BobcatSecurityHeist()
```
# Steps to Create New Alert
Add the following into your `alerts.lua` and change to your liking:
```
local function TestAlert()
    local coords = GetEntityCoords(cache.ped)
    local vehicle = GetVehicleData(cache.vehicle)

    local dispatchData = {
        message = locale('testalert'), -- add this into your locale
        codeName = 'testalert', -- this should be the same as in config.lua
        code = '10-35',
        icon = 'fas fa-car-burst',
        priority = 2,
        coords = coords,
        street = GetStreetAndZone(coords),
        heading = GetPlayerHeading(),
        vehicle = vehicle.name,
        plate = vehicle.plate,
        color = vehicle.color,
        class = vehicle.class,
        doors = vehicle.doors,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end
exports('TestAlert', TestAlert)
```
Add codeName in `config.lua` for the particular robbery to display the blip
["testalert"] is the codename you passed with the TriggerServerEvent in step 1
```
    ['testalert'] = { -- Need to match the codeName in alerts.lua
        radius = 0,
        sprite = 119,
        color = 1,
        scale = 1.5,
        length = 2,
        sound = 'Lose_1st',
        sound2 = 'GTAO_FM_Events_Soundset',
        offset = false,
        flash = false
    },
```
Information about each parameter is in the `alerts.lua` file.


## Plate check log

The dispatch menu has two tabs: **Calls** (the shared board) and **Plates** (this officer's own plate-check log).

Nothing needs wiring up. Plate checks already arrive as targeted alerts — ps-mdt's `PlateCheckAlert` sends them through `SendTargetedAlert` with `codeName = 'platecheck'` — and the log simply keeps the ones that scroll past. Hits never leave the client that ran them, which is both the privacy guarantee and why no database is involved.

A muted `platecheck` type still lands in the log: muting is about screen noise, not about forgetting what you looked up.

Each entry can be dismissed or escalated with **Request backup** — which sends ps-dispatch's ordinary `OfficerBackup` alert, so it reaches the board looking like every other backup call. Two-step confirm and a cooldown, since it puts a priority call on everyone's board.

```lua
Config.PlateScanner = {
    Enabled = true,           -- false removes the tab and the tab bar with it
    MaxHits = 40,
    CodeNames = { 'platecheck' },   -- empty = any alert with a plate AND a footer
    BackupButton = true,
    BackupCooldownMs = 15000,
}
```

Repeat checks on the same plate within a few seconds refresh the existing entry rather than stacking duplicates.

## Major incidents

A supervisor can declare a call a major incident. It pins to the top of every board, shows as a banner, and — optionally — routine chatter goes quiet for the units working it.

Deliberately **not** server-wide silence. Only units attached to an incident are shielded, and only from routine traffic: priority 1 calls, backup requests and anything addressed to a unit always come through, the same carve-outs the existing "priority only" preference uses. A second emergency across town is never hidden by the first.

Several incidents can run at once, each with its own banner strip. The banner says routine traffic is being held back — without that, a quiet board just looks broken.

```lua
Config.MajorIncident = {
    Enabled = true,
    Grades = { police = 4, ambulance = 4 },  -- minimum grade per job name
    Duration = 1800,     -- seconds, then it ends on its own
    QuietRoutine = true, -- quiet routine traffic for attached units
    MaxActive = 3,
}
```

Declaring happens from the call itself — open a call and the button sits under Attach — because an incident is always *a specific call*. Two-step confirm, since it changes everyone's board.

Anyone of the right grade can stand one down, not just whoever declared it: otherwise the state sticks when that player logs off. It also ends on its own after `Duration`, and immediately when the call is cleared. Re-declaring an active incident extends it rather than resetting it.

The client hides the button when the grade doesn't qualify, but that's cosmetics — the server re-checks the grade on every declare and stand-down.

## Critical alerts (priority 0)
 
A tier above the existing red, for calls that make every unit drop what it is doing. `Config.CriticalCodes` lists the alert code names that get it:
 
```lua
Config.CriticalCodes = {
    'officerdown', 'officerbackup', 'officerdistress', 'emsdown',
    'bankrobbery', 'pacificbankrobbery', 'paletobankrobbery',
    'vangelicorobbery', 'humanelabsrobbery', 'unionrobbery', 'prisonbreak',
}
```
 
Nothing is renumbered — existing integrations keep sending priority 1/2/3 and keep their meaning. Only these code names are lifted above them, and the upgrade happens once on the server, so alerts coming from other resources via `CustomAlert` are covered by their code name alone.
 
Repeated reports still escalate a routine call to priority 1, but **never into this tier**: critical is granted, not accumulated. Otherwise noise would climb back to the top over time, which is the problem the tier was added to fix.
 
Critical calls sort to the top of the board and carry their own treatment — a heavier border and a slow pulse rather than another shade of red, since two reds are hard to tell apart at a glance. The in-app reduced-motion preference turns the pulse off and keeps the weight.
 
Keep the list short. A board where half the calls are critical is exactly the situation this replaced.

## Search radius and position offset
 
Alerts with `offset = true` in `Config.Blips` report an approximate position: officers get a circle to search rather than a pin to drive to.
 
The displacement is now bounded by that circle's own radius, so **the incident is always inside the area being searched**. Previously the two were independent — an explosion drew a 75 m circle while the position could be thrown up to `Config.MaxOffset` on each axis, roughly 170 m diagonally, so the circle usually did not contain the incident at all.
 
It is also area-uniform rather than radius-uniform: every point in the circle is equally likely, so the centre is no better a guess than the edge. Sampling the distance linearly would have piled the truth up in the middle and officers would have learned to search there first.
 
Two further changes make the circle mean what it says:
 
- **The offset is fixed per call.** Repeat reports move the circle with the incident but reuse the same displacement. Re-randomising on every report let anyone average the jumps and triangulate the true spot — the more reports, the better the estimate, which is backwards.
- **The true coordinates no longer leave the server.** Offset alerts used to ship `coords` alongside `displayCoords`, so the approximation was decoration: anything reading the packet could see straight through it. Every path out — broadcast, targeted alert, call list, menu — now strips them.

# FAQ
* There are no calls showing on dispatch or mdt list.
  - Make sure you have a job type specified in your qbcore/shared/jobs.lua like:
  
    ![image](https://github.com/Project-Sloth/ps-dispatch/assets/9503151/7834e878-5020-4fcc-8864-03d44120c160)

  - Make sure that you're using the correct job type as leo and make sure your [qb-core](https://github.com/qbcore-framework/qb-core) is fully updated to the latest version.
  - On shared/config.lua make set Config.Debug = true to test calls as police officer.(ONLY to be used as testing, make sure to disable on live production)

* How to change colors of the calls? 
  - Priority 1 is red and priority 2 is normal on the config.

* To increase the time that calls are shown on the screen, do the following:
  - Find the "alerts.lua" file in the client folder.
  - Open this file with a text editor or a development tool like Visual Studio Code.
  - Look for the code "alertTime = nil".
  - Replace "nil" with the number of seconds you want the calls to display. For example, setting "alertTime = 25" means calls will be shown for 25 seconds.

# Credits
* [OK1ez](https://github.com/OK1ez)
* [Candrex](https://github.com/CandrexDev)
* [Lenzh](https://github.com/Lenzh)
* [LeSiiN](https://github.com/LeSiiN)
* Project Sloth Team
 
---

# 1of1 Servers - VPS & Dedicated Servers

[![1of1 Servers](https://github.com/user-attachments/assets/29e4ef8e-7b24-4821-a6ce-7c9e3c111fd1)](https://billing.1of1servers.com/aff.php?aff=1)

We are a VPS and dedicated server provider, specializing in strong gaming DDoS protection and 99.9% uptime.  

We host some of the biggest FiveM servers in the industry such as Prodigy RP, Smile RP, The Academy RP, and many more.  

---

### Features
- 4 Tbps DDoS Protection by CosmicGuard  
- 99.9% Network Uptime  
- NVMe SSD Storage  
- Unlimited Player Slots  
- Free transfer of files and setup  
- Free Windows licenses  
- Windows Remote Desktop  
- 24/7 Support with ~30 min average ticket response  

---

### Locations
- USA: Dallas, Ashburn, Los Angeles, Chicago  
- Europe: UK, Germany, Netherlands  
- Asia: Singapore  
- Australia: Sydney  

---

### Links
- [Website](https://billing.1of1servers.com/aff.php?aff=1)
- [Discord](https://discord.gg/1of1servers)