#!/usr/bin/env bash
# NB NodeQuality guided entry point. Never installs host software automatically.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
usage() {
  cat <<'TXT'
NB NodeQuality — guided setup and use
  bash setup.sh docker [options]   Configure/start your Docker report service
  bash setup.sh cloudflare [options]  Configure Cloudflare/GitHub auto-build setup
  bash setup.sh run [--config private-client.env] [CLI options]
  bash setup.sh run --share --consent-upload   Explicit noninteractive raw sharing
No arguments: choose interactively. No deployment occurs without confirmation.
Existing Docker/Node/Python prerequisites are checked, not silently installed.
TXT
}
if (( $# == 0 )); then
  [[ -t 0 ]] || { usage; exit 2; }
  printf '1) Docker service  2) Cloudflare service  3) Run benchmark (root required)\n'
  read -r -p 'Choose 1/2/3 (anything else cancels): ' choice
  case "$choice" in 1) set -- docker;; 2) set -- cloudflare;; 3) set -- run;; *) exit 0;; esac
fi
command="$1"; shift
case "$command" in
  docker) exec bash "$ROOT/service/setup.sh" "$@" ;;
  cloudflare|cf) exec bash "$ROOT/cloudflare/setup.sh" "$@" ;;
  run) command -v python3 >/dev/null || { echo 'Python3 required for guided run; use bash NodeQuality.sh for local-only CLI.' >&2; exit 1; }; exec python3 "$ROOT/scripts/run.py" "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
