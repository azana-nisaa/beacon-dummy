#!/usr/bin/env bash
# Beacon Dummy — install on a Linux VM as a systemd service.
#   sudo ./setup.sh
#   sudo ./setup.sh --port 80
#   sudo ./setup.sh --role dr --name "Customer DR Canary"
#   sudo ./setup.sh --uninstall
set -euo pipefail

APP_NAME="beacon-dummy"
INSTALL_DIR="/opt/beacon-dummy"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
ENV_FILE="/etc/default/${APP_NAME}"
SERVICE_USER="beacon"
PORT="${BEACON_PORT:-8080}"
ROLE="${BEACON_ROLE:-dummy}"
SITE_NAME="${BEACON_SITE_NAME:-Beacon Canary}"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
UNINSTALL=0

usage() {
  cat <<EOF
Beacon Dummy setup

Usage:
  sudo ./setup.sh [options]
  ./setup.sh              # no root: run in the foreground on :8080

Options:
  --port <n>          listen port (default: 8080)
  --role <name>       shown on the page, e.g. dummy / primary / dr
  --name <title>      site title shown on the page
  --uninstall         stop service and remove installed files
  -h, --help          show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --name) SITE_NAME="$2"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "This action needs root. Re-run with sudo."
    exit 1
  fi
}

detect_pkg() {
  if command -v apt-get >/dev/null 2>&1; then echo apt
  elif command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v yum >/dev/null 2>&1; then echo yum
  elif command -v zypper >/dev/null 2>&1; then echo zypper
  else echo none
  fi
}

install_python() {
  if command -v python3 >/dev/null 2>&1; then
    return
  fi
  echo "python3 not found — installing..."
  case "$(detect_pkg)" in
    apt) apt-get update -y && apt-get install -y python3 ;;
    dnf) dnf install -y python3 ;;
    yum) yum install -y python3 ;;
    zypper) zypper --non-interactive install python3 ;;
    *) echo "Could not install python3 automatically. Install it, then re-run."; exit 1 ;;
  esac
}

uninstall_app() {
  need_root
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "${APP_NAME}" 2>/dev/null || true
    systemctl disable "${APP_NAME}" 2>/dev/null || true
  fi
  rm -f "${SERVICE_FILE}" "${ENV_FILE}"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
  fi
  rm -rf "${INSTALL_DIR}"
  if id "${SERVICE_USER}" >/dev/null 2>&1; then
    userdel "${SERVICE_USER}" 2>/dev/null || true
  fi
  echo "Removed ${APP_NAME}."
}

if [[ "${UNINSTALL}" -eq 1 ]]; then
  uninstall_app
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "No sudo detected — starting in the foreground."
  echo "For a lasting install on this VM:  sudo ./setup.sh"
  echo
  export BEACON_PORT="${PORT}"
  export BEACON_ROLE="${ROLE}"
  export BEACON_SITE_NAME="${SITE_NAME}"
  exec "${SRC_DIR}/start.sh"
fi

install_python

if ! id "${SERVICE_USER}" >/dev/null 2>&1; then
  useradd --system --home "${INSTALL_DIR}" --shell /usr/sbin/nologin "${SERVICE_USER}" 2>/dev/null \
    || useradd --system --home "${INSTALL_DIR}" --shell /sbin/nologin "${SERVICE_USER}"
fi

mkdir -p "${INSTALL_DIR}"
rsync_ok=0
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude '.git' \
    --exclude '.env' \
    --exclude '__pycache__' \
    "${SRC_DIR}/" "${INSTALL_DIR}/"
  rsync_ok=1
fi
if [[ "${rsync_ok}" -eq 0 ]]; then
  find "${INSTALL_DIR}" -mindepth 1 -maxdepth 1 ! -name '.env' -exec rm -rf {} +
  cp -a "${SRC_DIR}/." "${INSTALL_DIR}/"
  rm -rf "${INSTALL_DIR}/.git"
fi

chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"
chmod 755 "${INSTALL_DIR}/start.sh" "${INSTALL_DIR}/setup.sh" "${INSTALL_DIR}/server.py"

cat > "${ENV_FILE}" <<EOF
BEACON_HOST=0.0.0.0
BEACON_PORT=${PORT}
BEACON_ROLE=${ROLE}
BEACON_SITE_NAME=${SITE_NAME}
EOF
chmod 644 "${ENV_FILE}"

PYTHON_BIN="$(command -v python3)"
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Beacon Dummy DR canary
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
EnvironmentFile=-${ENV_FILE}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${PYTHON_BIN} ${INSTALL_DIR}/server.py
Restart=always
RestartSec=2
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
  systemctl enable --now "${APP_NAME}"
  sleep 1
  systemctl --no-pager --full status "${APP_NAME}" || true
else
  echo "systemd not found. Start manually:"
  echo "  sudo -u ${SERVICE_USER} ${INSTALL_DIR}/start.sh"
fi

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
IP="${IP:-127.0.0.1}"
echo
echo "Beacon is installed."
echo "  page    http://${IP}:${PORT}/"
echo "  health  http://${IP}:${PORT}/health"
echo "  status  http://${IP}:${PORT}/api/status"
echo
echo "Change title/role later in ${ENV_FILE} then:  sudo systemctl restart ${APP_NAME}"
echo "Optional nginx sample: ${INSTALL_DIR}/nginx.conf.example"
echo "Uninstall:  sudo ${INSTALL_DIR}/setup.sh --uninstall"
