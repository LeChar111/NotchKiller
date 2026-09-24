#!/bin/bash
# Régénère les visuels du README (docs/assets) à partir du mode démo :
# captures de chaque page, états du bandeau, vidéo et GIF de démonstration.
#
# Prérequis : ffmpeg, python3 avec Pillow, et l'autorisation « Enregistrement
# de l'écran » pour le terminal. Les réglages de l'app sont sauvegardés avant
# et restaurés après ; l'instance habituelle est relancée si elle tournait.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MEDIA="$ROOT/Tools/media"
OUT="$ROOT/docs/assets"
APP="$ROOT/build/NotchKiller.app"
BUNDLE_ID="io.github.lechar111.notchkiller"
WORK="$(mktemp -d)"
SHOTS="$WORK/shots"
mkdir -p "$SHOTS" "$OUT"

"$ROOT/build.sh"
swiftc -O -o "$WORK/winlist" "$MEDIA/winlist.swift"
swiftc -O -o "$WORK/wrec" "$MEDIA/wrec.swift"

WAS_RUNNING=0
pgrep -f "Applications/NotchKiller.app/Contents/MacOS/NotchKiller$" >/dev/null && WAS_RUNNING=1
defaults export "$BUNDLE_ID" "$WORK/prefs.plist" 2>/dev/null || true

restore() {
  pkill -f "$APP/Contents/MacOS/NotchKiller" 2>/dev/null || true
  [[ -f "$WORK/prefs.plist" ]] && defaults import "$BUNDLE_ID" "$WORK/prefs.plist"
  [[ $WAS_RUNNING == 1 ]] && open -a NotchKiller
  rm -rf "$WORK"
}
trap restore EXIT

osascript -e 'quit app "NotchKiller"' 2>/dev/null || true
demo() { "$ROOT/Tools/demo.sh" "$@"; }

launch() {
  pkill -f "$APP/Contents/MacOS/NotchKiller" 2>/dev/null || true
  sleep 1
  open -n "$APP" --args --demo
  sleep 6
  # Fenêtre de l'écran principal : origine en (0, 0).
  WID="$("$WORK/winlist" | awk '$3==0 && $4==0 {print $1; exit}')"
}

shot() {  # shot <nom>
  screencapture -x -o -l"$WID" "$WORK/raw.png"
  python3 "$MEDIA/crop.py" "$WORK/raw.png" "$SHOTS/$1.png"
}

echo "── Bandeau fermé"
launch
for activity in claude music calendar; do demo bar "$activity"; sleep 1; shot "bar-$activity"; done
demo done; sleep 1.2; shot bar-done

echo "── Pages"
launch
PAGES=(home:summary home:agenda dev:projects dev:ports dev:docker dev:terminal
       claude:sessions claude:history claude:mcp media: system:stats system:processes
       system:memory system:cleanup system:battery system:controls workshop:shelf
       workshop:clipboard workshop:notes workshop:calculator workshop:actions workshop:settings)
for page in "${PAGES[@]}"; do
  tab="${page%%:*}"; sub="${page#*:}"
  # Arriver sur le Terminal depuis une autre page referme le panneau : on
  # l'ouvre directement dessus.
  [[ $sub == terminal ]] && { demo close; sleep 1; }
  demo open "$tab" $sub; sleep 1.8
  shot "$tab${sub:+-$sub}"
done
demo close

echo "── Vidéo"
launch
"$WORK/wrec" "$WID" 31 "$WORK/frames" 1120 &
sleep 5
demo open home summary;       sleep 3.5
demo open dev projects;       sleep 3
demo open claude sessions;    sleep 3.5
demo open media;              sleep 3
demo open system stats;       sleep 3
demo open system processes;   sleep 2.5
demo open workshop clipboard; sleep 3
demo close;                   sleep 1.5
demo done
wait

python3 "$MEDIA/compose.py" "$WORK/frames" "$WORK/comp" >/dev/null
( cd "$WORK/comp"
  ffmpeg -y -loglevel error -f concat -safe 0 -i list.txt \
    -vf "fps=30,scale=1920:-2:flags=lanczos,format=yuv420p" \
    -c:v libx264 -crf 20 -preset slow -movflags +faststart "$OUT/demo.mp4"
  ffmpeg -y -loglevel error -f concat -safe 0 -i list.txt \
    -vf "fps=15,scale=900:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
    "$OUT/demo.gif" )

echo "── Visuels"
python3 "$MEDIA/design.py" "$SHOTS" "$OUT"
echo "OK : $OUT"
