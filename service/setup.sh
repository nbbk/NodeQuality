#!/usr/bin/env bash
set -euo pipefail
command -v python3 >/dev/null || { echo '需要 Python 3；请先安装后重试。' >&2; exit 1; }
exec python3 "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/setup.py" "$@"
