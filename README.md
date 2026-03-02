# NotchKiller

Widget macOS inspiré d'un dock autour/sous le notch, avec animation au hover et stats système temps réel.

## Fonctionnalités
- Le widget s'affiche uniquement quand le curseur entre dans la zone notch définie
- Animation d'expansion/réduction au survol
- Vue compacte + vue détaillée
- Stats: CPU, RAM, batterie, download/upload, disque, heure, uptime, interface réseau
- Interface de configuration du périmètre de détection (largeur, hauteur, offsets, délai)
- Icône menu bar pour ouvrir la configuration et quitter
- Démarrage automatique à l'ouverture de session (via LaunchAgent)

## Prérequis
- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)
- Licence Xcode acceptée:

```bash
sudo xcodebuild -license accept
```

## Projet Xcode
Le dossier contient maintenant un projet Xcode natif:

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
Depuis le dossier du projet:

```bash
cd NotchKiller
chmod +x build.sh install.sh uninstall.sh
./install.sh
```

L'app est installée dans:

```bash
~/Applications/NotchKiller.app
```

## Réglage du périmètre de détection
1. Lance l'app.
2. Clique sur l'icône `NotchKiller` dans la menu bar.
3. Ouvre `Configuration de la zone...`.
4. Ajuste:
   - `Largeur` et `Hauteur` de la zone de détection
   - `Décalage horizontal` (gauche/droite)
   - `Départ depuis le haut` (distance depuis le bord supérieur)
   - `Position verticale widget`
   - `Délai de fermeture`
5. Active `Afficher la zone de détection à l'écran` pour visualiser la zone en direct.

## Lancer / Arrêter
- Lancer manuellement:

```bash
open ~/Applications/NotchKiller.app
```

- Quitter: icône `NotchKiller` dans la menu bar > `Quitter NotchKiller`

## Désinstallation

```bash
cd NotchKiller
./uninstall.sh
```

## Build seul (script)

```bash
cd NotchKiller
./build.sh
```

Le bundle compilé est généré dans `build/NotchKiller.app`.
