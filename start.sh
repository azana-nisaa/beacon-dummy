#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required. Install it, or run: sudo ./setup.sh"
  exit 1
fi

exec python3 server.py
