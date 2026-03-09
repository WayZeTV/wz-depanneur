-- ============================================================
-- wz-depanneur | client.lua v2.0
-- Mécanique de dépanneur avec camion plateau (flatbed)
-- Le joueur doit accrocher le véhicule et le ramener au dépôt
-- ============================================================

-- ============================================================
-- VARIABLES LOCALES
-- ============================================================
local Framework     = nil
local FrameworkType = nil

-- États du joueur
local isOnDuty       = false
local isOnMission    = false
local isHooking      = false
local isTransporting = false  -- Véhicule accroché, en route vers le dépôt
local isDoingAction  = false  -- En train de faire une action spéciale

-- Entités de mission
local towTruck       = nil   -- Le camion plateau du joueur
local selectedTruck  = nil   -- Config du camion choisi par le joueur
local missionVeh     = nil   -- Le véhicule en panne
local missionVeh2    = nil   -- 2e véhicule (accident)
local missionPed     = nil   -- Le PNJ en attente
local missionBlip    = nil   -- Blip de la mission
local deliveryBlip   = nil   -- Blip du point de livraison

-- Type de mission en cours
local currentMissionType   = nil  -- string: 'panne', 'panne_seche', 'batterie', etc.
local currentMissionConfig = nil  -- table config du type en cours
local missionStepDone      = false -- étape spéciale terminée (remplissage, câbles, etc.)
local savedVehModel        = nil   -- modèle du véhicule en panne (pour persistence)
local missionDistance      = 0     -- distance joueur-mission au moment du lancement
local dutyBlip       = nil   -- Blip du point de service
local bossPed        = nil   -- PNJ chef au dépôt
local showingStats   = false -- Panneau de stats ouvert
local playerStats    = nil   -- Données de stats reçues du serveur
local bossDialogue   = nil   -- Phrase actuelle du chef
local bossDialogueTime = 0   -- Timer dialogue chef

-- Timer
local missionTimer   = false

-- Suivi des dégâts pendant le transport
local initialTruckHealth = 0

-- HUD de service (session)
local dutyStartTime    = 0       -- Timestamp de prise de service
local sessionMissions  = 0       -- Missions réussies cette session
local sessionMoney     = 0       -- Argent gagné cette session
local showServiceHud   = true    -- HUD affiché ou non
local showF6Menu       = false   -- Menu F6 ouvert ou non
local f6MenuIndex      = 1       -- Index de l'option sélectionnée dans le menu F6
local gpsDepotBlip     = nil     -- Blip GPS vers le dépôt
local missionPaused    = false   -- Pause missions (pas de mission auto)

-- Dialogue du PNJ
local pedDialogue     = nil   -- Phrase actuelle du PNJ
local pedDialogueTime = 0     -- Timestamp d'affichage

-- Forward declaration (utilisée dans le CreateThread ci-dessous)
local GetPlayerJob

-- ============================================================
-- DÉTECTION AUTOMATIQUE DU FRAMEWORK
-- ============================================================
CreateThread(function()
    if Config.Framework == 'esx' or (Config.Framework == 'auto' and GetResourceState('es_extended') == 'started') then
        FrameworkType = 'esx'
        Framework = exports['es_extended']:getSharedObject()
    elseif Config.Framework == 'qb' or (Config.Framework == 'auto' and GetResourceState('qb-core') == 'started') then
        FrameworkType = 'qb'
        Framework = exports['qb-core']:GetCoreObject()
    end

    if not Framework then
        print('^1[wz-depanneur] ERREUR : Aucun framework détecté !^0')
        return
    end

    print('^2[wz-depanneur] Framework détecté : ' .. FrameworkType .. '^0')

    -- Attendre que le joueur soit complètement chargé puis vérifier le job
    Wait(5000)
    local jobName = GetPlayerJob()
    if jobName == Config.JobName then
        SpawnBossPed()
        CreateDutyBlip()
    end
end)

--- Spawn le PNJ chef au dépôt
function SpawnBossPed()
    if bossPed and DoesEntityExist(bossPed) then return end

    local bp = Config.BossPed
    local hash = type(bp.model) == 'string' and joaat(bp.model) or bp.model
    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end

    bossPed = CreatePed(4, hash, bp.coords.x, bp.coords.y, bp.coords.z, bp.coords.w, false, true)
    SetEntityAsMissionEntity(bossPed, true, true)
    SetBlockingOfNonTemporaryEvents(bossPed, true)
    SetPedFleeAttributes(bossPed, 0, false)
    FreezeEntityPosition(bossPed, true)
    SetEntityInvincible(bossPed, true)
    SetPedCanBeTargetted(bossPed, false)

    -- Animation idle
    RequestAnimDict(bp.anim.dict)
    local t2 = 0
    while not HasAnimDictLoaded(bp.anim.dict) and t2 < 50 do
        Wait(100)
        t2 = t2 + 1
    end
    TaskPlayAnim(bossPed, bp.anim.dict, bp.anim.name, 8.0, -8.0, -1, 1, 0, false, false, false)

    SetModelAsNoLongerNeeded(hash)
end

--- Supprime le PNJ chef
function DeleteBossPed()
    if bossPed and DoesEntityExist(bossPed) then
        DeleteEntity(bossPed)
    end
    bossPed = nil
end

--- Crée le blip du point de service
function CreateDutyBlip()
    if dutyBlip and DoesBlipExist(dutyBlip) then return end
    if not Config.DutyPoint.blip.enabled then return end

    dutyBlip = AddBlipForCoord(Config.DutyPoint.coords.x, Config.DutyPoint.coords.y, Config.DutyPoint.coords.z)
    SetBlipSprite(dutyBlip, Config.DutyPoint.blip.sprite)
    SetBlipDisplay(dutyBlip, 4)
    SetBlipScale(dutyBlip, Config.DutyPoint.blip.scale)
    SetBlipColour(dutyBlip, Config.DutyPoint.blip.color)
    SetBlipAsShortRange(dutyBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Config.DutyPoint.blip.label)
    EndTextCommandSetBlipName(dutyBlip)
end

--- Supprime le blip du point de service
function RemoveDutyBlip()
    if dutyBlip and DoesBlipExist(dutyBlip) then
        RemoveBlip(dutyBlip)
        dutyBlip = nil
    end
end

-- ============================================================
-- FONCTIONS UTILITAIRES
-- ============================================================

--- Notification compatible ESX / QBCore
local function Notify(msg, type)
    if FrameworkType == 'esx' then
        Framework.ShowNotification(msg)
    elseif FrameworkType == 'qb' then
        TriggerEvent('QBCore:Notify', msg, type or 'primary')
    end
end

--- Retourne le nom du job du joueur
GetPlayerJob = function()
    if FrameworkType == 'esx' then
        local pd = Framework.GetPlayerData()
        return pd.job and pd.job.name or ''
    elseif FrameworkType == 'qb' then
        local pd = Framework.Functions.GetPlayerData()
        return pd.job and pd.job.name or ''
    end
    return ''
end

--- Charge un modèle
local function LoadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 100 do
        Wait(100)
        timeout = timeout + 1
    end
    return hash
end

--- Charge un dictionnaire d'animation
local function LoadAnimDict(dict)
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end
end

--- Affiche un texte 3D
local function DrawText3D(coords, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

--- Dessine une bulle de dialogue moderne au-dessus d'un PNJ
local function DrawSpeechBubble(entity, text)
    if not entity or not DoesEntityExist(entity) then return end
    if not text or text == '' then return end

    local pedPos = GetEntityCoords(entity)
    local camPos = GetGameplayCamCoords()
    local dist   = #(camPos - pedPos)
    if dist > 15.0 then return end

    -- Opacité qui diminue avec la distance
    local alpha = math.floor(math.max(100, 255 - (dist * 12)))

    -- Position au-dessus de la tête
    SetDrawOrigin(pedPos.x, pedPos.y, pedPos.z + 1.2, 0)

    -- Dimensions de la bulle
    local displayText = '~w~' .. text
    local textLen  = string.len(text)
    local bubbleW  = math.max(0.06, textLen * 0.003 + 0.025)
    local bubbleH  = 0.032

    -- Ombre portée
    DrawRect(0.001, 0.002, bubbleW + 0.004, bubbleH + 0.004, 0, 0, 0, math.floor(alpha * 0.3))

    -- Bordure lumineuse subtile
    DrawRect(0.0, 0.0, bubbleW + 0.004, bubbleH + 0.004, 80, 140, 255, math.floor(alpha * 0.25))

    -- Fond principal (dégradé simulé avec 2 couches)
    DrawRect(0.0, 0.0, bubbleW + 0.002, bubbleH + 0.002, 22, 24, 35, alpha)
    DrawRect(0.0, -0.002, bubbleW, bubbleH - 0.004, 28, 30, 45, alpha)

    -- Reflet subtil en haut
    DrawRect(0.0, -(bubbleH / 2) + 0.004, bubbleW - 0.008, 0.005, 255, 255, 255, math.floor(alpha * 0.06))

    -- Flèche vers le bas (3 rects pour simuler un triangle)
    local arrowY = bubbleH / 2
    DrawRect(0.0, arrowY + 0.002, 0.010, 0.004, 22, 24, 35, alpha)
    DrawRect(0.0, arrowY + 0.005, 0.006, 0.004, 22, 24, 35, alpha)
    DrawRect(0.0, arrowY + 0.008, 0.003, 0.003, 22, 24, 35, alpha)

    -- Icône de parole
    SetTextScale(0.24, 0.24)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(100, 180, 255, alpha)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString('~b~>> ~w~' .. text)
    DrawText(0.0, -0.015)

    ClearDrawOrigin()
end

--- Dessine une barre de progression moderne
local function DrawProgressBar(progress, label)
    local centerX = 0.5
    local centerY = 0.90
    local totalW  = 0.18
    local barH    = 0.012
    local pct     = math.floor(progress * 100)

    -- Panneau de fond (style glassmorphism)
    DrawRect(centerX, centerY, totalW + 0.02, 0.065, 15, 15, 20, 200)
    DrawRect(centerX, centerY, totalW + 0.018, 0.063, 25, 25, 35, 180)

    -- Titre de l'action
    SetTextScale(0.30, 0.30)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(200, 200, 210, 255)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(label)
    DrawText(centerX, centerY - 0.027)

    -- Fond de la barre (sombre)
    local barY = centerY + 0.005
    DrawRect(centerX, barY, totalW, barH, 40, 40, 50, 220)

    -- Barre de progression (dégradé bleu-violet)
    local fillW = totalW * progress
    if fillW > 0.001 then
        local r = math.floor(60 + 140 * progress)
        local g = math.floor(120 - 30 * progress)
        local b = math.floor(255 - 40 * progress)
        DrawRect(centerX - (totalW - fillW) / 2, barY, fillW, barH, r, g, b, 240)
        -- Reflet lumineux sur la barre
        DrawRect(centerX - (totalW - fillW) / 2, barY - 0.002, fillW, 0.003, 255, 255, 255, 30)
    end

    -- Pourcentage à droite
    SetTextScale(0.28, 0.28)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(pct .. '%')
    DrawText(centerX, centerY + 0.012)
end

-- ============================================================
-- MENU DE SÉLECTION DU VÉHICULE
-- ============================================================

--- Affiche un menu de sélection et retourne le choix du joueur
local function ShowVehicleSelectionMenu()
    local trucks   = Config.TowTrucks
    local selected = 1
    local choosing = true
    local result   = nil

    while choosing do
        -- Désactiver les contrôles de jeu pendant le menu
        DisableControlAction(0, 24, true)  -- Attack
        DisableControlAction(0, 25, true)  -- Aim

        local menuX = 0.5
        local menuY = 0.38
        local menuW = 0.20
        local itemH = 0.035
        local count = #trucks
        local totalH = (count * itemH) + 0.07

        -- Fond du panneau
        DrawRect(menuX, menuY + totalH / 2 - 0.015, menuW + 0.01, totalH + 0.01, 10, 10, 15, 230)
        DrawRect(menuX, menuY + totalH / 2 - 0.015, menuW + 0.005, totalH + 0.005, 20, 22, 30, 220)

        -- Titre
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(true)
        SetTextColour(100, 180, 255, 255)
        SetTextEntry('STRING')
        SetTextCentre(true)
        AddTextComponentString('CHOISIR UN VEHICULE')
        DrawText(menuX, menuY - 0.01)

        -- Ligne de séparation
        DrawRect(menuX, menuY + 0.025, menuW - 0.02, 0.002, 60, 130, 255, 120)

        -- Liste des véhicules
        for i, truck in ipairs(trucks) do
            local itemY = menuY + 0.035 + (i - 1) * itemH
            local isSelected = (i == selected)

            -- Fond de l'item sélectionné
            if isSelected then
                DrawRect(menuX, itemY + 0.012, menuW - 0.01, itemH - 0.003, 60, 130, 255, 80)
            end

            -- Texte
            SetTextScale(0.30, 0.30)
            SetTextFont(4)
            SetTextProportional(true)
            if isSelected then
                SetTextColour(255, 255, 255, 255)
            else
                SetTextColour(170, 170, 180, 255)
            end
            SetTextEntry('STRING')
            SetTextCentre(true)
            local prefix = isSelected and '> ' or '  '
            AddTextComponentString(prefix .. truck.label)
            DrawText(menuX, itemY)
        end

        -- Instructions en bas
        local instrY = menuY + 0.040 + count * itemH
        SetTextScale(0.22, 0.22)
        SetTextFont(4)
        SetTextProportional(true)
        SetTextColour(120, 120, 130, 255)
        SetTextEntry('STRING')
        SetTextCentre(true)
        AddTextComponentString('Fleches Haut/Bas - Entree pour confirmer')
        DrawText(menuX, instrY)

        -- Navigation
        if IsControlJustPressed(0, 172) then -- Flèche haut
            selected = selected - 1
            if selected < 1 then selected = count end
        end
        if IsControlJustPressed(0, 173) then -- Flèche bas
            selected = selected + 1
            if selected > count then selected = 1 end
        end
        if IsControlJustPressed(0, 191) then -- Entrée
            result = trucks[selected]
            choosing = false
        end
        if IsControlJustPressed(0, 194) then -- Backspace = annuler
            choosing = false
        end

        Wait(0)
    end

    return result
end

-- ============================================================
-- GESTION DU CAMION DÉPANNEUR
-- ============================================================

--- Spawn le camion dépanneur choisi
local function SpawnTowTruck(truckConfig, spawnCoords)
    if towTruck and DoesEntityExist(towTruck) then return end
    if not truckConfig then return end

    selectedTruck = truckConfig
    local sp   = spawnCoords or Config.TowTruckSpawn
    local hash = LoadModel(truckConfig.model)

    towTruck = CreateVehicle(hash, sp.x, sp.y, sp.z, sp.w, true, false)
    SetEntityAsMissionEntity(towTruck, true, true)
    SetVehicleNumberPlateText(towTruck, 'DEPANN')
    SetVehicleColours(towTruck, 70, 70)  -- Jaune
    SetVehicleExtraColours(towTruck, 0, 0)
    SetVehicleDirtLevel(towTruck, 0.0)

    -- Rendre le véhicule utilisable
    SetVehicleDoorsLocked(towTruck, 1)
    SetVehicleEngineOn(towTruck, true, true, false)
    SetVehicleNeedsToBeHotwired(towTruck, false)
    DecorSetBool(towTruck, 'Vehicle.HasKeys', true)

    -- Donner les clés selon le framework
    local plate = GetVehicleNumberPlateText(towTruck)
    if FrameworkType == 'qb' then
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
    end

    SetModelAsNoLongerNeeded(hash)
end

--- Supprime le camion dépanneur
local function DeleteTowTruck()
    if towTruck and DoesEntityExist(towTruck) then
        -- Détacher le véhicule en panne s'il est accroché
        if missionVeh and DoesEntityExist(missionVeh) and IsEntityAttachedToEntity(missionVeh, towTruck) then
            DetachEntity(missionVeh, true, true)
        end
        DeleteEntity(towTruck)
    end
    towTruck = nil
end

--- Vérifie si le joueur est dans son camion dépanneur
local function IsInTowTruck()
    if not towTruck or not DoesEntityExist(towTruck) then return false end
    local playerVeh = GetVehiclePedIsIn(PlayerPedId(), false)
    return playerVeh == towTruck
end

-- ============================================================
-- NETTOYAGE COMPLET DE LA MISSION
-- ============================================================
local function CleanupMission()
    -- Détacher le véhicule si accroché
    if missionVeh and DoesEntityExist(missionVeh) then
        if towTruck and DoesEntityExist(towTruck) and IsEntityAttachedToEntity(missionVeh, towTruck) then
            DetachEntity(missionVeh, true, true)
        end
        DeleteEntity(missionVeh)
    end
    missionVeh = nil

    -- 2e véhicule (accident)
    if missionVeh2 and DoesEntityExist(missionVeh2) then
        DeleteEntity(missionVeh2)
    end
    missionVeh2 = nil

    if missionPed and DoesEntityExist(missionPed) then
        DeleteEntity(missionPed)
    end
    missionPed = nil

    if missionBlip and DoesBlipExist(missionBlip) then
        RemoveBlip(missionBlip)
    end
    missionBlip = nil

    if deliveryBlip and DoesBlipExist(deliveryBlip) then
        RemoveBlip(deliveryBlip)
    end
    deliveryBlip = nil

    isOnMission        = false
    isHooking          = false
    isTransporting     = false
    isDoingAction      = false
    initialTruckHealth = 0
    currentMissionType   = nil
    currentMissionConfig = nil
    missionStepDone      = false
    savedVehModel        = nil
    missionDistance      = 0

    -- Supprimer la mission sauvegardee cote serveur
    TriggerServerEvent('wz-depanneur:server:clearMission')
end

-- ============================================================
-- SYSTÈME DE MISSION
-- ============================================================

-- ============================================================
-- SÉLECTION PONDÉRÉE DU TYPE DE MISSION
-- ============================================================
local function PickMissionType()
    local totalWeight = 0
    for _, mt in ipairs(Config.MissionTypes) do
        totalWeight = totalWeight + mt.weight
    end
    local roll = math.random(1, totalWeight)
    local cumul = 0
    for _, mt in ipairs(Config.MissionTypes) do
        cumul = cumul + mt.weight
        if roll <= cumul then
            return mt
        end
    end
    return Config.MissionTypes[1]
end

-- ============================================================
-- TROUVER UNE POSITION SUR LA ROUTE
-- ============================================================
local function FindRoadPosition()
    local playerCoords = GetEntityCoords(PlayerPedId())

    -- Choisir une tranche de distance via le systeme de poids
    local ranges = Config.MissionDistances
    local totalWeight = 0
    for _, r in ipairs(ranges) do
        totalWeight = totalWeight + r.weight
    end

    local roll = math.random(1, totalWeight)
    local selectedRange = ranges[1]
    local cumul = 0
    for _, r in ipairs(ranges) do
        cumul = cumul + r.weight
        if roll <= cumul then
            selectedRange = r
            break
        end
    end

    -- Tenter de trouver un point valide dans cette tranche
    for attempt = 1, 10 do
        local heading  = math.random(0, 360) * 1.0
        local distance = math.random(selectedRange.min, selectedRange.max) * 1.0
        local targetX  = playerCoords.x + distance * math.cos(math.rad(heading))
        local targetY  = playerCoords.y + distance * math.sin(math.rad(heading))

        local success, nodePos, nodeHeading = GetClosestVehicleNodeWithHeading(targetX, targetY, 0.0, 1, 3.0, 0)
        if success then
            return vector4(nodePos.x, nodePos.y, nodePos.z, nodeHeading)
        end
    end

    -- Fallback : point proche du joueur
    local heading  = math.random(0, 360) * 1.0
    local distance = math.random(500, 1500) * 1.0
    local targetX  = playerCoords.x + distance * math.cos(math.rad(heading))
    local targetY  = playerCoords.y + distance * math.sin(math.rad(heading))
    return vector4(targetX, targetY, playerCoords.z, heading)
end

-- ============================================================
-- SPAWN D'UN PNJ À CÔTÉ DU VÉHICULE
-- ============================================================
local function SpawnMissionPed(veh, vehHeading)
    local pedCoords = GetOffsetFromEntityInWorldCoords(veh, -2.0, 0.0, 0.0)
    local pedHash   = LoadModel(Config.PedModel)

    if not HasModelLoaded(pedHash) then
        print('[wz-depanneur] ERREUR: modele PNJ non charge, re-essai...')
        RequestModel(pedHash)
        Wait(2000)
    end

    -- Spawn legerement au-dessus du vehicule, le moteur physique fera tomber le ped au sol
    local vehPos = GetEntityCoords(veh)

    -- Creer le PNJ avec retry
    for attempt = 1, 3 do
        missionPed = CreatePed(4, pedHash, pedCoords.x, pedCoords.y, vehPos.z + 0.5, vehHeading, false, true)
        if missionPed and missionPed ~= 0 and DoesEntityExist(missionPed) then
            break
        end
        print('[wz-depanneur] PNJ non cree, tentative ' .. attempt .. '/3')
        Wait(1000)
    end

    if not missionPed or missionPed == 0 or not DoesEntityExist(missionPed) then
        print('[wz-depanneur] ERREUR: impossible de creer le PNJ')
        SetModelAsNoLongerNeeded(pedHash)
        return
    end

    SetEntityAsMissionEntity(missionPed, true, true)
    SetBlockingOfNonTemporaryEvents(missionPed, true)
    SetPedFleeAttributes(missionPed, 0, false)
    SetPedCanRagdoll(missionPed, false)

    -- Laisser le moteur physique poser le PNJ au sol naturellement
    Wait(500)

    -- TaskStandStill garde le PNJ immobile MAIS le jeu gere sa position au sol
    -- contrairement a FreezeEntityPosition qui bloque le Z et cause les jambes dans le sol
    TaskStandStill(missionPed, -1)

    LoadAnimDict(Config.PedWaitAnim.dict)
    TaskPlayAnim(missionPed, Config.PedWaitAnim.dict, Config.PedWaitAnim.name, 8.0, -8.0, -1, 1, 0, false, false, false)
    SetModelAsNoLongerNeeded(pedHash)
end

-- ============================================================
-- SPAWN DU VÉHICULE EN PANNE (BASE)
-- ============================================================
local function SpawnBrokenVehicle(coords, forceModel)
    local vehModel = forceModel or Config.BrokenVehicles[math.random(#Config.BrokenVehicles)]
    savedVehModel = vehModel
    local vehHash  = LoadModel(vehModel)

    -- Trouver le Z au sol pour eviter le flottement en pente
    local groundFound, groundZ = false, coords.z
    for zOffset = 10.0, 1.0, -1.0 do
        groundFound, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + zOffset, false)
        if groundFound then break end
    end
    local spawnZ = groundFound and groundZ or coords.z

    local veh = CreateVehicle(vehHash, coords.x, coords.y, spawnZ, coords.w, false, false)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleDirtLevel(veh, 15.0)
    SetVehicleUndriveable(veh, true)
    SetVehicleIndicatorLights(veh, 0, true)
    SetVehicleIndicatorLights(veh, 1, true)
    PlaceObjectOnGroundProperly(veh)
    SetVehicleOnGroundProperly(veh)
    FreezeEntityPosition(veh, true)
    SetModelAsNoLongerNeeded(vehHash)
    return veh
end

-- ============================================================
-- SETUP SPÉCIFIQUE PAR TYPE DE MISSION
-- ============================================================
local function SetupPanne(coords)
    missionVeh = SpawnBrokenVehicle(coords)
    SetVehicleEngineHealth(missionVeh, 0.0)

    -- Effets aléatoires
    if math.random(100) <= 70 then
        SetVehicleDoorOpen(missionVeh, 4, false, false)
    end
    if math.random(100) <= 60 then
        SetVehicleEngineHealth(missionVeh, 0.0)
    end
    if math.random(100) <= 40 then
        SetVehicleTyreBurst(missionVeh, math.random(0, 3), true, 1000.0)
    end

    SpawnMissionPed(missionVeh, coords.w)
    missionStepDone = true -- Pas d'étape spéciale, on peut accrocher directement
end

local function SetupPanneSeche(coords)
    missionVeh = SpawnBrokenVehicle(coords)
    SetVehicleEngineHealth(missionVeh, 0.0)
    SetVehicleFuelLevel(missionVeh, 0.0)

    SpawnMissionPed(missionVeh, coords.w)
    missionStepDone = false -- Doit remplir le réservoir d'abord
end

local function SetupBatterie(coords)
    missionVeh = SpawnBrokenVehicle(coords)
    SetVehicleEngineHealth(missionVeh, 0.0)
    SetVehicleDoorOpen(missionVeh, 4, false, false) -- Capot ouvert

    SpawnMissionPed(missionVeh, coords.w)
    missionStepDone = false -- Doit brancher les câbles d'abord
end

local function SetupPneuCreve(coords)
    missionVeh = SpawnBrokenVehicle(coords)
    -- Forcer un pneu crevé visible (avant ou arrière)
    local tire = math.random(0, 3)
    SetVehicleTyreBurst(missionVeh, tire, true, 1000.0)
    -- Déformer la roue pour que ce soit bien visible
    local boneNames = { [0] = 'wheel_lf', [1] = 'wheel_rf', [2] = 'wheel_lr', [3] = 'wheel_rr' }
    local wheelBone = GetEntityBoneIndexByName(missionVeh, boneNames[tire] or 'wheel_lf')
    if wheelBone ~= -1 then
        local wheelPos = GetWorldPositionOfEntityBone(missionVeh, wheelBone)
        SetVehicleDamage(missionVeh, wheelPos.x, wheelPos.y, wheelPos.z, 200.0, 50.0, true)
    end

    SpawnMissionPed(missionVeh, coords.w)
    missionStepDone = false -- Doit changer le pneu
end

local function SetupAccident(coords)
    -- 1er véhicule (celui qu'on remorque)
    missionVeh = SpawnBrokenVehicle(coords)
    SetVehicleEngineHealth(missionVeh, 0.0)
    SetVehicleDoorOpen(missionVeh, 4, false, false)
    SetVehicleBodyHealth(missionVeh, 200.0)

    -- Déformer le véhicule
    local vehCoords = GetEntityCoords(missionVeh)
    SetVehicleDamage(missionVeh, vehCoords.x + 1.0, vehCoords.y, vehCoords.z, 500.0, 100.0, true)

    -- 2e véhicule (décor, en angle)
    local veh2Model = Config.BrokenVehicles[math.random(#Config.BrokenVehicles)]
    local veh2Hash  = LoadModel(veh2Model)
    local offset    = GetOffsetFromEntityInWorldCoords(missionVeh, 3.0, 4.0, 0.0)
    missionVeh2 = CreateVehicle(veh2Hash, offset.x, offset.y, offset.z, coords.w + 45.0, false, false)
    SetEntityAsMissionEntity(missionVeh2, true, true)
    SetVehicleEngineOn(missionVeh2, false, true, true)
    SetVehicleEngineHealth(missionVeh2, 0.0)
    SetVehicleBodyHealth(missionVeh2, 300.0)
    SetVehicleDirtLevel(missionVeh2, 10.0)
    FreezeEntityPosition(missionVeh2, true)
    SetModelAsNoLongerNeeded(veh2Hash)

    -- Déformer le 2e véhicule
    local v2c = GetEntityCoords(missionVeh2)
    SetVehicleDamage(missionVeh2, v2c.x - 1.0, v2c.y, v2c.z, 400.0, 80.0, true)

    SpawnMissionPed(missionVeh, coords.w)
    missionStepDone = true -- Pas d'étape spéciale, accrocher directement
end

local function SetupFourriere(coords)
    missionVeh = SpawnBrokenVehicle(coords)
    -- Véhicule en bon état mais mal garé
    SetVehicleEngineHealth(missionVeh, 1000.0)
    SetVehicleDirtLevel(missionVeh, 2.0)
    -- Pas de PNJ, pas d'étape spéciale
    missionPed = nil
    missionStepDone = true
end

-- ============================================================
-- LANCER UNE NOUVELLE MISSION
-- ============================================================
local function StartMission()
    if isOnMission then
        Notify(Config.Notifications.alreadyOnMission, 'error')
        return
    end

    -- Sélection pondérée du type
    local mType = PickMissionType()
    currentMissionType   = mType.type
    currentMissionConfig = mType

    -- Trouver une position
    local coords = FindRoadPosition()

    -- Setup selon le type
    if currentMissionType == 'panne' then
        SetupPanne(coords)
    elseif currentMissionType == 'panne_seche' then
        SetupPanneSeche(coords)
    elseif currentMissionType == 'batterie' then
        SetupBatterie(coords)
    elseif currentMissionType == 'pneu_creve' then
        SetupPneuCreve(coords)
    elseif currentMissionType == 'accident' then
        SetupAccident(coords)
    elseif currentMissionType == 'fourriere' then
        SetupFourriere(coords)
    end

    -- Dialogues du PNJ (spécifiques au type ou génériques)
    if missionPed then
        local dialogueKey = Config.PedDialogues[currentMissionType]
        local phrases = dialogueKey or Config.PedDialogues.waiting
        pedDialogue = phrases[math.random(#phrases)]
        pedDialogueTime = GetGameTimer()
    end

    -- Blip mission
    local vehCoords = GetEntityCoords(missionVeh)
    missionBlip = AddBlipForCoord(vehCoords.x, vehCoords.y, vehCoords.z)
    SetBlipSprite(missionBlip, 446)
    SetBlipDisplay(missionBlip, 4)
    SetBlipScale(missionBlip, 1.0)
    SetBlipColour(missionBlip, 1)
    SetBlipRoute(missionBlip, true)
    SetBlipRouteColour(missionBlip, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(mType.blipName or 'Mission')
    EndTextCommandSetBlipName(missionBlip)

    isOnMission = true

    -- Calculer la distance joueur-mission
    local playerPos = GetEntityCoords(PlayerPedId())
    missionDistance = #(playerPos - vector3(vehCoords.x, vehCoords.y, vehCoords.z))

    -- Sauvegarder la mission pour persistence (crash/restart)
    local vehCoordsSave = GetEntityCoords(missionVeh)
    TriggerServerEvent('wz-depanneur:server:saveMission', {
        type       = currentMissionType,
        coordsX    = coords.x,
        coordsY    = coords.y,
        coordsZ    = coords.z,
        coordsW    = coords.w,
        vehModel   = savedVehModel,
        stepDone   = missionStepDone,
        truckModel = selectedTruck and selectedTruck.model or nil,
    })

    -- Notification selon le type
    if currentMissionType == 'fourriere' then
        Notify(Config.Notifications.fourriereStart, 'info')
    elseif currentMissionType == 'accident' then
        Notify(Config.Notifications.accidentStart, 'info')
    else
        Notify(mType.label .. ' signalee ! Rendez-vous sur place.', 'info')
    end
end

-- ============================================================
-- RESTAURATION DE MISSION (APRES CRASH/RESTART)
-- ============================================================
local function RestoreMission(data)
    if isOnMission then return end

    -- Retrouver la config du type de mission
    local mType = nil
    for _, mt in ipairs(Config.MissionTypes) do
        if mt.type == data.type then
            mType = mt
            break
        end
    end
    if not mType then return end

    currentMissionType   = data.type
    currentMissionConfig = mType

    -- Reconstruire les coordonnees
    local coords = vector4(data.coordsX, data.coordsY, data.coordsZ, data.coordsW)

    -- Setup selon le type (avec modele force)
    if currentMissionType == 'panne' then
        missionVeh = SpawnBrokenVehicle(coords, data.vehModel)
        SetVehicleEngineHealth(missionVeh, 0.0)
        SpawnMissionPed(missionVeh, coords.w)
        missionStepDone = true
    elseif currentMissionType == 'panne_seche' then
        missionVeh = SpawnBrokenVehicle(coords, data.vehModel)
        SetVehicleEngineHealth(missionVeh, 0.0)
        SetVehicleFuelLevel(missionVeh, 0.0)
        SpawnMissionPed(missionVeh, coords.w)
        missionStepDone = data.stepDone or false
    elseif currentMissionType == 'batterie' then
        missionVeh = SpawnBrokenVehicle(coords, data.vehModel)
        SetVehicleEngineHealth(missionVeh, 0.0)
        SetVehicleDoorOpen(missionVeh, 4, false, false)
        SpawnMissionPed(missionVeh, coords.w)
        missionStepDone = data.stepDone or false
    elseif currentMissionType == 'pneu_creve' then
        missionVeh = SpawnBrokenVehicle(coords, data.vehModel)
        SetVehicleTyreBurst(missionVeh, 0, true, 1000.0)
        SpawnMissionPed(missionVeh, coords.w)
        missionStepDone = data.stepDone or false
    elseif currentMissionType == 'accident' then
        missionVeh = SpawnBrokenVehicle(coords, data.vehModel)
        SetVehicleEngineHealth(missionVeh, 0.0)
        SetVehicleDoorOpen(missionVeh, 4, false, false)
        SetVehicleBodyHealth(missionVeh, 200.0)
        SpawnMissionPed(missionVeh, coords.w)
        missionStepDone = true
    elseif currentMissionType == 'fourriere' then
        missionVeh = SpawnBrokenVehicle(coords, data.vehModel)
        SetVehicleEngineHealth(missionVeh, 1000.0)
        SetVehicleDirtLevel(missionVeh, 2.0)
        missionPed = nil
        missionStepDone = true
    end

    -- Dialogues du PNJ
    if missionPed then
        local dialogueKey = Config.PedDialogues[currentMissionType]
        local phrases = dialogueKey or Config.PedDialogues.waiting
        pedDialogue = phrases[math.random(#phrases)]
        pedDialogueTime = GetGameTimer()
    end

    -- Blip mission
    local vehCoords = GetEntityCoords(missionVeh)
    missionBlip = AddBlipForCoord(vehCoords.x, vehCoords.y, vehCoords.z)
    SetBlipSprite(missionBlip, 446)
    SetBlipDisplay(missionBlip, 4)
    SetBlipScale(missionBlip, 1.0)
    SetBlipColour(missionBlip, 1)
    SetBlipRoute(missionBlip, true)
    SetBlipRouteColour(missionBlip, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(mType.blipName or 'Mission')
    EndTextCommandSetBlipName(missionBlip)

    isOnMission = true

    Notify('Mission restauree ! Rendez-vous sur place.', 'info')
end


-- ============================================================
-- ACTIONS SPECIALES PAR TYPE DE MISSION
-- ============================================================

--- Progressbar générique avec animation + annulation si le joueur s'éloigne
local function DoProgressAction(targetCoords, duration, label, animDict, animName)
    local playerPed = PlayerPedId()
    isDoingAction = true

    TaskTurnPedToFaceCoord(playerPed, targetCoords.x, targetCoords.y, targetCoords.z, 1000)
    Wait(1000)

    LoadAnimDict(animDict)
    TaskPlayAnim(playerPed, animDict, animName, 8.0, -8.0, -1, 1, 0, false, false, false)

    local startTime = GetGameTimer()
    local cancelled = false

    while (GetGameTimer() - startTime) < duration do
        local progress = (GetGameTimer() - startTime) / duration
        DrawProgressBar(progress, label)

        local playerCoords = GetEntityCoords(playerPed)
        if #(playerCoords - targetCoords) > Config.InteractDistance + 3.0 then
            cancelled = true
            break
        end
        Wait(0)
    end

    ClearPedTasks(playerPed)
    isDoingAction = false
    return not cancelled
end

--- PANNE SÈCHE : remplissage du réservoir
local function DoFillJerrycan()
    if missionStepDone then return end

    local vehCoords = GetEntityCoords(missionVeh)
    Notify(Config.Notifications.fillStart, 'info')

    local success = DoProgressAction(
        vehCoords,
        currentMissionConfig.fillDuration or 6000,
        'Remplissage...',
        'timetable@gardener@filling_can', 'gar_ig_5_filling_can'
    )

    if success then
        missionStepDone = true
        if missionVeh and DoesEntityExist(missionVeh) then
            SetVehicleFuelLevel(missionVeh, 100.0)
        end
        Notify(Config.Notifications.fillDone, 'success')
    else
        Notify(Config.Notifications.actionCancel, 'error')
    end
end

--- BATTERIE : branchement des câbles (3 étapes)
local function DoConnectBattery()
    if missionStepDone then return end

    local vehCoords = GetEntityCoords(missionVeh)

    -- Étape 1 : Branchement
    Notify(Config.Notifications.batteryStart, 'info')
    local s1 = DoProgressAction(
        vehCoords,
        currentMissionConfig.step1Duration or 4000,
        'Branchement des cables...',
        'mini@repair', 'fixing_a_player'
    )
    if not s1 then
        Notify(Config.Notifications.actionCancel, 'error')
        return
    end

    -- Étape 2 : Charge
    Notify(Config.Notifications.batteryCharge, 'info')
    local s2 = DoProgressAction(
        vehCoords,
        currentMissionConfig.step2Duration or 3000,
        'Charge de la batterie...',
        'mini@repair', 'fixing_a_player'
    )
    if not s2 then
        Notify(Config.Notifications.actionCancel, 'error')
        return
    end

    -- Étape 3 : Démarrage
    Notify(Config.Notifications.batteryStartup, 'info')
    local s3 = DoProgressAction(
        vehCoords,
        currentMissionConfig.step3Duration or 2000,
        'Demarrage du moteur...',
        'mini@repair', 'fixing_a_player'
    )
    if not s3 then
        Notify(Config.Notifications.actionCancel, 'error')
        return
    end

    missionStepDone = true
    Notify(Config.Notifications.batteryDone, 'success')
end

--- PNEU CREVÉ : changement de pneu → PNJ repart
local function DoChangeTire()
    if missionStepDone then return end
    if not missionVeh or not DoesEntityExist(missionVeh) then return end

    Notify(Config.Notifications.tireStart, 'info')
    isDoingAction = true

    local playerPed = PlayerPedId()

    -- Trouver le pneu crevé pour positionner le joueur à côté
    local burstTire = 0
    for i = 0, 7 do
        if IsVehicleTyreBurst(missionVeh, i, false) then
            burstTire = i
            break
        end
    end

    -- Offsets selon le pneu crevé (se positionner côté roue)
    local offsets = {
        [0] = vector3(-1.5, 1.0, 0.0),   -- avant-gauche
        [1] = vector3(1.5, 1.0, 0.0),    -- avant-droit
        [2] = vector3(-1.5, -1.0, 0.0),  -- arrière-gauche
        [3] = vector3(1.5, -1.0, 0.0),   -- arrière-droit
    }
    local offset = offsets[burstTire] or vector3(-1.5, 0.0, 0.0)
    local tireWorldPos = GetOffsetFromEntityInWorldCoords(missionVeh, offset.x, offset.y, offset.z)

    -- Déplacer le joueur vers la roue
    TaskGoToCoordAnyMeans(playerPed, tireWorldPos.x, tireWorldPos.y, tireWorldPos.z, 1.0, 0, false, 786603, 0.0)
    Wait(2000)

    -- Se tourner vers le véhicule
    local vehCoords = GetEntityCoords(missionVeh)
    TaskTurnPedToFaceCoord(playerPed, vehCoords.x, vehCoords.y, vehCoords.z, 1000)
    Wait(1000)

    -- Animation accroupie de réparation
    local animDict = 'mini@repair'
    local animName = 'fixing_a_ped'
    LoadAnimDict(animDict)
    TaskPlayAnim(playerPed, animDict, animName, 8.0, -8.0, -1, 49, 0, false, false, false)

    -- Barre de progression
    local duration  = currentMissionConfig.changeDuration or 10000
    local startTime = GetGameTimer()
    local cancelled = false

    while (GetGameTimer() - startTime) < duration do
        local progress = (GetGameTimer() - startTime) / duration
        DrawProgressBar(progress, 'Changement du pneu...')

        -- Annuler si le joueur s'éloigne trop
        local playerCoords = GetEntityCoords(playerPed)
        if #(playerCoords - vehCoords) > Config.InteractDistance + 4.0 then
            cancelled = true
            break
        end
        Wait(0)
    end

    ClearPedTasks(playerPed)
    isDoingAction = false

    if cancelled then
        Notify(Config.Notifications.actionCancel, 'error')
        return
    end

    missionStepDone = true

    -- Réparer les pneus
    if missionVeh and DoesEntityExist(missionVeh) then
        for i = 0, 7 do
            if IsVehicleTyreBurst(missionVeh, i, false) then
                SetVehicleTyreFixed(missionVeh, i)
            end
        end
        FreezeEntityPosition(missionVeh, false)
        SetVehicleUndriveable(missionVeh, false)
        SetVehicleEngineHealth(missionVeh, 1000.0)
        SetVehicleEngineOn(missionVeh, true, true, false)
    end

    -- PNJ remercie et repart en voiture
    if missionPed and DoesEntityExist(missionPed) then
        ClearPedTasks(missionPed)
        FreezeEntityPosition(missionPed, false)
        local thankPhrases = Config.PedDialogues.thanking
        pedDialogue = thankPhrases[math.random(#thankPhrases)]
        pedDialogueTime = GetGameTimer()

        -- Le PNJ monte dans le véhicule et repart
        TaskEnterVehicle(missionPed, missionVeh, 10000, -1, 2.0, 1, 0)

        SetTimeout(5000, function()
            if missionPed and DoesEntityExist(missionPed) then
                TaskVehicleDriveWander(missionPed, missionVeh, 20.0, 786603)
            end

            -- Paiement sans ratio de dégâts (pas de remorquage)
            TriggerServerEvent('wz-depanneur:server:payPlayer', 0.0, missionDistance)
            Notify(Config.Notifications.tireDone, 'success')

            -- Nettoyage après que le PNJ soit parti
            SetTimeout(10000, function()
                if missionBlip and DoesBlipExist(missionBlip) then
                    RemoveBlip(missionBlip)
                    missionBlip = nil
                end
                if missionPed and DoesEntityExist(missionPed) then
                    DeleteEntity(missionPed)
                    missionPed = nil
                end
                if missionVeh and DoesEntityExist(missionVeh) then
                    DeleteEntity(missionVeh)
                    missionVeh = nil
                end
                isOnMission        = false
                isDoingAction      = false
                currentMissionType = nil
                currentMissionConfig = nil
                missionStepDone    = false
            end)
        end)
    end
end

-- ============================================================
-- ACCROCHAGE DU VÉHICULE AU CAMION
-- ============================================================
local function HookVehicle()
    if not isOnMission or isHooking or isTransporting or isDoingAction then return end
    if not isOnDuty then
        Notify(Config.Notifications.notOnDuty, 'error')
        return
    end

    -- Vérifier que l'étape spéciale est faite
    if not missionStepDone then
        return
    end

    -- Vérifier que le camion est proche
    if not towTruck or not DoesEntityExist(towTruck) then
        Notify(Config.Notifications.needTowTruck, 'error')
        return
    end

    local truckCoords = GetEntityCoords(towTruck)
    local vehCoords   = GetEntityCoords(missionVeh)
    if #(truckCoords - vehCoords) > 15.0 then
        Notify(Config.Notifications.needTowTruck, 'error')
        return
    end

    isHooking = true
    Notify(Config.Notifications.hookStart, 'info')

    local playerPed = PlayerPedId()

    -- Se tourner vers le véhicule
    TaskTurnPedToFaceCoord(playerPed, vehCoords.x, vehCoords.y, vehCoords.z, 1000)
    Wait(1000)

    -- Animation d'accrochage
    LoadAnimDict(Config.HookAnim.dict)
    TaskPlayAnim(playerPed, Config.HookAnim.dict, Config.HookAnim.name, 8.0, -8.0, -1, 1, 0, false, false, false)

    -- Barre de progression
    local startTime = GetGameTimer()
    local duration  = Config.HookDuration
    local cancelled = false

    while (GetGameTimer() - startTime) < duration do
        local progress = (GetGameTimer() - startTime) / duration
        DrawProgressBar(progress, 'Accrochage...')

        local playerCoords = GetEntityCoords(playerPed)
        if #(playerCoords - vehCoords) > Config.InteractDistance + 3.0 then
            cancelled = true
            break
        end

        Wait(0)
    end

    ClearPedTasks(playerPed)

    if cancelled then
        Notify(Config.Notifications.hookCancel, 'error')
        isHooking = false
        return
    end

    -- Attacher le véhicule selon la méthode du camion
    FreezeEntityPosition(missionVeh, false)
    SetVehicleUndriveable(missionVeh, false)

    if selectedTruck.attachMethod == 'hook' then
        SetTowTruckCraneHeight(towTruck, 0.0)
        Wait(500)
        AttachVehicleToTowTruck(towTruck, missionVeh, true, 0.0, 0.0, 0.0)
        Wait(300)
        for height = 0.0, 1.0, 0.02 do
            SetTowTruckCraneHeight(towTruck, height)
            Wait(30)
        end
        SetTowTruckCraneHeight(towTruck, 1.0)
    else
        local off = selectedTruck.attachOffset
        local rot = selectedTruck.attachRotation
        AttachEntityToEntity(
            missionVeh, towTruck, 0,
            off.x, off.y, off.z,
            rot.x, rot.y, rot.z,
            true, true, true, false, 20, true
        )
    end

    -- Supprimer le blip de mission
    if missionBlip and DoesBlipExist(missionBlip) then
        RemoveBlip(missionBlip)
        missionBlip = nil
    end

    -- Supprimer le 2e véhicule (accident)
    if missionVeh2 and DoesEntityExist(missionVeh2) then
        SetTimeout(5000, function()
            if missionVeh2 and DoesEntityExist(missionVeh2) then
                DeleteEntity(missionVeh2)
                missionVeh2 = nil
            end
        end)
    end

    -- Le PNJ remercie et disparaît (si présent)
    if missionPed and DoesEntityExist(missionPed) then
        ClearPedTasks(missionPed)
        LoadAnimDict('gestures@m@standing@casual')

        local thankPhrases = Config.PedDialogues.thanking
        pedDialogue = thankPhrases[math.random(#thankPhrases)]
        TaskPlayAnim(missionPed, 'gestures@m@standing@casual', 'gesture_thank_you', 8.0, -8.0, 2000, 0, 0, false, false, false)
        SetTimeout(4000, function()
            if missionPed and DoesEntityExist(missionPed) then
                DeleteEntity(missionPed)
                missionPed = nil
            end
        end)
    end

    -- Enregistrer la santé du camion pour calculer les dégâts
    initialTruckHealth = GetVehicleBodyHealth(towTruck)

    -- Créer le blip de livraison
    local dp = Config.DeliveryPoint
    deliveryBlip = AddBlipForCoord(dp.coords.x, dp.coords.y, dp.coords.z)
    SetBlipSprite(deliveryBlip, dp.blip.sprite)
    SetBlipDisplay(deliveryBlip, 4)
    SetBlipScale(deliveryBlip, dp.blip.scale)
    SetBlipColour(deliveryBlip, dp.blip.color)
    SetBlipRoute(deliveryBlip, true)
    SetBlipRouteColour(deliveryBlip, 2)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(dp.blip.label)
    EndTextCommandSetBlipName(deliveryBlip)

    isHooking      = false
    isTransporting = true

    Notify(Config.Notifications.hookDone, 'success')
end

-- ============================================================
-- LIVRAISON DU VÉHICULE
-- ============================================================
local function DeliverVehicle()
    if not isTransporting then return end

    -- Verifier que le vehicule est bien accroche au camion
    if not missionVeh or not DoesEntityExist(missionVeh) then
        Notify('Le vehicule de mission a disparu !', 'error')
        return
    end
    if not IsEntityAttachedToEntity(missionVeh, towTruck) then
        Notify('Le vehicule n\'est pas accroche a votre camion !', 'error')
        return
    end

    -- Calculer les dégâts subis pendant le transport
    local finalTruckHealth = GetVehicleBodyHealth(towTruck)
    local healthLost = initialTruckHealth - finalTruckHealth
    local damageRatio = 0.0

    if initialTruckHealth > 0 then
        damageRatio = math.max(0.0, math.min(1.0, healthLost / initialTruckHealth))
    end

    -- Détacher le véhicule selon la méthode
    if missionVeh and DoesEntityExist(missionVeh) then
        if selectedTruck and selectedTruck.attachMethod == 'hook' then
            -- Descendre le crochet avant de détacher
            for height = 1.0, 0.0, -0.02 do
                SetTowTruckCraneHeight(towTruck, height)
                Wait(20)
            end
            SetTowTruckCraneHeight(towTruck, 0.0)
            Wait(300)
            DetachVehicleFromTowTruck(towTruck, missionVeh)
        else
            DetachEntity(missionVeh, true, true)
        end

        -- Placer le véhicule au sol proprement
        local deliveryCoords = Config.DeliveryPoint.coords
        SetEntityCoords(missionVeh, deliveryCoords.x + 3.0, deliveryCoords.y, deliveryCoords.z, false, false, false, false)
        PlaceObjectOnGroundProperly(missionVeh)
        FreezeEntityPosition(missionVeh, true)
    end

    -- Supprimer le blip de livraison
    if deliveryBlip and DoesBlipExist(deliveryBlip) then
        RemoveBlip(deliveryBlip)
        deliveryBlip = nil
    end

    -- Envoyer au serveur pour paiement (avec le ratio de dégâts et la distance)
    TriggerServerEvent('wz-depanneur:server:payPlayer', damageRatio, missionDistance)

    -- Notifications de dégâts
    if damageRatio <= 0.01 then
        Notify(Config.Notifications.bonusNoDamage .. Config.BonusNoDamage, 'success')
    elseif damageRatio > 0.05 then
        Notify(Config.Notifications.damagePenalty, 'error')
    end

    Notify(Config.Notifications.deliveryDone, 'success')

    -- Nettoyer après un délai
    Wait(3000)
    if missionVeh and DoesEntityExist(missionVeh) then
        DeleteEntity(missionVeh)
        missionVeh = nil
    end

    isOnMission    = false
    isTransporting = false
    initialTruckHealth = 0
end

-- ============================================================
-- BOUCLE : POINT DE SERVICE (MARKER + INTERACTION)
-- ============================================================
CreateThread(function()
    while true do
        local sleep = 1000
        local playerCoords = GetEntityCoords(PlayerPedId())
        local dist = #(playerCoords - Config.DutyPoint.coords)

        if dist < 50.0 then
            sleep = 0

            local dpCoords = Config.DutyPoint.coords
            local m = Config.DutyPoint.marker

            -- Marqueur au sol (cylindre)
            DrawMarker(
                m.type,
                dpCoords.x, dpCoords.y, dpCoords.z - 1.0,
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                m.scale.x, m.scale.y, m.scale.z,
                m.color.r, m.color.g, m.color.b, m.color.a,
                false, true, 2, false, nil, nil, false
            )

            -- Texte visible de plus loin (adapté à la distance)
            if dist < 15.0 then
                if dist < Config.DutyPoint.radius then
                    local jobName = GetPlayerJob()
                    if jobName == Config.JobName then
                        local label = isOnDuty and '~r~[E]~s~ Fin de service' or '~g~[E]~s~ Prendre le service'
                        DrawText3D(dpCoords + vector3(0, 0, 0.5), label)

                        if IsControlJustPressed(0, 38) then
                            ToggleDuty()
                        end
                    else
                        DrawText3D(dpCoords + vector3(0, 0, 0.5), '~r~Reserve aux depanneurs')
                    end
                end
            else
                -- Texte indicatif visible de loin
                SetDrawOrigin(dpCoords.x, dpCoords.y, dpCoords.z + 2.5, 0)
                SetTextScale(0.40, 0.40)
                SetTextFont(4)
                SetTextProportional(true)
                SetTextColour(100, 180, 255, 200)
                SetTextOutline()
                SetTextEntry('STRING')
                SetTextCentre(true)
                AddTextComponentString('DEPANNEUR')
                DrawText(0.0, 0.0)
                ClearDrawOrigin()
            end
        end

        Wait(sleep)
    end
end)

-- ============================================================
-- BOUCLE : INTERACTION VÉHICULE EN PANNE (touche [E])
-- ============================================================
CreateThread(function()
    while true do
        local sleep = 1000

        -- Afficher l'interaction uniquement si on est en mission et pas en train de transporter
        if isOnMission and not isTransporting and not isHooking and not isDoingAction and missionVeh and DoesEntityExist(missionVeh) then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local vehCoords    = GetEntityCoords(missionVeh)
            local dist = #(playerCoords - vehCoords)

            if dist < 15.0 then
                sleep = 0

                -- Afficher la bulle de dialogue du PNJ
                if pedDialogue and missionPed and DoesEntityExist(missionPed) then
                    DrawSpeechBubble(missionPed, pedDialogue)
                end

                if dist < Config.InteractDistance then
                    -- Vérifier que le joueur est à pied
                    if IsPedInAnyVehicle(PlayerPedId(), false) then
                        DrawText3D(vehCoords + vector3(0, 0, 1.5), '~y~Sortez du vehicule')
                    else
                        -- ============================================================
                        -- AFFICHAGE DU PROMPT SELON LE TYPE DE MISSION
                        -- ============================================================

                        -- PNEU CREVÉ : pas besoin du camion
                        if currentMissionType == 'pneu_creve' and not missionStepDone then
                            DrawText3D(vehCoords + vector3(0, 0, 1.5), '~g~[E]~s~ Changer le pneu')
                            if IsControlJustPressed(0, 38) then
                                DoChangeTire()
                            end

                        -- PANNE SÈCHE : remplir d'abord, puis accrocher
                        elseif currentMissionType == 'panne_seche' and not missionStepDone then
                            DrawText3D(vehCoords + vector3(0, 0, 1.5), '~g~[E]~s~ Remplir le reservoir')
                            if IsControlJustPressed(0, 38) then
                                DoFillJerrycan()
                            end

                        -- BATTERIE : brancher d'abord, puis accrocher
                        elseif currentMissionType == 'batterie' and not missionStepDone then
                            DrawText3D(vehCoords + vector3(0, 0, 1.5), '~g~[E]~s~ Brancher les cables')
                            if IsControlJustPressed(0, 38) then
                                DoConnectBattery()
                            end

                        -- TOUS LES AUTRES (panne, accident, fourriere) + étape faite : ACCROCHER
                        else
                            local truckClose = false
                            if towTruck and DoesEntityExist(towTruck) then
                                local truckDist = #(GetEntityCoords(towTruck) - vehCoords)
                                truckClose = truckDist < 15.0
                            end

                            if truckClose then
                                DrawText3D(vehCoords + vector3(0, 0, 1.5), '~g~[E]~s~ Accrocher le vehicule')
                                if IsControlJustPressed(0, 38) then
                                    HookVehicle()
                                end
                            else
                                DrawText3D(vehCoords + vector3(0, 0, 1.5), '~r~Approchez votre camion')
                            end
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- ============================================================
-- BOUCLE : POINT DE LIVRAISON
-- ============================================================
CreateThread(function()
    while true do
        local sleep = 1000

        if isTransporting and towTruck and DoesEntityExist(towTruck) then
            sleep = 0  -- HUD doit s'afficher chaque frame pendant le transport
            local playerCoords = GetEntityCoords(PlayerPedId())
            local dpCoords     = Config.DeliveryPoint.coords
            local dist = #(playerCoords - dpCoords)

            if dist < 20.0 then
                sleep = 0

                -- Dessiner le marker de livraison
                local m = Config.DeliveryPoint.marker
                DrawMarker(
                    m.type,
                    dpCoords.x, dpCoords.y, dpCoords.z - 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    m.scale.x, m.scale.y, m.scale.z,
                    m.color.r, m.color.g, m.color.b, m.color.a,
                    false, true, 2, false, nil, nil, false
                )

                if dist < Config.DeliveryPoint.radius then
                    if IsInTowTruck() then
                        -- Verifier que le vehicule est toujours accroche
                        if missionVeh and DoesEntityExist(missionVeh) and IsEntityAttachedToEntity(missionVeh, towTruck) then
                            DrawText3D(dpCoords + vector3(0, 0, 1.0), '~g~[E]~s~ Livrer le vehicule')

                            if IsControlJustPressed(0, 38) then
                                DeliverVehicle()
                            end
                        else
                            DrawText3D(dpCoords + vector3(0, 0, 1.0), '~r~Vehicule non accroche !')
                        end
                    else
                        DrawText3D(dpCoords + vector3(0, 0, 1.0), '~y~Amenez votre camion ici')
                    end
                end
            end

            -- Detecter si le vehicule s'est decroche pendant le transport
            if missionVeh and DoesEntityExist(missionVeh) and not IsEntityAttachedToEntity(missionVeh, towTruck) then
                isTransporting = false
                isHooking      = false
                Notify('Le vehicule s\'est decroche ! Retournez l\'accrocher.', 'error')
            end

            -- ============================================================
            -- INDICATEUR D'ÉTAT DU VÉHICULE (HUD MODERNE)
            -- ============================================================
            if initialTruckHealth > 0 then
                local currentHealth = GetVehicleBodyHealth(towTruck)
                local healthPercent = math.max(0, math.min(100, (currentHealth / initialTruckHealth) * 100))
                local healthRatio   = healthPercent / 100

                -- Position du panneau
                local panelX = 0.92
                local panelY = 0.14
                local panelW = 0.14
                local panelH = 0.075

                -- Panneau de fond (glassmorphism)
                DrawRect(panelX, panelY, panelW, panelH, 15, 15, 20, 200)
                DrawRect(panelX, panelY, panelW - 0.002, panelH - 0.002, 25, 25, 35, 180)

                -- Titre "ETAT DU CHARGEMENT"
                SetTextScale(0.22, 0.22)
                SetTextFont(4)
                SetTextProportional(true)
                SetTextColour(150, 160, 180, 255)
                SetTextEntry('STRING')
                SetTextCentre(true)
                AddTextComponentString('ETAT DU CHARGEMENT')
                DrawText(panelX, panelY - 0.030)

                -- Couleur dynamique (vert -> orange -> rouge)
                local r, g, b
                if healthPercent >= 70 then
                    -- Vert vers orange
                    local t = (healthPercent - 70) / 30
                    r = math.floor(80 + (255 - 80) * (1 - t))
                    g = math.floor(220 * t + 180 * (1 - t))
                    b = math.floor(120 * t)
                elseif healthPercent >= 40 then
                    -- Orange vers rouge
                    local t = (healthPercent - 40) / 30
                    r = 255
                    g = math.floor(180 * t + 60 * (1 - t))
                    b = math.floor(30 * t)
                else
                    -- Rouge
                    r, g, b = 255, 60, 40
                end

                -- Pourcentage en gros
                SetTextScale(0.42, 0.42)
                SetTextFont(4)
                SetTextProportional(true)
                SetTextColour(r, g, b, 255)
                SetTextEntry('STRING')
                SetTextCentre(true)
                AddTextComponentString(math.floor(healthPercent) .. '%')
                DrawText(panelX, panelY - 0.015)

                -- Barre de vie
                local barY = panelY + 0.020
                local barW = panelW - 0.025
                local barH = 0.010

                -- Fond de la barre
                DrawRect(panelX, barY, barW, barH, 40, 40, 50, 220)

                -- Remplissage
                local fillW = barW * healthRatio
                if fillW > 0.001 then
                    DrawRect(panelX - (barW - fillW) / 2, barY, fillW, barH, r, g, b, 230)
                    -- Reflet
                    DrawRect(panelX - (barW - fillW) / 2, barY - 0.002, fillW, 0.003, 255, 255, 255, 25)
                end
            end
        end

        Wait(sleep)
    end
end)

-- ============================================================
-- GESTION DE LA TENUE
-- ============================================================
local savedClothes = nil  -- Sauvegarde de la tenue civile

--- Sauvegarde tous les composants de la tenue actuelle
local function SaveCivilianClothes()
    local ped = PlayerPedId()
    savedClothes = {}
    for i = 0, 11 do
        savedClothes[i] = {
            drawable = GetPedDrawableVariation(ped, i),
            texture  = GetPedTextureVariation(ped, i),
            palette  = GetPedPaletteVariation(ped, i),
        }
    end
end

--- Applique la tenue de service
local function ApplyUniform()
    local ped = PlayerPedId()
    local model = GetEntityModel(ped)
    local isMale = (model == joaat('mp_m_freemode_01'))
    local uniform = isMale and Config.Uniform.male or Config.Uniform.female

    for _, comp in ipairs(uniform) do
        SetPedComponentVariation(ped, comp[1], comp[2], comp[3], comp[4])
    end
end

--- Restaure la tenue civile sauvegardée
local function RestoreCivilianClothes()
    if not savedClothes then return end
    local ped = PlayerPedId()
    for i = 0, 11 do
        if savedClothes[i] then
            SetPedComponentVariation(ped, i, savedClothes[i].drawable, savedClothes[i].texture, savedClothes[i].palette)
        end
    end
    savedClothes = nil
end

-- ============================================================
-- PRISE / FIN DE SERVICE
-- ============================================================
function ToggleDuty()
    local jobName = GetPlayerJob()
    if jobName ~= Config.JobName then
        Notify(Config.Notifications.wrongJob, 'error')
        return
    end

    isOnDuty = not isOnDuty

    if isOnDuty then
        -- Afficher le menu de sélection du véhicule
        local choice = ShowVehicleSelectionMenu()
        if not choice then
            -- Le joueur a annulé
            isOnDuty = false
            return
        end

        SaveCivilianClothes()
        ApplyUniform()
        Notify(Config.Notifications.onDuty, 'success')
        TriggerServerEvent('wz-depanneur:server:setDuty', true)
        SpawnTowTruck(choice)
        StartMissionTimer()
        Notify('Vous recevrez une mission prochainement, restez en attente.', 'info')

        -- Reset session stats
        dutyStartTime   = GetGameTimer()
        sessionMissions = 0
        sessionMoney    = 0
        showServiceHud  = true
    else
        RestoreCivilianClothes()
        Notify(Config.Notifications.offDuty, 'error')
        TriggerServerEvent('wz-depanneur:server:setDuty', false)
        StopMissionTimer()
        CleanupMission()
        DeleteTowTruck()

        -- Reset session
        dutyStartTime   = 0
        sessionMissions = 0
        sessionMoney    = 0
        showF6Menu      = false
        missionPaused   = false
        if gpsDepotBlip then
            RemoveBlip(gpsDepotBlip)
            gpsDepotBlip = nil
        end
    end
end

-- ============================================================
-- RESTAURATION AUTO (CRASH/RESTART)
-- ============================================================
RegisterNetEvent('wz-depanneur:client:restoreMission')
AddEventHandler('wz-depanneur:client:restoreMission', function(data)
    -- Auto-restaurer le service si pas en duty
    if not isOnDuty then
        -- Attendre que le framework charge le job du joueur (max 30s)
        local attempts = 0
        while GetPlayerJob() ~= Config.JobName and attempts < 60 do
            Wait(500)
            attempts = attempts + 1
        end

        local jobName = GetPlayerJob()
        if jobName ~= Config.JobName then return end

        -- Retrouver la config du camion sauvegarde
        local truckConfig = nil
        if data.truckModel then
            for _, tc in ipairs(Config.TowTrucks) do
                if tc.model == data.truckModel then
                    truckConfig = tc
                    break
                end
            end
        end
        -- Fallback sur le premier camion si pas trouve
        if not truckConfig then
            truckConfig = Config.TowTrucks[1]
        end

        isOnDuty = true
        SaveCivilianClothes()
        ApplyUniform()
        TriggerServerEvent('wz-depanneur:server:setDuty', true)

        -- Spawn le camion pres du joueur (pas au depot)
        local pCoords = GetEntityCoords(PlayerPedId())
        local found, nodePos, nodeHeading = GetClosestVehicleNodeWithHeading(pCoords.x, pCoords.y, pCoords.z, 1, 3.0, 0)
        local truckSpawn
        if found then
            truckSpawn = vector4(nodePos.x, nodePos.y, nodePos.z, nodeHeading)
        else
            truckSpawn = vector4(pCoords.x + 3.0, pCoords.y, pCoords.z, 0.0)
        end
        SpawnTowTruck(truckConfig, truckSpawn)

        StartMissionTimer()
        dutyStartTime   = GetGameTimer()
        sessionMissions = 0
        sessionMoney    = 0
        Notify('Service restaure automatiquement.', 'success')

        -- Attendre que le camion soit bien charge
        Wait(3000)
    end

    RestoreMission(data)
end)

-- Auto-verification au spawn du joueur (apres crash/restart)
AddEventHandler('playerSpawned', function()
    Wait(5000) -- Attendre que tout soit charge
    TriggerServerEvent('wz-depanneur:server:checkSavedMission')
end)

-- ============================================================
-- TIMER DE MISSION
-- ============================================================
function StartMissionTimer()
    StopMissionTimer()
    missionTimer = true

    CreateThread(function()
        while missionTimer and isOnDuty do
            Wait(Config.MissionCooldown)
            if missionTimer and isOnDuty and not isOnMission and not missionPaused then
                StartMission()
            end
        end
    end)
end

function StopMissionTimer()
    missionTimer = false
end

-- ============================================================
-- SYNCHRONISATION MULTI-JOUEURS
-- ============================================================

--- Le serveur refuse le service (trop de dépanneurs)
RegisterNetEvent('wz-depanneur:client:dutyRefused')
AddEventHandler('wz-depanneur:client:dutyRefused', function(currentCount)
    isOnDuty = false
    RestoreCivilianClothes()
    Notify('Service complet ! ' .. currentCount .. ' depanneur(s) deja en service.', 'error')
end)

--- Le serveur confirme et envoie le nombre de dépanneurs actifs
RegisterNetEvent('wz-depanneur:client:dutySync')
AddEventHandler('wz-depanneur:client:dutySync', function(activeCount)
    if isOnDuty and activeCount > 1 then
        Notify(activeCount .. ' depanneur(s) en service actuellement.', 'info')
    end
end)

-- ============================================================
-- NETTOYAGE
-- ============================================================
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    CleanupMission()
    DeleteTowTruck()
    DeleteBossPed()
    if dutyBlip and DoesBlipExist(dutyBlip) then
        RemoveBlip(dutyBlip)
    end
end)

-- Changement de job (ESX)
RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job)
    if job.name == Config.JobName then
        CreateDutyBlip()
        SpawnBossPed()
    else
        RemoveDutyBlip()
        DeleteBossPed()
        if isOnDuty then
            isOnDuty = false
            RestoreCivilianClothes()
            StopMissionTimer()
            CleanupMission()
            DeleteTowTruck()
        end
    end
end)

-- Changement de job (QBCore)
RegisterNetEvent('QBCore:Client:OnJobUpdate')
AddEventHandler('QBCore:Client:OnJobUpdate', function(job)
    if job.name == Config.JobName then
        CreateDutyBlip()
        SpawnBossPed()
    else
        RemoveDutyBlip()
        DeleteBossPed()
        if isOnDuty then
            isOnDuty = false
            RestoreCivilianClothes()
            StopMissionTimer()
            CleanupMission()
            DeleteTowTruck()
        end
    end
end)

-- ============================================================
-- PNJ CHEF : PANNEAU DE STATISTIQUES
-- ============================================================

--- Dessine le panneau de statistiques (style glassmorphism)
local function DrawStatsPanel(stats)
    if not stats then return end

    -- Désactiver les contrôles de jeu
    DisableControlAction(0, 1, true)   -- Look LR
    DisableControlAction(0, 2, true)   -- Look UD
    DisableControlAction(0, 24, true)  -- Attack
    DisableControlAction(0, 25, true)  -- Aim
    DisableControlAction(0, 37, true)  -- Select weapon

    local cx = 0.5
    local cy = 0.40
    local pw = 0.26
    local ph = 0.34

    -- Ombre portée
    DrawRect(cx + 0.003, cy + 0.003, pw + 0.006, ph + 0.006, 0, 0, 0, 100)

    -- Fond principal (glassmorphism sombre)
    DrawRect(cx, cy, pw, ph, 15, 17, 25, 230)
    DrawRect(cx, cy, pw - 0.003, ph - 0.003, 22, 25, 38, 215)

    -- Bordure lumineuse en haut
    DrawRect(cx, cy - ph / 2 + 0.002, pw - 0.01, 0.003, 60, 140, 255, 150)

    -- ========== TITRE ==========
    local titleY = cy - ph / 2 + 0.020
    SetTextScale(0.50, 0.50)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(80, 170, 255, 255)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString('TABLEAU DE BORD')
    DrawText(cx, titleY)

    -- Ligne de séparation sous le titre
    DrawRect(cx, titleY + 0.038, pw - 0.04, 0.002, 60, 130, 255, 100)

    -- ========== STATISTIQUES ==========
    local startY = titleY + 0.055
    local lineH  = 0.045

    local lines = {
        { label = 'Missions completees',      value = tostring(stats.totalMissions),  icon = '~b~>>' },
        { label = 'Argent gagne',              value = '$' .. tostring(stats.totalMoney), icon = '~g~$'  },
        { label = 'Serie sans degats',         value = tostring(stats.currentStreak),  icon = '~y~*'  },
        { label = 'Meilleur record',           value = tostring(stats.bestStreak),     icon = '~o~#'  },
    }

    for i, line in ipairs(lines) do
        local ly = startY + (i - 1) * lineH

        -- Fond alterné subtil
        if i % 2 == 0 then
            DrawRect(cx, ly + 0.012, pw - 0.02, lineH - 0.005, 255, 255, 255, 8)
        end

        -- Icône + Label (aligné à gauche)
        SetTextScale(0.38, 0.38)
        SetTextFont(4)
        SetTextProportional(true)
        SetTextColour(180, 185, 200, 255)
        SetTextEntry('STRING')
        AddTextComponentString(line.icon .. ' ~w~' .. line.label)
        DrawText(cx - pw / 2 + 0.018, ly)

        -- Valeur (alignée à droite)
        SetTextScale(0.40, 0.40)
        SetTextFont(4)
        SetTextProportional(true)
        SetTextColour(255, 255, 255, 255)
        SetTextEntry('STRING')
        SetTextRightJustify(true)
        SetTextWrap(0.0, cx + pw / 2 - 0.018)
        AddTextComponentString(line.value)
        DrawText(0.0, ly)
    end

    -- ========== INSTRUCTION DE FERMETURE ==========
    local bottomY = cy + ph / 2 - 0.028
    SetTextScale(0.30, 0.30)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(100, 105, 120, 255)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString('Appuyez sur ~r~BACKSPACE~s~ pour fermer')
    DrawText(cx, bottomY)
end

-- Boucle d'interaction avec le PNJ chef
CreateThread(function()
    while true do
        local sleep = 1000

        -- Panneau de stats ouvert : priorité absolue
        if showingStats and playerStats then
            sleep = 0
            DrawStatsPanel(playerStats)

            if IsControlJustPressed(0, 194) then -- Backspace
                showingStats = false
                playerStats  = nil
            end
        elseif bossPed and DoesEntityExist(bossPed) then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local bossCoords   = GetEntityCoords(bossPed)
            local dist = #(playerCoords - bossCoords)

            if dist < 15.0 then
                sleep = 0

                -- Dialogue aléatoire du chef (change toutes les 8 secondes)
                if not bossDialogue or (GetGameTimer() - bossDialogueTime) > 8000 then
                    local phrases = Config.BossPed.dialogues
                    bossDialogue = phrases[math.random(#phrases)]
                    bossDialogueTime = GetGameTimer()
                end

                DrawSpeechBubble(bossPed, bossDialogue)

                if dist < Config.BossPed.radius then
                    DrawText3D(bossCoords + vector3(0, 0, 1.1), '~g~[E]~s~ Voir les statistiques')

                    if IsControlJustPressed(0, 38) then
                        TriggerServerEvent('wz-depanneur:server:requestStats')
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- Réception des stats depuis le serveur
RegisterNetEvent('wz-depanneur:client:receiveStats')
AddEventHandler('wz-depanneur:client:receiveStats', function(stats)
    playerStats  = stats
    showingStats = true
end)

-- Réception du paiement (pour le HUD session)
RegisterNetEvent('wz-depanneur:client:missionPaid')
AddEventHandler('wz-depanneur:client:missionPaid', function(amount)
    sessionMissions = sessionMissions + 1
    sessionMoney    = sessionMoney + amount
    Notify('Mission terminee ! Vous avez gagne ~g~$' .. amount, 'success')
end)

-- ============================================================
-- HUD DE SERVICE (affiché en haut à gauche quand en service)
-- ============================================================

--- Formate un temps en millisecondes en HH:MM:SS
local function FormatTime(ms)
    local totalSec = math.floor(ms / 1000)
    local h = math.floor(totalSec / 3600)
    local m = math.floor((totalSec % 3600) / 60)
    local s = totalSec % 60
    return string.format('%02d:%02d:%02d', h, m, s)
end

--- Dessine le HUD de service
local function DrawServiceHud()
    local cx = 0.105
    local cy = 0.27
    local pw = 0.185
    local ph = 0.155

    -- Ombre
    DrawRect(cx + 0.002, cy + 0.002, pw + 0.004, ph + 0.004, 0, 0, 0, 80)

    -- Fond glassmorphism
    DrawRect(cx, cy, pw, ph, 15, 17, 25, 210)
    DrawRect(cx, cy, pw - 0.002, ph - 0.002, 22, 25, 38, 195)

    -- Bordure lumineuse en haut
    DrawRect(cx, cy - ph / 2 + 0.001, pw - 0.008, 0.002, 60, 140, 255, 130)

    -- Titre
    local titleY = cy - ph / 2 + 0.010
    SetTextScale(0.38, 0.38)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(80, 170, 255, 255)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString('EN SERVICE')
    DrawText(cx, titleY)

    -- Séparateur
    DrawRect(cx, titleY + 0.030, pw - 0.03, 0.001, 60, 130, 255, 80)

    -- Données
    local startY = titleY + 0.038
    local lineH  = 0.030

    local elapsed = dutyStartTime > 0 and (GetGameTimer() - dutyStartTime) or 0

    local data = {
        { label = 'Temps',     value = FormatTime(elapsed) },
        { label = 'Missions',  value = tostring(sessionMissions) },
        { label = 'Gains',     value = '$' .. tostring(sessionMoney) },
    }

    for i, d in ipairs(data) do
        local ly = startY + (i - 1) * lineH

        -- Label
        SetTextScale(0.32, 0.32)
        SetTextFont(4)
        SetTextProportional(true)
        SetTextColour(150, 155, 170, 255)
        SetTextEntry('STRING')
        AddTextComponentString(d.label)
        DrawText(cx - pw / 2 + 0.012, ly)

        -- Valeur
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(true)
        SetTextColour(255, 255, 255, 255)
        SetTextEntry('STRING')
        SetTextRightJustify(true)
        SetTextWrap(0.0, cx + pw / 2 - 0.012)
        AddTextComponentString(d.value)
        DrawText(0.0, ly)
    end

    -- Petit message F6
    local hintY = cy + ph / 2 - 0.012
    SetTextScale(0.30, 0.30)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(100, 105, 120, 255)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString('~w~F6~s~ pour masquer')
    DrawText(cx, hintY)
end

-- ============================================================
-- MENU F6 (toggle HUD)
-- ============================================================

local function DrawF6Menu()
    -- Construction dynamique des options
    local items = {
        {
            label = (showServiceHud and '~g~[X]' or '~r~[ ]') .. '~w~  Afficher le HUD',
            desc  = 'Affiche ou masque le panneau de service en haut a gauche.',
            action = function() showServiceHud = not showServiceHud end,
            color = {200, 205, 215},
        },
        {
            label = (gpsDepotBlip and '~g~[X]' or '~r~[ ]') .. '~w~  GPS Depot',
            desc  = 'Active le GPS avec un itineraire vers le depot de livraison.',
            action = function()
                if gpsDepotBlip then
                    RemoveBlip(gpsDepotBlip)
                    gpsDepotBlip = nil
                else
                    local dp = Config.DeliveryPoint.coords
                    gpsDepotBlip = AddBlipForCoord(dp.x, dp.y, dp.z)
                    SetBlipSprite(gpsDepotBlip, 477)
                    SetBlipDisplay(gpsDepotBlip, 4)
                    SetBlipScale(gpsDepotBlip, 0.9)
                    SetBlipColour(gpsDepotBlip, 3)
                    SetBlipRoute(gpsDepotBlip, true)
                    SetBlipRouteColour(gpsDepotBlip, 3)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentSubstringPlayerName('Depot depanneur')
                    EndTextCommandSetBlipName(gpsDepotBlip)
                end
            end,
            color = {200, 205, 215},
        },
        {
            label = '~b~>>~w~  Voir les statistiques',
            desc  = 'Ouvre le tableau de bord avec vos stats globales.',
            action = function()
                TriggerServerEvent('wz-depanneur:server:requestStats')
                showF6Menu = false
            end,
            color = {200, 205, 215},
        },
        {
            label = (missionPaused and '~o~[P]' or '~g~[>]') .. '~w~  ' .. (missionPaused and 'En pause' or 'Missions actives'),
            desc  = 'Met en pause la reception de nouvelles missions.',
            action = function() missionPaused = not missionPaused end,
            color = {200, 205, 215},
        },
    }

    if isOnMission then
        items[#items + 1] = {
            label = '~r~>>~w~  Abandonner la mission',
            desc  = 'Annule la mission en cours sans recompense.',
            action = function()
                CleanupMission()
                Notify(Config.Notifications.missionCancel or 'Mission abandonnee.', 'error')
                showF6Menu = false
            end,
            color = {255, 80, 80},
        }
    end

    local itemCount = #items

    -- Clamp l'index
    if f6MenuIndex < 1 then f6MenuIndex = 1 end
    if f6MenuIndex > itemCount then f6MenuIndex = itemCount end

    -- Dimensions
    local cx = 0.5
    local cy = 0.42
    local pw = 0.26
    local rowH = 0.038
    local headerH = 0.055
    local descH = 0.040
    local footerH = 0.035
    local ph = headerH + (itemCount * rowH) + descH + footerH + 0.015

    -- Désactiver les contrôles (garder la caméra libre)
    DisableControlAction(0, 24, true)
    DisableControlAction(0, 25, true)
    DisableControlAction(0, 172, true) -- Arrow Up
    DisableControlAction(0, 173, true) -- Arrow Down

    -- Ombre
    DrawRect(cx + 0.002, cy + 0.002, pw + 0.004, ph + 0.004, 0, 0, 0, 90)

    -- Fond
    DrawRect(cx, cy, pw, ph, 15, 17, 25, 225)
    DrawRect(cx, cy, pw - 0.002, ph - 0.002, 22, 25, 38, 210)

    -- Bordure haut
    DrawRect(cx, cy - ph / 2 + 0.001, pw - 0.008, 0.002, 60, 140, 255, 130)

    -- Titre
    local titleY = cy - ph / 2 + 0.012
    SetTextScale(0.42, 0.42)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(80, 170, 255, 255)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString('OPTIONS DEPANNEUR')
    DrawText(cx, titleY)

    -- Séparateur
    DrawRect(cx, titleY + 0.033, pw - 0.03, 0.001, 60, 130, 255, 80)

    -- ========== ITEMS ==========
    local startY = titleY + 0.042

    for i, item in ipairs(items) do
        local iy = startY + (i - 1) * rowH
        local rowCenter = iy + 0.012

        -- Highlight de la ligne sélectionnée
        if i == f6MenuIndex then
            DrawRect(cx, rowCenter, pw - 0.015, rowH - 0.004, 50, 120, 255, 50)
            -- Petit indicateur à gauche
            DrawRect(cx - pw / 2 + 0.010, rowCenter, 0.004, rowH - 0.010, 80, 170, 255, 200)
        end

        -- Texte
        local c = item.color
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(true)
        SetTextColour(c[1], c[2], c[3], 255)
        SetTextEntry('STRING')
        AddTextComponentString(item.label)
        DrawText(cx - pw / 2 + 0.022, iy)
    end

    -- ========== DESCRIPTION ==========
    local descY = startY + (itemCount * rowH) + 0.005
    DrawRect(cx, descY + 0.012, pw - 0.03, 0.001, 60, 130, 255, 40)
    local selectedItem = items[f6MenuIndex]
    if selectedItem and selectedItem.desc then
        DrawRect(cx, descY + 0.025, pw - 0.025, 0.028, 40, 50, 70, 60)
        SetTextScale(0.30, 0.30)
        SetTextFont(4)
        SetTextProportional(true)
        SetTextColour(140, 160, 200, 255)
        SetTextEntry('STRING')
        SetTextCentre(true)
        AddTextComponentString(selectedItem.desc)
        DrawText(cx, descY + 0.016)
    end

    -- ========== INSTRUCTIONS ==========
    local bottomY = cy + ph / 2 - 0.028
    DrawRect(cx, bottomY + 0.008, pw - 0.02, 0.001, 60, 130, 255, 40)
    SetTextScale(0.26, 0.26)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(100, 105, 120, 255)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString('~w~[^] [v]~s~ Naviguer  |  ~w~[ENTREE]~s~ Valider  |  ~r~F6~s~ Fermer')
    DrawText(cx, bottomY + 0.012)

    -- ========== INPUTS ==========
    -- Flèche haut
    if IsDisabledControlJustPressed(0, 172) then
        f6MenuIndex = f6MenuIndex - 1
        if f6MenuIndex < 1 then f6MenuIndex = itemCount end
    end

    -- Flèche bas
    if IsDisabledControlJustPressed(0, 173) then
        f6MenuIndex = f6MenuIndex + 1
        if f6MenuIndex > itemCount then f6MenuIndex = 1 end
    end

    -- Entrée : activer l'option sélectionnée
    if IsControlJustPressed(0, 191) then
        local selected = items[f6MenuIndex]
        if selected and selected.action then
            selected.action()
        end
    end

    -- Fermer avec F6 ou Backspace
    if IsControlJustPressed(0, 194) then
        showF6Menu = false
    end
end

-- ============================================================
-- BOUCLE : HUD DE SERVICE + MENU F6
-- ============================================================
CreateThread(function()
    while true do
        local sleep = 500

        if isOnDuty then
            sleep = 0

            -- Dessiner le HUD de service
            if showServiceHud then
                DrawServiceHud()
            end

            -- Dessiner le menu F6
            if showF6Menu then
                DrawF6Menu()
            end

            -- Touche F6 pour ouvrir/fermer le menu
            if IsControlJustPressed(0, 167) then -- F6
                showF6Menu = not showF6Menu
                if showF6Menu then f6MenuIndex = 1 end
            end
        end

        Wait(sleep)
    end
end)
