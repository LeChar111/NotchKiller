# NotchKiller

Widget macOS inspiré de l'effet notch dynamique, avec affichage au hover uniquement sur une zone configurable.

## Fonctionnalités
- UI type "nook" collée en haut avec contenu descendu sous la zone notch
- Apparition uniquement quand la souris entre dans la zone de détection
- Rail de navigation fonctionnel:
  - `Accueil`
  - `Stats`
  - `Outils`
  - `Param`
- Boutons rapides fonctionnels:
  - Ouvrir Music / Spotify / YouTube
  - Ouvrir Finder / Activity Monitor / Console / System Settings
  - Verrouiller l'écran
  - Activer/Désactiver la zone debug hover
- Page `Stats` dédiée avec cartes système
- Page `Param` dédiée pour configurer:
  - Largeur / hauteur du widget
  - Position verticale
  - Zone de détection hover
  - Délai de fermeture
  - Statistiques affichées
- Fenêtre de configuration complète depuis la menu bar
- Démarrage automatique à l'ouverture de session (LaunchAgent)

## Prérequis
- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)
- Licence Xcode acceptée:

```bash
sudo xcodebuild -license accept
```

## Projet Xcode
Le dossier contient un projet Xcode natif:

- `NotchKiller.xcodeproj`

Ouvrir dans Xcode:

```bash
open NotchKiller/NotchKiller.xcodeproj
```

Puis dans Xcode:
1. Sélectionner le scheme `NotchKiller`.
2. Choisir `My Mac`.
3. Lancer avec `Cmd+R`.

## Installation (script)

```bash
cd NotchKiller
chmod +x build.sh install.sh uninstall.sh
./install.sh
```

App installée dans:

```bash
~/Applications/NotchKiller.app
```

## Configuration
Depuis l'icône menu bar `NotchKiller`:
- `Afficher le widget`
- `Configuration...`

Dans le widget lui-même:
- Rail droit pour changer de page
- Page `Param` pour les réglages en temps réel

## Désinstallation

```bash
cd NotchKiller
./uninstall.sh
```
