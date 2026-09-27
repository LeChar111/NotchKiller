import Foundation

/// Scripts embarqués par la page Nettoyage. NotchKiller les écrit dans
/// `~/Library/Application Support/NotchKiller/scripts/` au premier usage et à
/// chaque mise à jour de l'app : c'est ce texte qui fait foi, pas la copie disque.
enum MaintenanceScripts {
    static let audioOffloadName = "audio-plugins-offload.sh"
    static let maintenanceName = "nk-maintenance.sh"

    /// Déplace les plug-ins audio et les données des éditeurs (banques de sons, iZotope,
    /// Native Instruments…) vers un disque externe (lien à la place),
    /// surveille les futurs, rapatrie, met les intrus en quarantaine. Tourne en root.
    static let audioOffload = #"""
#!/bin/zsh -f
# audio-plugins-offload — déplace les plug-ins audio vers un disque externe.
# Chaque plug-in est copié, vérifié (nombre de fichiers + taille), supprimé puis
# remplacé par un lien symbolique : les DAW le retrouvent au même chemin.
#
#   sudo audio-plugins-offload.sh --dest DIR     déplace ce qui est encore sur le Mac
#                                                (plug-ins + données des éditeurs audio)
#   sudo audio-plugins-offload.sh --watch        + surveille les dossiers (futurs plug-ins)
#   sudo audio-plugins-offload.sh --unwatch      arrête la surveillance
#   sudo audio-plugins-offload.sh --restore      rapatrie tout sur le Mac
#   sudo audio-plugins-offload.sh --quarantine   sort les fichiers qui ne sont pas des plug-ins
#   audio-plugins-offload.sh --status | --dry-run
#
# Avec --watch --helper <NotchKillerAudioHelper>, le service lance cet assistant (qui
# peut recevoir l'Accès complet au disque, contrairement à /bin/zsh) et lit les demandes
# que NotchKiller dépose dans ~/Library/Application Support/NotchKiller/requests/.
#
# Généré par NotchKiller (Système › Nettoyage) — ne pas modifier à la main.
setopt null_glob
umask 022

LABEL="io.github.lechar111.notchkiller.audio-offload"
SUPPORT="/Library/Application Support/NotchKiller"
CONF="$SUPPORT/audio-offload.conf"
STATUS="$SUPPORT/audio-offload-status.json"
INSTALLED="$SUPPORT/audio-plugins-offload.sh"
HELPER="$SUPPORT/NotchKillerAudioHelper"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
LOGDIR="/Library/Logs/NotchKiller"
LOG="$LOGDIR/audio-offload.log"
LOCK="/tmp/$LABEL.lock"
SETTLE_MIN=10   # un plug-in modifié il y a moins de 10 min est peut-être en cours d'installation
PLUGIN_EXT=(component vst vst3 clap aaxplugin)
# Données des éditeurs (banques de sons, modèles, ressources partagées) rangées dans
# /Library (ex. /Library/Arturia), /Library/Application Support ou /Users/Shared. Avid est exclu : ses plug-ins AAX
# sont déplacés un par un.
VENDORS=("iZotope" "Native Instruments" "Arturia" "D16 Group" "Kilohearts" "reFX" "Valhalla DSP"
         "FabFilter" "Xfer Records" "Spectrasonics" "Output" "u-he" "Waves" "Soundtoys"
         "Plugin Alliance" "Brainworx" "Eventide" "Softube" "Toontrack" "Spitfire Audio"
         "Heavyocity" "UJAM" "sonible" "oeksound" "Cableguys" "Polyverse" "Baby Audio"
         "AudioThing" "Goodhertz" "Sugar Bytes" "Tone2" "LennarDigital" "Rob Papen" "Vital Audio")
VENDOR_BASES=("/Library" "/Library/Application Support" "/Users/Shared")
# Logiciels qui chargent les plug-ins : on ne déplace rien pendant qu'ils tournent.
DAWS="Live|Ableton Live.*|Logic Pro|Logic Pro X|MainStage|GarageBand|Pro Tools|REAPER|Bitwig Studio|FL Studio|Studio One|Cubase.*|Nuendo.*|Reason|rekordbox|Serato DJ.*|Traktor.*|Kontakt.*|Komplete Kontrol|Maschine.*|Analog Lab.*|Serum|Vital"

MODE=run DEST="" QUIET=0 DAEMON=0 HELPER_SRC=""
while (( $# )); do
  case "$1" in
    --dest) DEST="$2"; shift ;;
    --watch) MODE=watch ;; --unwatch) MODE=unwatch ;; --restore) MODE=restore ;;
    --quarantine) MODE=quarantine ;; --status) MODE=status ;; --dry-run) MODE=dry ;;
    --quiet) QUIET=1 ;; --daemon) DAEMON=1 ;;
    --helper) HELPER_SRC="$2"; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) print -u2 "Option inconnue : $1"; exit 64 ;;
  esac; shift
done
[[ -z "$DEST" && -r "$CONF" ]] && DEST="$(sed -n 's/^DEST=//p' "$CONF")"
REQUEST_DIR=""; [[ -r "$CONF" ]] && REQUEST_DIR="$(sed -n 's/^REQUEST_DIR=//p' "$CONF")"

# Demande déposée par NotchKiller (déplacer, mettre en quarantaine, rapatrier). Le
# dossier appartient à l'utilisateur : on ne lit qu'un fichier ordinaire, jamais un lien,
# et seule l'une des trois actions connues est retenue ; la destination reste celle de
# la configuration root.
if (( DAEMON )) && [[ -n "$REQUEST_DIR" ]]; then
  req="$REQUEST_DIR/audio-offload.request"
  if [[ -f "$req" && ! -L "$req" ]]; then
    action="$(head -c 32 "$req" | tr -cd 'a-z')"; rm -f "$req"
    case "$action" in move) MODE=run ;; quarantine) MODE=quarantine ;; restore) MODE=restore ;; esac
  fi
fi
DEST="${DEST%/}"

# ── Affichage ────────────────────────────────────────────────────────────────
if [[ -t 1 && $QUIET -eq 0 ]]; then
  B=$'\e[1m' D=$'\e[2m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' C=$'\e[36m' N=$'\e[0m'
else B= D= G= Y= R= C= N=; fi
log() { [[ -w "$LOGDIR" ]] && print -r -- "$(date '+%F %T')  $*" >> "$LOG"; }
say() { (( QUIET )) || print -r -- "$*"; log "$(print -r -- "$*" | sed $'s/\e\\[[0-9;]*m//g')"; }
human() { local k=$1; if (( k >= 1048576 )); then printf "%.1f Go" $((k/1048576.0)); elif (( k >= 1024 )); then printf "%d Mo" $((k/1024)); else printf "%d Ko" $k; fi; }
size_kb() { print ${$(du -sk "$1" 2>/dev/null | cut -f1):-0}; }

# ── Inventaire ───────────────────────────────────────────────────────────────
# Dossiers de plug-ins : système + chaque utilisateur
plugin_dirs() {
  local d u
  for d in /Library/Audio/Plug-Ins/{Components,VST,VST3,CLAP} "/Library/Application Support/Avid/Audio/Plug-Ins"; do print -r -- "$d"; done
  for u in /Users/*(/); do
    [[ "${u:t}" == Shared ]] && continue
    for d in "$u"/Library/Audio/Plug-Ins/{Components,VST,VST3,CLAP}; do print -r -- "$d"; done
  done
}
kind_of() {
  case "$1" in
    *Avid*) print AAX ;;
    /Library|"/Library/Application Support"|/Users/Shared) print Données ;;
    *) print "${1:t}" ;;
  esac
}
vendor_dirs() {
  local base p v
  for base in $VENDOR_BASES; do
    for p in "$base"/*; do
      for v in $VENDORS; do [[ "${p:t:l}" == "${v:l}"* ]] && { print -r -- "$p"; break; }; done
    done
  done
}
# Emplacement sur le disque : DEST/<type> (système) ou DEST/utilisateurs/<nom>/<type>
target_of() {
  local dir="${1:h}"
  if [[ "$dir" == /Library ]]; then print -r -- "$DEST/Donnees/Library/${1:t}"
  elif [[ "$dir" == "/Library/Application Support" ]]; then print -r -- "$DEST/Donnees/Application Support/${1:t}"
  elif [[ "$dir" == /Users/Shared ]]; then print -r -- "$DEST/Donnees/Shared/${1:t}"
  elif [[ "$dir" == /Users/* ]]; then print -r -- "$DEST/utilisateurs/${${dir#/Users/}%%/*}/$(kind_of "$dir")/${1:t}"
  else print -r -- "$DEST/$(kind_of "$dir")/${1:t}"; fi
}
# Un plug-in : un bundle audio, ou un dossier d'éditeur qui en contient.
is_plugin() {
  local p="$1" real="$1"
  [[ -L "$p" ]] && real="$(readlink "$p")"
  [[ "${p:e}" == (${(j:|:)~PLUGIN_EXT}) ]] && return 0
  [[ -d "$real" && ! -L "$real" ]] || return 1
  [[ -n "$(find "$real" -maxdepth 3 \( -name '*.component' -o -name '*.vst' -o -name '*.vst3' -o -name '*.clap' -o -name '*.aaxplugin' \) -print -quit 2>/dev/null)" ]]
}

fingerprint() { /usr/bin/python3 -c '
import os,sys
n=s=0
import stat
for r,ds,fs in os.walk(sys.argv[1]):
    for x in ds+fs:
        st=os.lstat(os.path.join(r,x))
        # Tubes, sockets et périphériques : ditto ne les copie pas (et ce ne sont pas des données).
        if stat.S_ISFIFO(st.st_mode) or stat.S_ISSOCK(st.st_mode) or stat.S_ISCHR(st.st_mode) or stat.S_ISBLK(st.st_mode): continue
        n+=1; s+=st.st_size
print(n,s)' "$1"; }

daw_running() { pgrep -xq "$DAWS"; }
# (package_script_service est un service XPC de PackageKit qui peut traîner des heures
# après une installation : ce n'est pas un signal fiable, la règle des 10 min suffit.)
installing() { pgrep -xq "installer|Installer|Native Access|Native Access 2|iZotope Product Portal|Waves Central|Arturia Software Center|Plugin Alliance Installation Manager|Splice|Splice Instrument|Spitfire Audio|Output Hub"; }

count_state() {  # → ON_MAC ON_DEST MAC_KB INTRUDERS SUP_MAC SUP_DEST SUP_KB
  ON_MAC=0 ON_DEST=0 MAC_KB=0 INTRUDERS=0 SUP_MAC=0 SUP_DEST=0 SUP_KB=0
  local dir p
  for p in ${(f)"$(vendor_dirs)"}; do
    if [[ -L "$p" ]]; then (( SUP_DEST++ )); else (( SUP_MAC++ )); SUP_KB=$(( SUP_KB + $(size_kb "$p") )); fi
  done
  for dir in ${(f)"$(plugin_dirs)"}; do
    for p in "$dir"/*; do
      [[ "${p:t}" == .* ]] && continue
      if ! is_plugin "$p"; then (( INTRUDERS++ ))
      elif [[ -L "$p" ]]; then (( ON_DEST++ ))
      else (( ON_MAC++ )); MAC_KB=$(( MAC_KB + $(size_kb "$p") )); fi
    done
  done
}

write_status() {  # $1 état, $2 message, [$3 fait, $4 total, $5 élément en cours]
  [[ -w "$SUPPORT" ]] || return 0
  local watching=false mounted=false
  [[ -f "$PLIST" ]] && watching=true
  [[ -n "$DEST" && -d "${DEST:h}" ]] && mounted=true
  /usr/bin/python3 - "$STATUS" "$1" "$2" "${3:-0}" "${4:-0}" "${5:-}" "$DEST" $watching $mounted \
    "${ON_MAC:-0}" "${ON_DEST:-0}" "${MAC_KB:-0}" "${INTRUDERS:-0}" "${MOVED:-0}" "${FAILED:-0}" "${DEFERRED:-0}" \
    "${SUP_MAC:-0}" "${SUP_DEST:-0}" "${SUP_KB:-0}" <<'PY'
import json,sys,time,os
a=sys.argv
d=dict(state=a[2],message=a[3],done=int(a[4]),total=int(a[5]),current=a[6],dest=a[7],
       watching=a[8]=="true",destMounted=a[9]=="true",onMac=int(a[10]),onDest=int(a[11]),
       onMacKB=int(a[12]),intruders=int(a[13]),moved=int(a[14]),failed=int(a[15]),deferred=int(a[16]),
       supportOnMac=int(a[17]),supportOnDest=int(a[18]),supportOnMacKB=int(a[19]),
       updatedAt=int(time.time()))
tmp=a[1]+".tmp"; json.dump(d,open(tmp,"w"),ensure_ascii=False); os.chmod(tmp,0o644); os.replace(tmp,a[1])
PY
}

need_root() { [[ $EUID -eq 0 ]] || { print -u2 "${R}À lancer avec sudo.${N}"; exit 77; }; }
prepare() {
  mkdir -p "$SUPPORT" "$LOGDIR"; chmod 755 "$SUPPORT" "$LOGDIR"
  [[ -f "$LOG" ]] && (( $(stat -f %z "$LOG") > 2097152 )) && mv -f "$LOG" "$LOG.1"
}

# ── Modes sans déplacement ───────────────────────────────────────────────────
if [[ $MODE == status ]]; then
  count_state
  print "${B}Plug-ins audio${N}"
  print "  sur le Mac      : ${B}$ON_MAC${N} ($(human $MAC_KB))"
  print "  sur le disque   : ${B}$ON_DEST${N} (liens)"
  print "${B}Données des éditeurs${N} (iZotope, Native Instruments, Arturia…)"
  print "  sur le Mac      : ${B}$SUP_MAC${N} dossier(s) ($(human $SUP_KB))"
  print "  sur le disque   : ${B}$SUP_DEST${N} (liens)"
  (( INTRUDERS )) && print "  ${Y}intrus${N}          : ${B}$INTRUDERS${N} fichiers qui ne sont pas des plug-ins (--quarantine)"
  print "  destination     : ${DEST:-${Y}non définie${N}} $([[ -n "$DEST" && -d "${DEST:h}" ]] && print "${G}branchée${N}" || print "${R}absente${N}")"
  print "  surveillance    : $([[ -f "$PLIST" ]] && print "${G}active${N}" || print "${D}inactive${N}")"
  print "  journal         : $LOG"
  exit 0
fi

if [[ $MODE == unwatch ]]; then
  need_root; prepare
  launchctl bootout system/$LABEL 2>/dev/null
  rm -f "$PLIST"; say "${G}Surveillance arrêtée${N} — les plug-ins déjà déplacés restent sur le disque."
  count_state; write_status idle "Surveillance arrêtée"; exit 0
fi

[[ -n "$DEST" ]] || { print -u2 "${R}Destination manquante${N} : --dest /Volumes/<disque>/<dossier>"; exit 64; }

if [[ $MODE == watch ]]; then
  need_root; prepare
  [[ "$0" -ef "$INSTALLED" ]] || { cp -f "$0" "$INSTALLED" && chown root:wheel "$INSTALLED" && chmod 755 "$INSTALLED"; }
  # L'assistant n'est installé qu'une fois : le remplacer ferait perdre l'Accès complet
  # au disque que l'utilisateur lui a accordé (l'autorisation suit sa signature).
  if [[ -n "$HELPER_SRC" && -f "$HELPER_SRC" && ! -e "$HELPER" ]]; then
    cp -f "$HELPER_SRC" "$HELPER" && chown root:wheel "$HELPER" && chmod 755 "$HELPER" \
      && say "Assistant installé : ${B}$HELPER${N} — accorde-lui l'Accès complet au disque."
  fi
  req_user="${SUDO_USER:-$(stat -f %Su /dev/console)}"
  REQUEST_DIR="$(dscl . -read "/Users/$req_user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')/Library/Application Support/NotchKiller/requests"
  mkdir -p "$REQUEST_DIR" && chown "$req_user" "$REQUEST_DIR"
  print -r -- "DEST=$DEST" > "$CONF"; print -r -- "REQUEST_DIR=$REQUEST_DIR" >> "$CONF"; chmod 644 "$CONF"
  if [[ -x "$HELPER" ]]; then program="    <string>$HELPER</string>"
  else program="    <string>/bin/zsh</string><string>-f</string><string>$INSTALLED</string>"; fi
  watch=""
  for d in /Library/Audio/Plug-Ins ${(f)"$(plugin_dirs)"} "$REQUEST_DIR"; do [[ -d "$d" ]] && watch+="    <string>${d//&/&amp;}</string>"$'\n'; done
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
$program<string>--quiet</string><string>--daemon</string></array>
  <key>WatchPaths</key><array>
$watch  </array>
  <key>StartInterval</key><integer>3600</integer>
  <key>ThrottleInterval</key><integer>120</integer>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict></plist>
EOF
  chown root:wheel "$PLIST"; chmod 644 "$PLIST"
  launchctl bootout system/$LABEL 2>/dev/null
  launchctl bootstrap system "$PLIST" && say "${G}Surveillance active${N} : tout nouveau plug-in partira sur ${B}$DEST${N} (${SETTLE_MIN} min après son installation, puis toutes les heures)."
  MODE=run
  # Depuis l'app (pas de terminal), le passage est confié au service : un processus root
  # lancé par AppleScript se verrait refuser le disque externe par macOS.
  if [[ ! -t 1 && -x "$HELPER" ]]; then
    print -r -- move > "$REQUEST_DIR/audio-offload.request"; chown "$req_user" "$REQUEST_DIR/audio-offload.request"
    count_state; write_status queued "Passage confié au service"; exit 0
  fi
fi

# ── Déplacement, rapatriement, quarantaine ───────────────────────────────────
[[ $MODE == dry ]] || { need_root; prepare; }
if ! mkdir "$LOCK" 2>/dev/null; then
  if [[ -n "$(find "$LOCK" -maxdepth 0 -mmin +120 2>/dev/null)" ]]; then rm -rf "$LOCK"; mkdir "$LOCK"
  else say "Un passage est déjà en cours — rien à faire."; exit 0; fi
fi
trap 'rm -rf "$LOCK"' EXIT INT TERM

if [[ ! -d "${DEST:h}" ]]; then
  count_state; say "${Y}Disque de destination absent${N} (${DEST:h}) — les plug-ins restent sur le Mac pour l'instant."
  write_status waiting "Disque de destination absent"; exit 0
fi

# macOS (TCC « Volumes amovibles ») refuse l'écriture sur un disque externe à un
# processus root lancé par AppleScript ou par launchd : seul `sudo` depuis un terminal
# autorisé passe. On le vérifie avant de commencer plutôt que d'échouer élément par élément.
if [[ $MODE != dry ]]; then
  probe="${DEST:h}/.nk-write-test-$$"
  if ! mkdir -p "$DEST" 2>/dev/null || ! mkdir "$probe" 2>/dev/null; then
    count_state
    say "${R}macOS refuse l'écriture sur ${DEST:h}${N} (protection « Volumes amovibles »)."
    say "Lance depuis un terminal autorisé : sudo zsh -f \"$0\" --dest \"$DEST\" — rien n'a été touché."
    write_status denied "Écriture refusée par macOS sur le disque externe — lancer depuis un terminal"
    exit 75
  fi
  rmdir "$probe"
fi

MOVED=0 FAILED=0 DEFERRED=0
typeset -a items
for dir in ${(f)"$(plugin_dirs)"}; do
  for p in "$dir"/*; do
    [[ "${p:t}" == .* ]] && continue
    case $MODE in
      restore)    [[ -L "$p" && "$(readlink "$p")" == "$DEST"/* ]] && is_plugin "$p" && items+=("$p") ;;
      quarantine) is_plugin "$p" || items+=("$p") ;;
      *)          [[ ! -L "$p" ]] && is_plugin "$p" && items+=("$p") ;;
    esac
  done
done
for p in ${(f)"$(vendor_dirs)"}; do
  case $MODE in
    restore)    [[ -L "$p" && "$(readlink "$p")" == "$DEST"/* ]] && items+=("$p") ;;
    quarantine) ;;
    *)          [[ -L "$p" ]] || items+=("$p") ;;
  esac
done
total=${#items}
count_state
case $MODE in restore) verb="rapatrier" title="Rapatriement" ;; quarantine) verb="mettre en quarantaine" title="Quarantaine" ;; *) verb="déplacer" title="Déplacement" ;; esac

if (( total == 0 )); then
  say "${G}✓${N} Rien à $verb — $ON_DEST plug-in(s) sur le disque, $ON_MAC sur le Mac."
  [[ $MODE != quarantine ]] && (( INTRUDERS )) && say "${Y}!${N} $INTRUDERS fichier(s) qui ne sont pas des plug-ins traînent dans les dossiers : --quarantine pour les sortir."
  write_status idle "À jour"; exit 0
fi

(( QUIET )) || print "${B}$title de $total élément(s)${N} ${D}→ $([[ $MODE == restore ]] && print "Mac" || print "$DEST")${N}\n"
log "── début ($MODE, $total éléments, dest=$DEST)"
if [[ $MODE == run || $MODE == restore ]] && daw_running; then
  say "${Y}Un logiciel audio est ouvert${N} ($(pgrep -xl "$DAWS" | awk '{print $2}' | sort -u | paste -sd, -)) — ferme-le, report au prochain passage."
  DEFERRED=$total; write_status deferred "Logiciel audio ouvert, report"; exit 0
fi
if [[ $MODE == run ]] && installing; then
  say "${Y}Une installation est en cours${N} — report au prochain passage."
  DEFERRED=$total; write_status deferred "Installation en cours, report"; exit 0
fi

QUAR="${DEST:h}/Hors-plug-ins-quarantaine/$(date +%F)"
i=0
for p in $items; do
  (( i++ ))
  dir="${p:h}"; kind=$(kind_of "$dir"); name="${p:t}"
  prefix=$(printf "${D}[%3d/%d]${N} ${C}%-10s${N} %s" $i $total "$kind" "$name")
  write_status running "$title" $i $total "$kind/$name"

  case $MODE in
  restore)
    src="$(readlink "$p")"
    [[ -e "$src" ]] || { say "$prefix  ${R}✗ introuvable sur le disque${N}"; (( FAILED++ )); continue; }
    tmp="$p.nk-restore"; rm -rf "$tmp"
    if ditto "$src" "$tmp" && [[ "$(fingerprint "$src")" == "$(fingerprint "$tmp")" ]]; then
      rm -f "$p" && mv "$tmp" "$p" && rm -rf "$src" && { say "$prefix  ${G}✓ rapatrié${N}"; (( MOVED++ )); }
    else rm -rf "$tmp"; say "$prefix  ${R}✗ échec, laissé sur le disque${N}"; (( FAILED++ )); fi
    ;;
  quarantine)
    q="$QUAR/$kind/$name"; mkdir -p "${q:h}"
    if [[ -L "$p" ]]; then src="$(readlink "$p")"
      if [[ ! -e "$src" ]]; then rm -f "$p"; say "$prefix  ${G}✓ lien mort retiré${N}"; (( MOVED++ ))   # tube/socket jamais copié
      elif mv "$src" "$q"; then rm -f "$p"; say "$prefix  ${G}✓ sorti${N}"; (( MOVED++ ))
      else say "$prefix  ${R}✗ échec${N}"; (( FAILED++ )); fi
    elif ditto "$p" "$q" && [[ "$(fingerprint "$p")" == "$(fingerprint "$q")" ]]; then
      rm -rf "$p"; say "$prefix  ${G}✓ sorti${N}"; (( MOVED++ ))
    else rm -rf "$q"; say "$prefix  ${R}✗ échec, laissé en place${N}"; (( FAILED++ )); fi
    ;;
  *)
    kb=$(size_kb "$p")
    if [[ -n "$(find "$p" -mmin -$SETTLE_MIN -print -quit 2>/dev/null)" ]]; then
      say "$prefix  ${Y}… modifié il y a moins de $SETTLE_MIN min, reporté${N}"; (( DEFERRED++ )); continue
    fi
    if [[ $MODE == dry ]]; then say "$prefix  $(human $kb)  ${D}serait déplacé${N}"; continue; fi
    target="$(target_of "$p")"
    if [[ -e "$target" ]]; then
      # Même contenu déjà sur le disque (passage interrompu) : on garde la copie existante.
      if [[ "$(fingerprint "$p")" == "$(fingerprint "$target")" ]]; then
        rm -rf "$p" && ln -s "$target" "$p" && { say "$prefix  ${G}✓ déjà copié, lien posé${N}"; (( MOVED++ )); }
        continue
      fi
      # Copie incomplète ou périmée : l'original du Mac fait foi, l'ancienne copie est écartée (pas supprimée).
      stale="$target.ancienne-copie-$(date +%Y%m%d-%H%M%S)"
      mv "$target" "$stale" && say "$prefix  ${Y}ancienne copie différente écartée → ${stale:t}${N}"
    fi
    mkdir -p "${target:h}"
    if ditto "$p" "$target" && [[ "$(fingerprint "$p")" == "$(fingerprint "$target")" ]]; then
      rm -rf "$p" && ln -s "$target" "$p" && { say "$prefix  $(human $kb)  ${G}✓ déplacé${N}"; (( MOVED++ )); }
    else
      rm -rf "$target"; say "$prefix  ${R}✗ échec de copie, laissé sur le Mac${N}"; (( FAILED++ ))
    fi
    ;;
  esac
done

[[ $MODE == run || $MODE == restore ]] && (( MOVED )) && killall -9 AudioComponentRegistrar 2>/dev/null   # relit les Audio Units
count_state
case $MODE in
  restore)    summary="$MOVED rapatrié(s), $FAILED en échec" ;;
  quarantine) summary="$MOVED sorti(s) vers $QUAR, $FAILED en échec" ;;
  dry)        summary="simulation — $(( total - DEFERRED )) à déplacer maintenant, $DEFERRED reporté(s)" ;;
  *)          summary="$MOVED déplacé(s), $DEFERRED reporté(s), $FAILED en échec" ;;
esac
(( QUIET )) || print "\n${B}Bilan${N} : $summary\n       ${B}$ON_MAC${N} plug-in(s) sur le Mac ($(human $MAC_KB)), ${B}$ON_DEST${N} sur le disque$( (( INTRUDERS )) && print ", ${Y}$INTRUDERS intrus${N}")\n       ${B}$SUP_MAC${N} dossier(s) de données sur le Mac ($(human $SUP_KB)), ${B}$SUP_DEST${N} sur le disque."
log "── fin : $summary"
write_status idle "$summary"
exit $(( FAILED > 0 ))
"""#

    /// Entretien hebdomadaire lancé par le LaunchAgent de la page Nettoyage.
    static let maintenance = #"""
#!/bin/zsh -f
# nk-maintenance — entretien hebdomadaire du disque, lancé par un LaunchAgent.
#   nk-maintenance.sh [--offload-root DIR] [--min-free GO]
# Purge ce qui se régénère, puis prévient si l'espace libre baisse ou si le disque
# externe qui porte les caches et plug-ins est débranché.
# Généré par NotchKiller (Système › Nettoyage) — ne pas modifier à la main.
setopt null_glob
SUPPORT="$HOME/Library/Application Support/NotchKiller"
LOGDIR="$HOME/Library/Logs/NotchKiller"
LOG="$LOGDIR/maintenance.log"
STATUS="$SUPPORT/maintenance-status.json"
ROOT="" MIN_FREE=30
while (( $# )); do
  case "$1" in
    --offload-root) ROOT="$2"; shift ;;
    --min-free) MIN_FREE="$2"; shift ;;
  esac; shift
done

mkdir -p "$LOGDIR" "$SUPPORT"
[[ -f "$LOG" ]] && (( $(stat -f %z "$LOG") > 1048576 )) && mv -f "$LOG" "$LOG.1"
exec >> "$LOG" 2>&1
free_kb() { df -k /System/Volumes/Data | awk 'NR==2{print $4}'; }
notify() { /usr/bin/osascript -e "display notification \"${1//\"/\'}\" with title \"${2//\"/\'}\""; }

before=$(free_kb)
print "== $(date '+%F %T') début"

tmp="$(getconf DARWIN_USER_TEMP_DIR)"; n=0
for p in "$tmp"/*; do
  [[ -O "$p" && -n "$(find "$p" -maxdepth 0 -mtime +3 2>/dev/null)" ]] && rm -rf "$p" && (( n++ ))
done
print "temporaires de plus de 3 jours : $n supprimé(s)"

/usr/bin/xcrun simctl delete unavailable 2>/dev/null && print "simulateurs orphelins : supprimés"

brew=/opt/homebrew/bin/brew; [[ -x $brew ]] || brew=/usr/local/bin/brew
[[ -x $brew ]] && $brew cleanup -s --prune=7 >/dev/null 2>&1 && print "Homebrew : anciennes versions et téléchargements purgés"

updates=("$HOME"/Library/Caches/*.ShipIt)
(( ${#updates} )) && rm -rf $updates && print "mises à jour d'apps en attente : ${#updates} supprimée(s)"

after=$(free_kb)
freed=$(( after > before ? after - before : 0 ))
gb=$(( after / 1048576 ))
print "libre : $gb Go (+$(( freed / 1024 )) Mo)"
(( gb < MIN_FREE )) && notify "Plus que $gb Go libres sur le Mac" "Disque presque plein"

mounted=true
if [[ -n "$ROOT" && ! -d "$ROOT" ]]; then
  mounted=false
  notify "Disque externe débranché : les caches et plug-ins qui y ont été déplacés sont indisponibles." "Disque externe absent"
fi

/usr/bin/python3 - "$STATUS" "$gb" "$(( freed / 1024 ))" "$mounted" <<'PY'
import json, os, sys, time
p = sys.argv[1]
json.dump(dict(lastRun=int(time.time()), freeGB=int(sys.argv[2]), freedMB=int(sys.argv[3]),
               offloadMounted=sys.argv[4] == "true"), open(p + ".tmp", "w"))
os.replace(p + ".tmp", p)
PY
print "== fin"
"""#

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchKiller/scripts", isDirectory: true)
    }

    /// Écrit les scripts s'ils manquent ou diffèrent ; renvoie le dossier.
    @discardableResult
    nonisolated static func install() -> URL {
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, body) in [(audioOffloadName, audioOffload), (maintenanceName, maintenance)] {
            let url = dir.appendingPathComponent(name)
            if (try? String(contentsOf: url, encoding: .utf8)) != body {
                try? body.write(to: url, atomically: true, encoding: .utf8)
            }
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return dir
    }
}
