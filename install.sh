#!/usr/bin/env bash
#   sudo ./uninstall.sh
#   sudo ./install.sh
#   curl -fsSL https://raw.githubusercontent.com/azana-nisaa/beacon-dummy/main/install.sh | sudo bash
set -euo pipefail

APP_NAME="beacon-dummy"
INSTALL_DIR="/opt/beacon-dummy"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
DROPIN_DIR="/etc/systemd/system/${APP_NAME}.service.d"
ENV_FILE="/etc/default/${APP_NAME}"
CRON_FILE="/etc/cron.d/${APP_NAME}"
SYSCTL_FILE="/etc/sysctl.d/80-beacon-dummy.conf"
LOG_FILE="/var/log/beacon-dummy.log"
STATE_DIR="/var/lib/beacon-dummy"
SERVICE_USER="beacon"
REPO_TARBALL="https://github.com/azana-nisaa/beacon-dummy/archive/refs/heads/main.tar.gz"
PORT=80
ROLE="dummy"
SITE_NAME="Beacon Canary"
UNINSTALL=0
ROLE_SET=0
NAME_SET=0

self_dir() {
  local src="${BASH_SOURCE[0]:-}"
  case "$src" in
    ""|-|/dev/fd/*|/proc/self/fd/*) echo ""; return ;;
  esac
  [[ -f "$src" ]] && cd "$(dirname "$src")" && pwd
}

SRC_DIR="$(self_dir)"

if [[ "${EUID}" -ne 0 ]]; then
  if [[ -z "$SRC_DIR" ]]; then
    echo "Run: curl -fsSL https://raw.githubusercontent.com/azana-nisaa/beacon-dummy/main/install.sh | sudo bash" >&2
    exit 1
  fi
  exec sudo -- "$SRC_DIR/install.sh" "$@"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="$2"; ROLE_SET=1; shift 2 ;;
    --name) SITE_NAME="$2"; NAME_SET=1; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)
      echo "Usage:"
      echo "  sudo ./uninstall.sh"
      echo "  sudo ./install.sh [--name TITLE] [--role dummy]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

pkg_kind() {
  command -v apt-get >/dev/null && { echo apt; return; }
  command -v dnf >/dev/null && { echo dnf; return; }
  command -v yum >/dev/null && { echo yum; return; }
  command -v zypper >/dev/null && { echo zypper; return; }
  echo none
}

pkg_install() {
  case "$(pkg_kind)" in
    apt) apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf) dnf install -y "$@" ;;
    yum) yum install -y "$@" ;;
    zypper) zypper --non-interactive install "$@" ;;
    *) echo "Cannot install: $*" >&2; return 1 ;;
  esac
}

port_users() {
  if command -v ss >/dev/null; then
    ss -lntp 2>/dev/null | grep -E ":${PORT}\\b" || true
  elif command -v lsof >/dev/null; then
    lsof -iTCP:"$PORT" -sTCP:LISTEN || true
  fi
}

port_free() {
  python3 - "$PORT" <<'PY'
import socket, sys
s = socket.socket()
try:
    s.bind(("0.0.0.0", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    s.close()
sys.exit(0)
PY
}

purge_beacon() {
  echo "Cleaning previous Beacon Dummy files and processes..."
  if command -v systemctl >/dev/null; then
    systemctl disable --now "$APP_NAME" 2>/dev/null || true
    systemctl stop "$APP_NAME" 2>/dev/null || true
  fi
  pkill -f "/opt/beacon-dummy/server.py" 2>/dev/null || true
  pkill -f "beacon-dummy/server.py" 2>/dev/null || true
  pkill -f "beacon-dummy.*server.py" 2>/dev/null || true
  if command -v fuser >/dev/null; then
    fuser -k 80/tcp 2>/dev/null || true
    fuser -k 8080/tcp 2>/dev/null || true
  fi
  rm -rf "$INSTALL_DIR" "$DROPIN_DIR" "$STATE_DIR"
  rm -f "$SERVICE_FILE" "$ENV_FILE" "$CRON_FILE" "$SYSCTL_FILE" "$LOG_FILE"
  if command -v systemctl >/dev/null; then
    systemctl daemon-reload 2>/dev/null || true
    systemctl reset-failed "$APP_NAME" 2>/dev/null || true
  fi
  userdel "$SERVICE_USER" 2>/dev/null || true
  groupdel "$SERVICE_USER" 2>/dev/null || true
  if [[ -w /proc/sys/net/ipv4/ip_unprivileged_port_start ]]; then
    echo 1024 > /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || true
  fi
  sleep 0.4
}

free_port_80() {
  if port_free; then
    return
  fi
  echo "Port 80 is busy. Stopping the process that holds it..."
  port_users
  if command -v systemctl >/dev/null; then
    for svc in nginx apache2 httpd lighttpd; do
      systemctl stop "$svc" 2>/dev/null || true
    done
  fi
  command -v fuser >/dev/null && fuser -k "${PORT}/tcp" 2>/dev/null || true
  sleep 0.4
}

precheck() {
  echo "Precheck..."
  command -v python3 >/dev/null || { echo "python3 missing"; return 1; }
  if [[ -e "$SERVICE_FILE" || -d "$INSTALL_DIR" || -f "$ENV_FILE" ]]; then
    echo "Beacon leftovers are still present."
    return 1
  fi
  if pgrep -f "beacon-dummy.*server.py" >/dev/null 2>&1; then
    echo "A Beacon process is still running."
    return 1
  fi
  if ! port_free; then
    echo "Port 80 is still in use:"
    port_users
    return 1
  fi
  echo "Precheck passed. Port 80 is free."
}

open_firewall() {
  local p
  for p in 80 8080; do
    if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -qi "Status: active"; then
      ufw allow "${p}/tcp" >/dev/null || true
    fi
    if command -v iptables >/dev/null; then
      iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null \
        || iptables -I INPUT 1 -p tcp --dport "$p" -j ACCEPT || true
    fi
  done
  if command -v firewall-cmd >/dev/null && firewall-cmd --state 2>/dev/null | grep -qi running; then
    local zone
    for zone in $(firewall-cmd --get-zones 2>/dev/null); do
      firewall-cmd --permanent --zone="$zone" --add-port=80/tcp >/dev/null 2>&1 || true
      firewall-cmd --permanent --zone="$zone" --add-port=8080/tcp >/dev/null 2>&1 || true
    done
    firewall-cmd --reload >/dev/null || true
  fi
}

detect_ip() {
  local ip=""
  command -v ip >/dev/null && ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  [[ -z "$ip" ]] && ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  echo "${ip:-127.0.0.1}"
}

beacon_ok() {
  python3 - "$1" <<'PY'
import sys, urllib.request
url = "http://%s/health" % sys.argv[1]
try:
    res = urllib.request.urlopen(url, timeout=2)
    sys.exit(0 if res.status == 200 and res.headers.get("X-Beacon") == "alive" else 1)
except Exception:
    sys.exit(1)
PY
}

wait_health() {
  local i
  for i in $(seq 1 40); do
    beacon_ok "127.0.0.1" && return 0
    beacon_ok "127.0.0.1:8080" && return 0
    sleep 0.25
  done
  return 1
}

fetch_source() {
  [[ -n "$SRC_DIR" && -f "$SRC_DIR/server.py" && -d "$SRC_DIR/static" ]] && return
  echo "Downloading Beacon Dummy..."
  command -v tar >/dev/null || pkg_install tar
  command -v curl >/dev/null || pkg_install curl
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL "$REPO_TARBALL" -o "$tmp/src.tgz"
  tar -xzf "$tmp/src.tgz" -C "$tmp"
  SRC_DIR="$(dirname "$(find "$tmp" -maxdepth 2 -name server.py | head -n 1)")"
  [[ -f "$SRC_DIR/server.py" ]] || { echo "Download failed." >&2; exit 1; }
}

copy_app() {
  mkdir -p "$INSTALL_DIR"
  if command -v rsync >/dev/null; then
    rsync -a --delete --exclude '.git' --exclude '.env' --exclude '__pycache__' "$SRC_DIR/" "$INSTALL_DIR/"
  else
    cp -a "$SRC_DIR/." "$INSTALL_DIR/"
    rm -rf "$INSTALL_DIR/.git"
  fi
  chmod 755 "$INSTALL_DIR"/*.sh "$INSTALL_DIR"/server.py
}

write_env() {
  ROLE="${ROLE//\'/}"
  ROLE="${ROLE//\"/}"
  SITE_NAME="${SITE_NAME//\'/}"
  SITE_NAME="${SITE_NAME//\"/}"
  cat > "$ENV_FILE" <<EOF
BEACON_HOST=0.0.0.0
BEACON_PORT=80
BEACON_ROLE=${ROLE}
BEACON_SITE_NAME=${SITE_NAME}
EOF
}

write_unit() {
  local python_bin
  python_bin="$(command -v python3)"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Beacon Dummy DR canary
After=network-online.target network.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
Environment=BEACON_HOST=0.0.0.0
Environment=BEACON_PORT=80
EnvironmentFile=-${ENV_FILE}
ExecStart=${python_bin} ${INSTALL_DIR}/server.py
Restart=always
RestartSec=2
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
}

if [[ "$UNINSTALL" -eq 1 ]]; then
  purge_beacon
  if pgrep -f "beacon-dummy.*server.py" >/dev/null 2>&1 || [[ -d "$INSTALL_DIR" ]]; then
    echo "Uninstall did not finish cleanly." >&2
    exit 1
  fi
  echo "Beacon Dummy is fully removed. Port 80 should now be free."
  port_users
  exit 0
fi

fetch_source
command -v python3 >/dev/null || pkg_install python3
purge_beacon
free_port_80
if ! precheck; then
  echo "Precheck failed. Run: sudo ./uninstall.sh" >&2
  exit 1
fi

copy_app
write_env
open_firewall

if command -v systemctl >/dev/null && [[ -d /run/systemd/system ]]; then
  write_unit
  systemctl daemon-reload
  systemctl enable "$APP_NAME" >/dev/null
  systemctl restart "$APP_NAME"
else
  echo "@reboot root $(command -v python3) ${INSTALL_DIR}/server.py" > "$CRON_FILE"
  chmod 644 "$CRON_FILE"
  nohup python3 "$INSTALL_DIR/server.py" >"$LOG_FILE" 2>&1 &
fi

if ! wait_health; then
  echo "Beacon did not become healthy on port 80 or 8080." >&2
  port_users
  command -v journalctl >/dev/null && journalctl -u "$APP_NAME" -n 50 --no-pager || true
  exit 1
fi

IP="$(detect_ip)"
open_firewall
echo
echo "Beacon is up and enabled on boot."
echo "  page     http://${IP}/"
echo "  alt      http://${IP}:8080/"
echo "  health   http://${IP}/health"
echo "  If Zscaler blocks port 80, use :8080"
command -v ss >/dev/null && ss -lnt | grep -E ':80|:8080' || true
echo
