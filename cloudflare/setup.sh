#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
command -v node >/dev/null || { printf '%s\n' '需要 Node.js 22/24 LTS，请先安装后重新运行。' >&2; exit 1; }
exec node scripts/setup.mjs "$@"
