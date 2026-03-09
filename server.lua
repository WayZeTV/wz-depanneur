-- ============================================================
-- wz-depanneur | server.lua v2.0
-- Paiement sécurisé avec système de dégâts, anti-spam, logs
-- ============================================================

-- ============================================================
-- VARIABLES LOCALES
-- ============================================================
local Framework     = nil
local FrameworkType = nil

local playersOnDuty = {}  -- { [source] = true }
local lastReward    = {}  -- { [source] = timestamp }

-- ============================================================
-- STATISTIQUES (JSON PERSISTANT)
-- ============================================================
local statsFile = 'data/stats.json'
local allStats  = {}  -- { [identifier] = { totalMissions, totalMoney, currentStreak, bestStreak } }

--- Charge les stats depuis le fichier JSON
local function LoadStats()
    local raw = LoadResourceFile(GetCurrentResourceName(), statsFile)
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            allStats = data
            print('^2[wz-depanneur] Stats chargees (' .. #raw .. ' octets)^0')
        else
            print('^3[wz-depanneur] Fichier stats corrompu, reinitialisation.^0')
            allStats = {}
        end
    else
        allStats = {}
        print('^3[wz-depanneur] Aucun fichier de stats trouve, creation au premier paiement.^0')
    end
end

--- Sauvegarde les stats dans le fichier JSON
local function SaveStats()
    local raw = json.encode(allStats)
    SaveResourceFile(GetCurrentResourceName(), statsFile, raw, -1)
end

-- ============================================================
-- MISSIONS PERSISTANTES (JSON)
-- ============================================================
local missionsFile = 'data/missions.json'
local savedMissions = {}  -- { [identifier] = { type, coords, vehModel, stepDone } }

local function LoadMissions()
    local raw = LoadResourceFile(GetCurrentResourceName(), missionsFile)
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            savedMissions = data
            print('^2[wz-depanneur] Missions sauvegardees chargees (' .. #raw .. ' octets)^0')
        else
            savedMissions = {}
        end
    else
        savedMissions = {}
    end
end

local function SaveMissionsFile()
    local raw = json.encode(savedMissions)
    SaveResourceFile(GetCurrentResourceName(), missionsFile, raw, -1)
end

--- Récupère l'identifiant principal d'un joueur
local function GetPlayerLicense(src)
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and id:find('license:') then
            return id
        end
    end
    -- Fallback sur steam ou autre
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id then return id end
    end
    return 'unknown'
end

--- Récupère ou crée les stats d'un joueur
local function GetPlayerStats(identifier)
    if not allStats[identifier] then
        allStats[identifier] = {
            totalMissions  = 0,
            totalMoney     = 0,
            currentStreak  = 0,
            bestStreak     = 0,
        }
    end
    return allStats[identifier]
end

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
        print('^1[wz-depanneur] ERREUR : Aucun framework detecte cote serveur !^0')
        return
    end

    print('^2[wz-depanneur] Serveur initialise avec : ' .. FrameworkType .. '^0')

    -- Charger les stats persistantes
    LoadStats()
    LoadMissions()
end)

-- ============================================================
-- FONCTIONS UTILITAIRES
-- ============================================================

--- Récupère les identifiants d'un joueur
local function GetPlayerIdentifiers(src)
    local ids = {}
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id then
            local prefix = id:match('^([^:]+):')
            if prefix then ids[prefix] = id end
        end
    end
    ids.name = GetPlayerName(src) or 'Inconnu'
    return ids
end

--- Récupère le nom du job côté serveur
local function GetPlayerJob(src)
    if FrameworkType == 'esx' then
        local xPlayer = Framework.GetPlayerFromId(src)
        return xPlayer and xPlayer.getJob().name or ''
    elseif FrameworkType == 'qb' then
        local player = Framework.Functions.GetPlayer(src)
        return player and player.PlayerData.job.name or ''
    end
    return ''
end


-- ============================================================
-- ÉVÉNEMENTS
-- ============================================================

--- Compte le nombre de dépanneurs en service
local function GetActiveDutyCount()
    local count = 0
    for _ in pairs(playersOnDuty) do
        count = count + 1
    end
    return count
end

--- Mise à jour du statut de service
RegisterNetEvent('wz-depanneur:server:setDuty')
AddEventHandler('wz-depanneur:server:setDuty', function(status)
    local src = source

    -- Vérif job serveur
    if GetPlayerJob(src) ~= Config.JobName then
        print('^1[wz-depanneur] Tentative duty non autorisee : ' .. GetPlayerName(src) .. '^0')
        return
    end

    -- Vérifier le nombre max de dépanneurs
    if status and Config.MaxDepanneurs > 0 then
        local currentCount = GetActiveDutyCount()
        if currentCount >= Config.MaxDepanneurs then
            TriggerClientEvent('wz-depanneur:client:dutyRefused', src, currentCount)
            return
        end
    end

    playersOnDuty[src] = status or nil

    -- Envoyer le nombre de dépanneurs actifs au joueur
    local activeCount = GetActiveDutyCount()
    TriggerClientEvent('wz-depanneur:client:dutySync', src, activeCount)

end)

--- Paiement avec calcul des dégâts et distance
RegisterNetEvent('wz-depanneur:server:payPlayer')
AddEventHandler('wz-depanneur:server:payPlayer', function(damageRatio, missionDist)
    local src = source

    -- ============================================================
    -- VÉRIFICATIONS DE SÉCURITÉ
    -- ============================================================

    -- 1. En service ?
    if not playersOnDuty[src] then
        print('^1[wz-depanneur] Paiement refuse : pas en service (' .. GetPlayerName(src) .. ')^0')
        return
    end

    -- 2. Bon job ?
    if GetPlayerJob(src) ~= Config.JobName then
        print('^1[wz-depanneur] Paiement refuse : mauvais job (' .. GetPlayerName(src) .. ')^0')
        return
    end

    -- 3. Anti-spam
    local now = os.time()
    if lastReward[src] and (now - lastReward[src]) < Config.ServerCooldown then
        print('^3[wz-depanneur] Paiement refuse : cooldown (' .. GetPlayerName(src) .. ')^0')
        return
    end

    -- 4. Valider le damageRatio (protection contre injection)
    if type(damageRatio) ~= 'number' then damageRatio = 0.0 end
    damageRatio = math.max(0.0, math.min(1.0, damageRatio))

    -- ============================================================
    -- CALCUL DE LA RÉCOMPENSE
    -- ============================================================
    local baseReward = math.random(Config.Reward.min, Config.Reward.max)

    -- Bonus de distance
    if type(missionDist) ~= 'number' then missionDist = 0 end
    missionDist = math.max(0, missionDist)
    local distRatio = math.min(1.0, missionDist / Config.DistanceBonus.maxDist)
    local distBonus = math.floor(Config.DistanceBonus.maxBonus * distRatio)
    baseReward = baseReward + distBonus

    -- Pénalité basée sur les dégâts (ex: 50% de dégâts = -25% de récompense si DamagePenaltyMax = 0.5)
    local penalty = damageRatio * Config.DamagePenaltyMax
    local finalReward = math.floor(baseReward * (1.0 - penalty))

    -- Bonus si aucun dégât
    if damageRatio <= 0.01 then
        finalReward = finalReward + Config.BonusNoDamage
    end

    -- Minimum garanti : 30% de la récompense de base
    finalReward = math.max(math.floor(baseReward * 0.3), finalReward)

    -- ============================================================
    -- PAIEMENT
    -- ============================================================
    if FrameworkType == 'esx' then
        local xPlayer = Framework.GetPlayerFromId(src)
        if xPlayer then
            xPlayer.addMoney(finalReward, 'Depannage - Livraison vehicule')
        end
    elseif FrameworkType == 'qb' then
        local player = Framework.Functions.GetPlayer(src)
        if player then
            player.Functions.AddMoney('cash', finalReward, 'depannage-livraison')
        end
    end

    lastReward[src] = now

    -- ============================================================
    -- MISE À JOUR DES STATISTIQUES
    -- ============================================================
    local license = GetPlayerLicense(src)
    local stats   = GetPlayerStats(license)

    stats.totalMissions = stats.totalMissions + 1
    stats.totalMoney    = stats.totalMoney + finalReward

    if damageRatio <= 0.01 then
        stats.currentStreak = stats.currentStreak + 1
        if stats.currentStreak > stats.bestStreak then
            stats.bestStreak = stats.currentStreak
        end
    else
        stats.currentStreak = 0
    end

    SaveStats()

    local ids = GetPlayerIdentifiers(src)
    print('^2[wz-depanneur] ' .. ids.name .. ' -> $' .. finalReward .. ' (degats: ' .. math.floor(damageRatio * 100) .. '%) | Missions: ' .. stats.totalMissions .. ' | Streak: ' .. stats.currentStreak .. '^0')

    -- Notifier le client de la récompense (pour le HUD session)
    TriggerClientEvent('wz-depanneur:client:missionPaid', src, finalReward)
end)

-- ============================================================
-- DEMANDE DE STATISTIQUES (CLIENT -> SERVEUR -> CLIENT)
-- ============================================================
RegisterNetEvent('wz-depanneur:server:requestStats')
AddEventHandler('wz-depanneur:server:requestStats', function()
    local src     = source
    local license = GetPlayerLicense(src)
    local stats   = GetPlayerStats(license)

    TriggerClientEvent('wz-depanneur:client:receiveStats', src, {
        totalMissions  = stats.totalMissions,
        totalMoney     = stats.totalMoney,
        currentStreak  = stats.currentStreak,
        bestStreak     = stats.bestStreak,
    })
end)

-- ============================================================
-- NETTOYAGE
-- ============================================================
AddEventHandler('playerDropped', function()
    local src = source
    playersOnDuty[src] = nil
    lastReward[src]    = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    playersOnDuty = {}
    lastReward    = {}
end)

-- ============================================================
-- PERSISTENCE DES MISSIONS
-- ============================================================

--- Sauvegarder une mission en cours
RegisterNetEvent('wz-depanneur:server:saveMission')
AddEventHandler('wz-depanneur:server:saveMission', function(data)
    local src     = source
    local license = GetPlayerLicense(src)
    savedMissions[license] = {
        type       = data.type,
        coordsX    = data.coordsX,
        coordsY    = data.coordsY,
        coordsZ    = data.coordsZ,
        coordsW    = data.coordsW,
        vehModel   = data.vehModel,
        stepDone   = data.stepDone,
        truckModel = data.truckModel,
    }
    SaveMissionsFile()
end)

--- Supprimer une mission sauvegardee (terminee ou abandonnee)
RegisterNetEvent('wz-depanneur:server:clearMission')
AddEventHandler('wz-depanneur:server:clearMission', function()
    local src     = source
    local license = GetPlayerLicense(src)
    if savedMissions[license] then
        savedMissions[license] = nil
        SaveMissionsFile()
    end
end)

--- Verifier si le joueur a une mission sauvegardee
RegisterNetEvent('wz-depanneur:server:checkSavedMission')
AddEventHandler('wz-depanneur:server:checkSavedMission', function()
    local src     = source
    local license = GetPlayerLicense(src)
    local mission = savedMissions[license]
    if mission then
        TriggerClientEvent('wz-depanneur:client:restoreMission', src, mission)
    end
end)

