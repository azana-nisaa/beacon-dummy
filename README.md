# Beacon Dummy

A lightweight canary website for **disaster recovery drills**.

It is meant to look like a real page — not a blank “it works” screen — so you can screenshot proof that a dummy VM is up, serving HTTP, and reachable after failover.

No database. No login. No npm. Python 3 standard library only.

## Quick start

```bash
git clone https://github.com/azana-nisaa/beacon-dummy.git
cd beacon-dummy
chmod +x start.sh setup.sh
./start.sh
```

Open [http://SERVER_IP:8080](http://SERVER_IP:8080).

## Linux VM install (systemd)

On the dummy VM:

```bash
sudo ./setup.sh --port 8080 --role dummy --name "Customer DR Canary"
```

That will:

1. Install `python3` if it is missing (apt / dnf / yum / zypper)
2. Copy the app to `/opt/beacon-dummy`
3. Create a `beacon` system user
4. Enable and start `beacon-dummy.service`

Useful flags:

```bash
sudo ./setup.sh --port 80 --role dr --name "Acme DR Canary"
sudo ./setup.sh --uninstall
```

After install:

| What | Where |
| --- | --- |
| Page | `http://<vm-ip>:<port>/` |
| Health probe | `http://<vm-ip>:<port>/health` |
| JSON identity | `http://<vm-ip>:<port>/api/status` |
| Environment | `/etc/default/beacon-dummy` |
| Logs | `journalctl -u beacon-dummy -f` |

To change the title later:

```bash
sudo nano /etc/default/beacon-dummy
sudo systemctl restart beacon-dummy
```

Optional nginx reverse proxy: see `nginx.conf.example`.

## What you get on the page

- Live **ONLINE** badge
- Real hostname, IP, clock, uptime, and request count from the VM
- A screenshot strip designed for DR reports
- A unique identicon derived from the hostname, so primary and DR VMs look different

## Environment

Copy `.env.example` to `.env` for foreground runs, or set the same keys in `/etc/default/beacon-dummy` for systemd:

```
BEACON_HOST=0.0.0.0
BEACON_PORT=8080
BEACON_ROLE=dummy
BEACON_SITE_NAME=Beacon Canary
```

`BEACON_ROLE` is the label you want on the proof strip (`dummy`, `primary`, `dr`, …).

## Health checks

Load balancers and monitors can hit:

- `GET /health`
- `GET /healthz`
- `GET /ready`
- `GET /api/status` (JSON)

All of them return HTTP 200 while the process is up.

## Uninstall

```bash
sudo ./setup.sh --uninstall
```

## License

MIT. Use it on customer dummy VMs, internal labs, or as a shared DR canary.
