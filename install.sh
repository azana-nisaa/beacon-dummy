#!/usr/bin/env bash
# Beacon Dummy installer.
# One of these is enough on the dummy VM:
#   sudo ./install.sh
#   curl -fsSL https://raw.githubusercontent.com/azana-nisaa/beacon-dummy/main/install.sh | sudo bash
set -euo pipefail

APP_NAME="beacon-dummy"
INSTALL_DIR="/opt/beacon-dummy"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
CRON_FILE="/etc/cron.d/${APP_NAME}"
ENV_FILE="/etc/default/${APP_NAME}"
SERVICE_USER="beacon"
REPO_TARBALL="https://github.com/azana-nisaa/beacon-dummy/archive/refs/heads/main.tar.gz"
PORT=""
ROLE=""
SITE_NAME=""
PORT_SET=0
ROLE_SET=0
NAME_SET=0
UNINSTALL=0

usage() {
  cat <<EOF
Beacon Dummy installer

  sudo ./install.sh
  sudo ./install.sh --name "Customer DR Canary"
  sudo ./install.sh --uninstall

After this finishes, the site is running and it comes back after reboot.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; PORT_SET=1; shift 2 ;;
    --role) ROLE="$2"; ROLE_SET=1; shift 2 ;;
    --name) SITE_NAME="$2"; NAME_SET=1; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

self_path() {
  local src="${BASH_SOURCE[0]:-}"
  case "$src" in
    ""|-|/dev/fd/*|/proc/self/fd/*) echo ""; return ;;
  esac
  if [[ -f "$src" ]]; then
    cd "$(dirname "$src")" && pwd
  else
    echo ""
  fi
}

SRC_DIR="$(self_path)"

is_root() { [[ "${EUID}" -eq 0 ]]; }

reexec_sudo() {
  if is_root; then
    return
  fi
  if [[ -z "$SRC_DIR" ]]; then
    echo "Run this as root:"
    echo "  curl -fsSL https://raw.githubusercontent.com/azana-nisaa/beacon-dummy/main/install.sh | sudo bash"
    exit 1
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    echo "Need root. Re-run:  sudo $SRC_DIR/install.sh"
    exit 1
  fi
  exec sudo -- "$SRC_DIR/install.sh" "$@"
}

detect_pkg() {
  if command -v apt-get >/dev/null 2>&1; then echo apt
  elif command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v yum >/dev/null 2>&1; then echo yum
  elif command -v zypper >/dev/null 2>&1; then echo zypper
  else echo none
  fi
}

pkg_install() {
  case "$(detect_pkg)" in
    apt) apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf) dnf install -y "$@" ;;
    yum) yum install -y "$@" ;;
    zypper) zypper --non-interactive install "$@" ;;
    *) echo "Could not install: $*"; return 1 ;;
  esac
}

ensure_python() {
  if command -v python3 >/dev/null 2>&1; then
    return
  fi
  echo "Installing python3..."
  pkg_install python3
  command -v python3 >/dev/null 2>&1
}

fetch_source() {
  if [[ -n "$SRC_DIR" && -f "$SRC_DIR/server.py" && -d "$SRC_DIR/static" ]]; then
    return
  fi
  echo "Downloading Beacon Dummy..."
  command -v tar >/dev/null 2>&1 || pkg_install tar
  local tmp
  tmp="$(mktemp -d)"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO_TARBALL" -o "$tmp/src.tgz"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp/src.tgz" "$REPO_TARBALL"
  else
    pkg_install curl
    curl -fsSL "$REPO_TARBALL" -o "$tmp/src.tgz"
  fi
  tar -xzf "$tmp/src.tgz" -C "$tmp"
  SRC_DIR="$(dirname "$(find "$tmp" -maxdepth 2 -type f -name server.py | head -n 1)")"
  if [[ ! -f "$SRC_DIR/server.py" ]]; then
    echo "Download failed. Clone the repo and run sudo ./install.sh from there."
    exit 1
  fi
}

load_existing_env() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    source "$ENV_FILE"
    set +a
  fi
  if [[ "$PORT_SET" -eq 0 ]]; then
    PORT=80
  fi
  if [[ "$ROLE_SET" -eq 0 ]]; then
    ROLE="${BEACON_ROLE:-dummy}"
  fi
  if [[ "$NAME_SET" -eq 0 ]]; then
    SITE_NAME="${BEACON_SITE_NAME:-Beacon Canary}"
  fi
}

port_busy() {
  local p="$1"
  python3 - "$p" <<'PY'
import socket, sys
port = int(sys.argv[1])
s = socket.socket()
try:
    s.bind(("0.0.0.0", port))
except OSError:
    sys.exit(0)
finally:
    s.close()
sys.exit(1)
PY
}

ours_active() {
  command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$APP_NAME"
}

pick_port() {
  if ours_active; then
    return
  fi
  if port_busy "$PORT"; then
    echo "Port ${PORT} is already in use."
    echo "Stop the other web server, then re-run the installer:"
    echo "  sudo systemctl stop nginx apache2 httpd 2>/dev/null || true"
    echo "  sudo ./install.sh"
    exit 1
  fi
}

ensure_user() {
  if id "$SERVICE_USER" >/dev/null 2>&1; then
    return
  fi
  if command -v useradd >/dev/null 2>&1; then
    useradd --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin "$SERVICE_USER" 2>/dev/null \
      || useradd --system --home "$INSTALL_DIR" --shell /sbin/nologin "$SERVICE_USER"
  else
    adduser -S -H -h "$INSTALL_DIR" -s /sbin/nologin "$SERVICE_USER"
  fi
}

copy_app() {
  mkdir -p "$INSTALL_DIR"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude '.git' \
      --exclude '.env' \
      --exclude '__pycache__' \
      "$SRC_DIR/" "$INSTALL_DIR/"
  else
    find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 ! -name '.env' -exec rm -rf {} +
    cp -a "$SRC_DIR/." "$INSTALL_DIR/"
    rm -rf "$INSTALL_DIR/.git"
  fi
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR"
  chmod 755 "$INSTALL_DIR"
  chmod 755 "$INSTALL_DIR"/server.py "$INSTALL_DIR"/install.sh "$INSTALL_DIR"/setup.sh "$INSTALL_DIR"/start.sh
}

write_env() {
  cat > "$ENV_FILE" <<EOF
BEACON_HOST=0.0.0.0
BEACON_PORT=${PORT}
BEACON_ROLE='${ROLE}'
BEACON_SITE_NAME='${SITE_NAME}'
EOF
  chmod 644 "$ENV_FILE"
}

write_run_helper() {
  cat > "$INSTALL_DIR/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
set -a
# shellcheck disable=SC1091
source "$ENV_FILE"
set +a
cd "$INSTALL_DIR"
exec "$(command -v python3)" "$INSTALL_DIR/server.py"
EOF
  chmod 755 "$INSTALL_DIR/run.sh"
  chown "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR/run.sh"
}

write_unit() {
  local python_bin caps=""
  python_bin="$(command -v python3)"
  if [[ "$PORT" -lt 1024 ]]; then
    caps="AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE"
  else
    caps="CapabilityBoundingSet="
  fi
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Beacon Dummy DR canary
After=network-online.target network.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
EnvironmentFile=-${ENV_FILE}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${python_bin} ${INSTALL_DIR}/server.py
Restart=always
RestartSec=2
KillSignal=SIGTERM
TimeoutStopSec=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
PrivateDevices=true
LockPersonality=true
RestrictRealtime=true
RestrictSUIDSGID=true
RestrictNamespaces=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
SystemCallArchitectures=native
${caps}

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$SERVICE_FILE"
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
    ufw allow "${PORT}/tcp" >/dev/null || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -qi running; then
    firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null || true
    firewall-cmd --reload >/dev/null || true
  fi
}

start_systemd() {
  systemctl daemon-reload
  systemctl enable "$APP_NAME"
  systemctl restart "$APP_NAME"
}

start_cron_fallback() {
  echo "systemd not found. Using cron so it still starts on reboot."
  cat > "$CRON_FILE" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
@reboot ${SERVICE_USER} ${INSTALL_DIR}/run.sh
EOF
  chmod 644 "$CRON_FILE"
  if [[ "$PORT" -lt 1024 ]] && command -v setcap >/dev/null 2>&1; then
    setcap cap_net_bind_service=+ep "$(readlink -f "$(command -v python3)")" || true
  fi
  pkill -f "${INSTALL_DIR}/server.py" 2>/dev/null || true
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$SERVICE_USER" -- "$INSTALL_DIR/run.sh" >/var/log/beacon-dummy.log 2>&1 &
  elif command -v sudo >/dev/null 2>&1; then
    sudo -u "$SERVICE_USER" "$INSTALL_DIR/run.sh" >/var/log/beacon-dummy.log 2>&1 &
  else
    su -s /bin/bash -c "$INSTALL_DIR/run.sh" "$SERVICE_USER" >/var/log/beacon-dummy.log 2>&1 &
  fi
}

wait_health() {
  python3 - "$PORT" <<'PY'
import sys, time, urllib.request
port = sys.argv[1]
url = "http://127.0.0.1:%s/health" % port
for _ in range(40):
    try:
        with urllib.request.urlopen(url, timeout=1) as res:
            if res.status == 200:
                sys.exit(0)
    except Exception:
        time.sleep(0.25)
print("Service did not become healthy on port %s" % port, file=sys.stderr)
sys.exit(1)
PY
}

detect_ip() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  fi
  if [[ -z "$ip" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  echo "${ip:-127.0.0.1}"
}

uninstall_app() {
  if ! is_root; then
    echo "Uninstall needs root. Re-run with sudo."
    exit 1
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$APP_NAME" 2>/dev/null || true
    systemctl disable "$APP_NAME" 2>/dev/null || true
  fi
  pkill -f "${INSTALL_DIR}/server.py" 2>/dev/null || true
  rm -f "$SERVICE_FILE" "$ENV_FILE" "$CRON_FILE"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
  fi
  rm -rf "$INSTALL_DIR"
  if id "$SERVICE_USER" >/dev/null 2>&1; then
    userdel "$SERVICE_USER" 2>/dev/null || true
  fi
  echo "Removed ${APP_NAME}."
}

print_done() {
  local ip
  ip="$(detect_ip)"
  local url="http://${ip}/"
  if [[ "$PORT" != "80" ]]; then
    url="http://${ip}:${PORT}/"
  fi
  echo
  echo "Beacon is up and enabled on boot."
  echo "  page    ${url}"
  echo "  health  ${url%/}/health"
  echo
  if command -v systemctl >/dev/null 2>&1; then
    echo "  logs    journalctl -u ${APP_NAME} -f"
    echo "  enable  $(systemctl is-enabled "$APP_NAME" 2>/dev/null || echo unknown)"
  fi
}

reexec_sudo "$@"

if [[ "$UNINSTALL" -eq 1 ]]; then
  uninstall_app
  exit 0
fi

fetch_source
ensure_python
load_existing_env
pick_port
ensure_user
copy_app
write_env
write_run_helper
open_firewall

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  write_unit
  start_systemd
else
  start_cron_fallback
fi

if ! wait_health; then
  echo "Install finished, but health check failed. Last logs:"
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -u "$APP_NAME" -n 40 --no-pager || true
  else
    tail -n 40 /var/log/beacon-dummy.log 2>/dev/null || true
  fi
  exit 1
fi

print_done
