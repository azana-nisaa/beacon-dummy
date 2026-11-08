#!/usr/bin/env bash
# Safe to run anytime. If Beacon is already up, this just prints the URL.
# If it is not installed yet, this runs the installer.
set -euo pipefail
cd "$(dirname "$0")"
exec ./install.sh "$@"
