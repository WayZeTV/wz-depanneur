# 🔧 wz-depanneur

Script de job dépanneur complet pour FiveM — Compatible **ESX** et **QBCore** - Script réalisé pour une [vidéo Youtube](https://www.youtube.com/watch?v=5Sojt7tHZb0)

---

## ✨ Fonctionnalités

- 🚗 **6 types de missions** : panne moteur, panne sèche, batterie, pneu crevé, accident, fourrière
- 🎲 **Probabilités pondérées** par type de mission et par distance
- 🗺️ **Missions sur toute la map** avec bonus de distance (plus c'est loin, plus ça paye)
- 🚛 **3 camions sélectionnables** : flatbed, towtruck, towtruck2
- 🔗 **Système d'accrochage réaliste** avec ré-accrochage si le véhicule se décroche
- ✅ **Vérification de livraison** : impossible de valider sans le véhicule
- 💰 **Système économique complet** : récompenses, bonus sans dégâts, pénalités, bonus streak
- 📊 **Statistiques persistantes** : missions, argent, séries sans dégâts
- 💾 **Persistence crash/restart** : restauration auto du service, camion et mission en cours
- 🎨 **Menu F6** avec navigation clavier + panneau de statistiques
- 📺 **HUD de service** : temps, missions, argent de la session
- 🔒 **Anti-spam serveur** avec vérifications de sécurité
- 👥 **Limite de dépanneurs simultanés** configurable

## 📦 Installation

### 1. Ajouter la resource
Placez le dossier `wz-depanneur` dans votre répertoire `resources/`.

### 2. Base de données
Importez le fichier SQL correspondant à votre framework :
- **ESX** → `sql/esx.sql`
- **QBCore** → `sql/qbcore.sql` (suivez les instructions dans le fichier)

### 3. Démarrer la resource
Ajoutez dans votre `server.cfg` :
```
ensure wz-depanneur
```

### 4. Configuration
Tous les paramètres sont modifiables dans `config.lua` :
- Point de service et de livraison
- Camions disponibles
- Types de missions et probabilités
- Récompenses et pénalités
- Distances et bonus
- Cooldowns et limites

## ⚙️ Configuration rapide

| Paramètre | Description | Défaut |
|-----------|-------------|--------|
| `Config.JobName` | Nom du job | `depanneur` |
| `Config.MissionCooldown` | Délai entre les missions | 3 min |
| `Config.Reward.min / max` | Récompense de base | 200$ - 450$ |
| `Config.DistanceBonus.maxBonus` | Bonus distance max | 300$ |
| `Config.MaxDepanneurs` | Limite de joueurs en service | 3 |
| `Config.MissionDistances` | Probabilités par tranche de distance | Configurable |

## 💻​ Hébergement FiveM

Si vous êtes à la recherche d'un hébergeur FiveM fiable, je suis le propriétaire du [meilleur hébergeur FiveM](https://hanohost.fr/) HanoHost Hébergement ! 

## 📝 Support

Pour toute question, rendez-vous sur [SW Développement](https://discord.gg/hAy5VMP)

---
© wz-scripts | Tous droits réservés 2026


