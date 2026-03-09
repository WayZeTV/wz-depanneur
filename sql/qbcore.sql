-- ============================================================
-- wz-depanneur | SQL pour QBCore
-- ============================================================
-- QBCore n'utilise PAS de tables SQL pour les jobs.
-- Les jobs sont définis dans : qb-core/shared/jobs.lua
--
-- Ajoutez ceci dans votre fichier qb-core/shared/jobs.lua :
-- ============================================================

--[[

    ['depanneur'] = {
        label = 'Dépanneur',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Stagiaire',       payment = 150 },
            ['1'] = { name = 'Employé',         payment = 200 },
            ['2'] = { name = 'Expérimenté',     payment = 275 },
            ['3'] = { name = 'Chef d\'équipe',  payment = 350 },
            ['4'] = { name = 'Patron',          payment = 500, isboss = true },
        },
    },

]]--

-- ============================================================
-- Si vous utilisez QBCore avec une base de données pour les jobs
-- (ex: qb-management), exécutez ceci :
-- ============================================================

INSERT INTO `management_funds` (`job_name`, `amount`, `type`) VALUES
    ('depanneur', 0, 'boss')
ON DUPLICATE KEY UPDATE `job_name` = 'depanneur';
