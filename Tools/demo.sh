#!/bin/bash
# Pilote une instance lancée en mode démo (`NotchKiller --demo`).
#   Tools/demo.sh open <onglet> [sous-page]   ex. open dev ports
#   Tools/demo.sh close
#   Tools/demo.sh bar <claude|music|calendar>  fige le bandeau fermé
#   Tools/demo.sh done                         tiroir « Claude a fini »
set -euo pipefail
[[ $# -ge 1 ]] || { echo "usage: $0 open <onglet> [sous-page] | close | done" >&2; exit 64; }
osascript -l JavaScript - "$*" <<'JXA' >/dev/null
ObjC.import('Foundation')
function run(argv) {
  $.NSDistributedNotificationCenter.defaultCenter
    .postNotificationNameObjectUserInfoDeliverImmediately(
      'io.github.lechar111.notchkiller.demo', argv[0], $(), true)
}
JXA
