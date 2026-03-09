Config = {}

-- ============================================================
-- FRAMEWORK
-- ============================================================
-- 'auto' = détection automatique | 'esx' | 'qb'
Config.Framework = 'auto'

-- ============================================================
-- JOB
-- ============================================================
Config.JobName = 'depanneur'
Config.MaxDepanneurs = 0  -- Nombre max de dépanneurs en service simultanément (0 = illimité)

-- ============================================================
-- POINT DE PRISE DE SERVICE
-- ============================================================
Config.DutyPoint = {
    coords = vector3(722.20526123047, -1069.5997314453, 23.06240272522),
    radius = 2.0,
    blip = {
        enabled = true,
        sprite  = 446,
        color   = 5,
        scale   = 0.8,
        label   = 'Dépanneur - Service',
    },
    marker = {
        type  = 1,
        color = { r = 50, g = 150, b = 255, a = 120 },
        scale = vector3(2.0, 2.0, 0.8),
    },
}

-- ============================================================
-- PNJ CHEF (STATISTIQUES)
-- ============================================================
Config.BossPed = {
    coords  = vector4(722.71234, -1072.457763, 22.06, 90.15522),  -- À côté du duty point
    model   = 's_m_m_autoshop_02',                        -- Modèle mécano chef
    radius  = 2.0,                                        -- Distance d'interaction
    anim    = {
        dict = 'anim@heists@heist_corona@single_team',
        name = 'single_team_loop_boss',
    },
    dialogues = {
        'Alors, comment ca se passe aujourd\'hui ?',
        'T\'as fait du bon boulot !',
        'Viens voir tes stats si tu veux.',
        'On a besoin de bras, au travail !',
        'Le patron est content de toi.',
        'Tu veux voir ton tableau de bord ?',
    },
}

-- ============================================================
-- CAMION DÉPANNEUR (FLATBED)
-- ============================================================
Config.TowTrucks = {
    {
        label        = 'Flatbed (Plateau)',
        model        = 'flatbed',
        attachMethod = 'flatbed',   -- Le véhicule est posé sur le plateau
        attachOffset   = { x = 0.0, y = -0.8, z = 0.95 },
        attachRotation = { x = 0.0, y = 0.0, z = 0.0 },
    },
    {
        label        = 'Towtruck (Crochet)',
        model        = 'towtruck',
        attachMethod = 'hook',      -- Le véhicule est soulevé par le crochet arrière
    },
    {
        label        = 'Towtruck 2 (Petit)',
        model        = 'towtruck2',
        attachMethod = 'hook',      -- Le véhicule est soulevé par le crochet arrière
    },
}

-- Point de spawn du camion choisi
Config.TowTruckSpawn = vector4(709.15588378906, -1071.4077148438, 22.358392715454, 357.117492)

-- ============================================================
-- POINT DE LIVRAISON (DÉPÔT)
-- ============================================================
Config.DeliveryPoint = {
    coords = vector3(717.4047851, -1088.6636962, 22.359910964),  -- Où ramener le véhicule
    radius = 5.0,
    blip = {
        sprite = 477,
        color  = 2,
        scale  = 0.9,
        label  = '🔧 Dépôt - Livraison',
    },
    marker = {
        type  = 1,
        color = { r = 50, g = 255, b = 50, a = 100 },
        scale = vector3(5.0, 5.0, 1.0),
    },
}

-- ============================================================
-- MISSIONS
-- ============================================================
-- Délai entre chaque mission (en millisecondes)
Config.MissionCooldown = 2 * 60 * 1000  -- 2 minutes entre chaque mission

-- Durée de la barre de progression pour accrocher le véhicule (en ms)
Config.HookDuration = 8000  -- 8 secondes

-- Distance d'interaction avec le véhicule en panne
Config.InteractDistance = 4.0

-- ============================================================
-- TYPES DE MISSIONS
-- ============================================================
-- weight = probabilité relative (plus c'est haut, plus c'est fréquent)
Config.MissionTypes = {
    {
        type   = 'panne',
        label  = 'Panne moteur',
        weight = 20,
        blipName = 'Vehicule en panne',
    },
    {
        type   = 'panne_seche',
        label  = 'Panne seche',
        weight = 20,
        blipName = 'Panne de carburant',
        fillDuration = 6000,  -- Durée du remplissage (ms)
    },
    {
        type   = 'batterie',
        label  = 'Batterie a plat',
        weight = 20,
        blipName = 'Batterie a plat',
        step1Duration = 4000,  -- Branchement
        step2Duration = 3000,  -- Charge
        step3Duration = 2000,  -- Démarrage
    },
    {
        type   = 'pneu_creve',
        label  = 'Pneu creve',
        weight = 20,
        blipName = 'Pneu creve',
        changeDuration = 10000,  -- Durée du changement de pneu (ms)
    },
    {
        type   = 'accident',
        label  = 'Accident',
        weight = 10,
        blipName = 'Accident de la route',
    },
    {
        type   = 'fourriere',
        label  = 'Mise en fourriere',
        weight = 10,
        blipName = 'Vehicule en fourriere',
    },
}

-- ============================================================
-- RÉCOMPENSES
-- ============================================================
Config.Reward = {
    min = 200,   -- Récompense minimum ($)
    max = 450,   -- Récompense maximum ($)
}

-- Bonus si le véhicule est ramené sans aucun dégât (en $)
Config.BonusNoDamage = 100

-- Pénalité : pourcentage de réduction par dégât subi (0.0 à 1.0)
-- Ex: 0.5 = le joueur perd jusqu'à 50% de sa récompense si le camion est très endommagé
Config.DamagePenaltyMax = 0.5

-- Bonus de distance (plus la mission est loin, plus on gagne)
Config.DistanceBonus = {
    maxDist  = 5000,   -- Distance max pour le bonus complet (en mètres)
    maxBonus = 300,    -- Bonus max en $ (à maxDist ou plus)
}

-- Probabilités de distance des missions (weight = fréquence relative)
-- Plus le weight est élevé, plus cette tranche de distance a de chances d'être choisie
Config.MissionDistances = {
    { min = 500,   max = 2000,   weight = 50 },  -- Proche     : très fréquent
    { min = 2000,  max = 4000,   weight = 30 },  -- Moyen      : fréquent
    { min = 4000,  max = 6000,   weight = 15 },  -- Loin       : occasionnel
    { min = 6000,  max = 8000,   weight = 10 },  -- Très loin  : rare
    { min = 8000,  max = 12000,  weight = 5  },  -- Extrême   : très rare
}

-- ============================================================
-- ANTI-SPAM / SÉCURITÉ
-- ============================================================
Config.ServerCooldown = 60  -- Secondes entre deux paiements

-- ============================================================
-- MODÈLES DE VÉHICULES EN PANNE
-- ============================================================
Config.BrokenVehicles = {
    'emperor',
    'prairie',
    'asea',
    'stanier',
    'premier',
    'fugitive',
    'surge',
    'stratum',
    'tailgater',
    'washington',
}

-- ============================================================
-- PNJ
-- ============================================================
Config.PedModel = 's_m_y_construct_01'

Config.PedWaitAnim = {
    dict = 'anim@heists@heist_corona@single_team',
    name = 'single_team_loop_boss',
}

-- ============================================================
-- DIALOGUES DU PNJ
-- ============================================================
Config.PedDialogues = {
    -- Phrases génériques (panne moteur classique)
    waiting = {
        'Enfin vous etes la !',
        'Ma voiture est tombee en panne...',
        'Merci d\'etre venu aussi vite !',
        'J\'attends depuis un moment...',
        'Vous pouvez m\'aider ?',
        'Le moteur a lache d\'un coup !',
        'Heureusement que vous etes la !',
        'Je suis bloque ici...',
    },
    -- Phrases quand le véhicule est accroché (PNJ content)
    thanking = {
        'Merci beaucoup !',
        'Vous etes un pro !',
        'Genial, merci pour votre aide !',
        'Super travail !',
        'Je vous dois une fiere chandelle !',
        'Parfait, bonne route !',
        'Merci, bonne journee !',
        'Vous gerez !',
    },
    -- Phrases spécifiques par type de mission
    panne_seche = {
        'J\'ai plus une goutte d\'essence...',
        'Le reservoir est completement vide !',
        'J\'aurais du faire le plein...',
        'Vous avez un jerrican ?',
    },
    batterie = {
        'La batterie est a plat...',
        'Plus rien ne demarre !',
        'Les phares se sont eteints d\'un coup.',
        'Je crois que c\'est la batterie...',
    },
    pneu_creve = {
        'J\'ai creve en pleine route !',
        'Le pneu a eclate !',
        'J\'ai pas de roue de secours...',
        'Vous pouvez changer mon pneu ?',
    },
    accident = {
        'On s\'est percutes !',
        'L\'autre conducteur est parti...',
        'Regardez l\'etat de ma voiture !',
        'C\'est arrive tellement vite...',
    },
}

-- ============================================================
-- ANIMATION D'ACCROCHAGE (joueur)
-- ============================================================
Config.HookAnim = {
    dict = 'mini@repair',
    name = 'fixing_a_player',
}

-- ============================================================
-- TENUE DE SERVICE
-- ============================================================
-- Composants : { componentId, drawable, texture, palette }
-- componentId : 1=Masque, 3=Torse, 4=Pantalon, 6=Chaussures, 7=Accessoire, 8=Sous-haut, 11=Veste
Config.Uniform = {
    male = {
        { 3,  0,   0, 0 },   -- Torse (ajuster selon votre serveur)
        { 4,  36,  0, 0 },   -- Pantalon de travail
        { 6,  24,  0, 0 },   -- Bottes de travail
        { 8,  59,  0, 0 },   -- Sous-haut
        { 11, 55,  0, 0 },   -- Veste/Bleu de travail
    },
    female = {
        { 3,  0,   0, 0 },
        { 4,  36,  0, 0 },
        { 6,  24,  0, 0 },
        { 8,  34,  0, 0 },
        { 11, 48,  0, 0 },
    },
}

-- ============================================================
-- POSITIONS DE SPAWN DES MISSIONS
-- ============================================================
Config.MissionLocations = {
    {
        coords = vector4(251.35, -647.68, 40.24, 250.0),
        description = 'Près du centre-ville',
    },
    {
        coords = vector4(-538.23, -246.41, 35.65, 30.0),
        description = 'Route principale ouest',
    },
    {
        coords = vector4(1208.47, -1402.56, 35.22, 180.0),
        description = 'Zone industrielle est',
    },
    {
        coords = vector4(-1044.65, -2739.91, 13.86, 330.0),
        description = 'Près de l\'aéroport',
    },
    {
        coords = vector4(373.21, -1828.97, 29.29, 140.0),
        description = 'Sud de la ville',
    },
    {
        coords = vector4(-323.78, -1545.18, 27.55, 320.0),
        description = 'Quartier résidentiel',
    },
    {
        coords = vector4(817.77, -1290.78, 26.28, 90.0),
        description = 'Autoroute est',
    },
    {
        coords = vector4(-1613.69, -1050.09, 13.02, 225.0),
        description = 'Bord de mer',
    },
    {
        coords = vector4(1137.97, -470.88, 66.73, 280.0),
        description = 'Collines de Vinewood',
    },
    {
        coords = vector4(-72.17, -1761.87, 29.53, 50.0),
        description = 'Zone sud',
    },
}

-- ============================================================
-- NOTIFICATIONS
-- ============================================================
Config.Notifications = {
    onDuty          = 'Service pris ! Votre camion dépanneur est prêt.',
    offDuty         = 'Fin de service. Le camion a été retiré.',
    missionStart    = 'Un véhicule en panne vous attend ! Prenez votre camion.',
    hookStart       = 'Accrochage du véhicule en cours...',
    hookDone        = 'Véhicule accroché ! Ramenez-le au dépôt sans accident.',
    hookCancel      = 'Accrochage annulé.',
    deliveryDone    = 'Livraison effectuée !',
    bonusNoDamage   = 'Bonus : véhicule ramené en parfait état ! +$',
    damagePenalty   = 'Dégâts constatés : récompense réduite.',
    alreadyOnMission = 'Vous avez déjà une mission en cours.',
    notOnDuty       = 'Vous devez être en service.',
    wrongJob        = 'Vous n\'êtes pas dépanneur.',
    needTowTruck    = 'Approchez avec votre camion dépanneur !',
    notInTowTruck   = 'Vous devez être dans votre camion pour accrocher le véhicule.',
    -- Missions spéciales
    fillStart       = 'Remplissage du réservoir en cours...',
    fillDone        = 'Réservoir rempli ! Vous pouvez maintenant remorquer le véhicule.',
    batteryStart    = 'Branchement des câbles en cours...',
    batteryCharge   = 'Charge de la batterie...',
    batteryStartup  = 'Tentative de démarrage...',
    batteryDone     = 'Batterie rechargée ! Vous pouvez maintenant remorquer.',
    tireStart       = 'Changement du pneu en cours...',
    tireDone        = 'Pneu changé ! Le conducteur peut repartir.',
    accidentStart   = 'Accident signalé. Remorquez l\'un des véhicules.',
    fourriereStart  = 'Véhicule signalé en fourrière. Remorquez-le au dépôt.',
    actionCancel    = 'Action annulée.',
}
