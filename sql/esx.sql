-- ============================================================
-- wz-depanneur | SQL pour ESX
-- Ajoute le job 'depanneur' avec ses grades
-- ============================================================

-- 1) Créer le job
INSERT INTO `jobs` (`name`, `label`) VALUES
    ('depanneur', 'Dépanneur')
ON DUPLICATE KEY UPDATE `label` = 'Dépanneur';

-- 2) Créer les grades
INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`) VALUES
    ('depanneur', 0, 'stagiaire',   'Stagiaire',        150, '{}', '{}'),
    ('depanneur', 1, 'employe',     'Employé',          200, '{}', '{}'),
    ('depanneur', 2, 'experienced', 'Expérimenté',      275, '{}', '{}'),
    ('depanneur', 3, 'chef',        'Chef d\'équipe',   350, '{}', '{}'),
    ('depanneur', 4, 'patron',      'Patron',           500, '{}', '{}')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `salary` = VALUES(`salary`);
