#!/usr/bin/env bash
# One command on the dummy VM:
#   sudo ./install.sh
#   curl -fsSL https://raw.githubusercontent.com/azana-nisaa/beacon-dummy/main/install.sh | sudo bash
set -euo pipefail

APP_NAME="beacon-dummy"
INSTALL_DIR="/opt/beacon-dummy"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
ENV_FILE="/etc/default/${APP_NAME}"
CRON_FILE="/etc/cron.d/${APP_NAME}"
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
is_root() { [[ "${EUID}" -eq 0 ]]; }

if ! is_root; then
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
      echo "Usage: sudo ./install.sh [--name TITLE] [--role dummy|dr|primary] [--uninstall]"
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

ensure_python() {
  command -v python3 >/dev/null 2>&1 && return
  pkg_install python3
}

fetch_source() {
  [[ -n "$SRC_DIR" && -f "$SRC_DIR/server.py" && -d "$SRC_DIR/static" ]] && return
  echo "Downloading Beacon Dummy..."
  command -v tar >/dev/null || pkg_install tar
  local tmp
  tmp="$(mktemp -d)"
  if command -v curl >/dev/null; then
    curl -fsSL "$REPO_TARBALL" -o "$tmp/src.tgz"
  else
    pkg_install curl
    curl -fsSL "$REPO_TARBALL" -o "$tmp/src.tgz"
  fi
  tar -xzf "$tmp/src.tgz" -C "$tmp"
  SRC_DIR="$(dirname "$(find "$tmp" -maxdepth 2 -name server.py | head -n 1)")"
  [[ -f "$SRC_DIR/server.py" ]] || { echo "Download failed." >&2; exit 1; }
}

load_name() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    source "$ENV_FILE" || true
    set +a
    [[ "$ROLE_SET" -eq 0 ]] && ROLE="${BEACON_ROLE:-$ROLE}"
    [[ "$NAME_SET" -eq 0 ]] && SITE_NAME="${BEACON_SITE_NAME:-$SITE_NAME}"
  fi
  ROLE="${ROLE//\'/}"
  ROLE="${ROLE//\"/}"
  SITE_NAME="${SITE_NAME//\'/}"
  SITE_NAME="${SITE_NAME//\"/}"
  PORT=80
}

stop_old() {
  if command -v systemctl >/dev/null; then
    systemctl stop "$APP_NAME" 2>/dev/null || true
    for svc in nginx apache2 httpd lighttpd; do
      systemctl stop "$svc" 2>/dev/null || true
      systemctl disable "$svc" 2>/dev/null || true
    done
  fi
  pkill -f "beacon-dummy.*server.py" 2>/dev/null || true
  pkill -f "/opt/beacon-dummy/server.py" 2>/dev/null || true
  sleep 0.3
}

copy_app() {
  mkdir -p "$INSTALL_DIR"
  if command -v rsync >/dev/null; then
    rsync -a --delete --exclude '.git' --exclude '.env' --exclude '__pycache__' "$SRC_DIR/" "$INSTALL_DIR/"
  else
    find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 ! -name '.env' -exec rm -rf {} +
    cp -a "$SRC_DIR/." "$INSTALL_DIR/"
    rm -rf "$INSTALL_DIR/.git"
  fi
  id "$SERVICE_USER" >/dev/null 2>&1 || useradd --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin "$SERVICE_USER" 2>/dev/null \
    || useradd --system --home "$INSTALL_DIR" --shell /sbin/nologin "$SERVICE_USER"
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR"
  chmod 755 "$INSTALL_DIR" "$INSTALL_DIR"/server.py "$INSTALL_DIR"/install.sh "$INSTALL_DIR"/setup.sh "$INSTALL_DIR"/start.sh
}

write_env() {
  cat > "$ENV_FILE" <<EOF
BEACON_HOST=0.0.0.0
BEACON_PORT=80
BEACON_ROLE=${ROLE}
BEACON_SITE_NAME=${SITE_NAME}
EOF
  chmod 644 "$ENV_FILE"
}

allow_port_80() {
  if [[ -w /proc/sys/net/ipv4/ip_unprivileged_port_start ]]; then
    echo 80 > /proc/sys/net/ipv4/ip_unprivileged_port_start || true
    mkdir -p /etc/sysctl.d
    echo "net.ipv4.ip_unprivileged_port_start=80" > /etc/sysctl.d/80-beacon-dummy.conf
  fi
  if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -qi "Status: active"; then
    ufw allow 80/tcp >/dev/null || true
  fi
  if command -v firewall-cmd >/dev/null && firewall-cmd --state 2>/dev/null | grep -qi running; then
    firewall-cmd --permanent --add-service=http >/dev/null 2>&1 \
      || firewall-cmd --permanent --add-port=80/tcp >/dev/null || true
    firewall-cmd --reload >/dev/null || true
  fi
  if command -v iptables >/dev/null; then
    iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null \
      || iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT || true
    if command -v netfilter-persistent >/dev/null; then
      netfilter-persistent save >/dev/null 2>&1 || true
    elif command -v service >/dev/null; then
      service iptables save >/dev/null 2>&1 || true
    fi
  fi
}

write_unit() {
  local user="$1"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Beacon Dummy DR canary
After=network-online.target network.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=${user}
WorkingDirectory=${INSTALL_DIR}
Environment=BEACON_HOST=0.0.0.0
Environment=BEACON_PORT=80
EnvironmentFile=-${ENV_FILE}
ExecStart=${PYTHON_BIN} ${INSTALL_DIR}/server.py
Restart=always
RestartSec=2
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$SERVICE_FILE"
}

start_unit() {
  systemctl daemon-reload
  systemctl enable "$APP_NAME" >/dev/null
  systemctl restart "$APP_NAME"
}

wait_health() {
  python3 - "$PORT" <<'PY'
import sys, time, urllib.request
port = sys.argv[1]
url = "http://127.0.0.1:%s/health" % port
for _ in range(40):
    try:
        res = urllib.request.urlopen(url, timeout=1)
        if res.status == 200 and res.headers.get("X-Beacon") == "alive":
            sys.exit(0)
    except Exception:
        time.sleep(0.25)
sys.exit(1)
PY
}

detect_ip() {
  local ip=""
  command -v ip >/dev/null && ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  [[ -z "$ip" ]] && ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  echo "${ip:-127.0.0.1}"
}

uninstall_app() {
  command -v systemctl >/dev/null && systemctl disable --now "$APP_NAME" 2>/dev/null || true
  pkill -f "beacon-dummy.*server.py" 2>/dev/null || true
  rm -f "$SERVICE_FILE" "$ENV_FILE" "$CRON_FILE" /etc/sysctl.d/80-beacon-dummy.conf
  command -v systemctl >/dev/null && systemctl daemon-reload || true
  rm -rf "$INSTALL_DIR"
  userdel "$SERVICE_USER" 2>/dev/null || true
  echo "Removed ${APP_NAME}."
}

if [[ "$UNINSTALL" -eq 1 ]]; then
  uninstall_app
  exit 0
fi

fetch_source
ensure_python
PYTHON_BIN="$(command -v python3)"
load_name
stop_old
copy_app
write_env
allow_port_80

if command -v systemctl >/dev/null && [[ -d /run/systemd/system ]]; then
  write_unit "$SERVICE_USER"
  start_unit
  if ! wait_health; then
    echo "Port 80 bind as ${SERVICE_USER} failed, retrying as root..."
    write_unit root
    start_unit
  fi
else
  echo "@reboot root ${PYTHON_BIN} ${INSTALL_DIR}/server.py" > "$CRON_FILE"
  chmod 644 "$CRON_FILE"
  nohup "$PYTHON_BIN" "$INSTALL_DIR/server.py" >/var/log/beacon-dummy.log 2>&1 &
fi

if ! wait_health; then
  echo "Beacon did not start on port 80." >&2
  command -v journalctl >/dev/null && journalctl -u "$APP_NAME" -n 40 --no-pager || true
  exit 1
fi

IP="$(detect_ip)"
echo
echo "Beacon is up and enabled on boot."
echo "  page    http://${IP}/"
echo "  health  http://${IP}/health"
echo "  logs    journalctl -u ${APP_NAME} -f"
echo
