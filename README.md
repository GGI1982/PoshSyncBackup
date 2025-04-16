# 💾 PoshSyncBackup

**PoshSyncBackup** est un script PowerShell avancé conçu pour la **synchronisation automatique de dossiers** vers une destination unique (disque dur externe, NAS, etc.). Il combine **surveillance temps réel**, **planification périodique**, **gestion des erreurs**, et une **interface console interactive**, le tout avec des **notifications utilisateur modernes**.

---

## 🚀 Fonctionnalités principales

- 🔄 **Synchronisation automatique** à chaque changement (création, modification, suppression, renommage).
- ⏰ **Synchronisation planifiée** à intervalle régulier (ex. toutes les 6 heures).
- 🧠 **Détection intelligente des modifications** avec délais pour éviter les déclenchements en rafale.
- 📁 **Support multi-dossiers** avec sauvegarde centralisée dans une arborescence lisible.
- 🔧 **Configuration simple et claire** dans le script (sources, exclusions, délais…).
- 📜 **Journalisation complète** par dossier et par jour avec niveaux de gravité (INFO, WARNING, ERROR).
- 🛎️ **Notifications Toast Windows** via [BurntToast] ou fallback natif.
- 🖥️ **Interface console interactive** : synchronisation manuelle, affichage des logs, aide, sortie propre.
- 🔒 **Sécurité opérationnelle** : gestion des verrous, tentatives multiples, traitement des erreurs transitoires.

---

## ✅ Cas d’usage

- 🔁 Sauvegarde de vos projets vers un disque dur externe, sans outil tiers.
- 🏠 Usage personnel ou **semi-professionnel** dans une TPE / PME.
- 📂 Maintien d’une copie à jour de dossiers critiques (documents, photos, code source…).
- ⚙️ Intégration dans une stratégie de continuité d’activité légère.

---

## 🛠️ Prérequis

- PowerShell 5.1 ou supérieur (Windows 10 / 11 recommandé)
- Pour notifications avancées : [BurntToast](https://github.com/Windos/BurntToast)

```powershell
Install-Module -Name BurntToast -Force
```

---

## 📦 Installation

1. Clonez ou téléchargez ce dépôt :

```bash
git clone https://github.com/votre-utilisateur/PoshSyncBackup.git
```

2. Modifiez les paramètres dans la section `# CONFIGURATION` du script :
   - Dossiers à synchroniser (`$Sources`)
   - Destination (`$BackupRoot`)
   - Filtres d’exclusion, fréquence, délais, etc.

3. Exécutez le script :

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\PoshSyncBackup.ps1
```

4. (Optionnel) Ajoutez à une tâche planifiée ou exécutez au démarrage via raccourci.

---

## 🧭 Interface console

- `S` → Forcer une synchronisation immédiate de tous les dossiers
- `L` → Afficher les derniers logs journaliers
- `?` → Afficher l’aide intégrée
- `Q` → Quitter proprement le programme

---

## 🔄 Roadmap

- [x] Gestion multi-dossiers
- [x] Notifications toast avec fallback
- [x] Journalisation avancée par niveau
- [ ] Support de fichier de configuration externe (`.json` ou `.psd1`)
- [ ] Export statistiques (CSV ou JSON)
- [ ] Mode service ou packaging .exe / installateur

---

## 📄 Licence

Ce projet est distribué sous licence **GNU GPL**.

---

## 🤝 Contributions

Les contributions sont les bienvenues ! Proposez vos idées via les Issues ou ouvrez une Pull Request.

---

**Auteur** : [VotreNom]  
**Version actuelle** : `v1.0`  
**Nom du projet** : `PoshSyncBackup`
```


