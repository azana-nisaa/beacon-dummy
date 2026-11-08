# Beacon Dummy

Dummy website for disaster recovery drills. It listens on port 80. If the page opens, the VM is serving HTTP.

## Install

On a dummy VM that already had an older Beacon:

```bash
git pull
sudo ./uninstall.sh
sudo ./install.sh
```

On a new VM:

```bash
git clone https://github.com/azana-nisaa/beacon-dummy.git
cd beacon-dummy
sudo ./install.sh
```

Or:

```bash
curl -fsSL https://raw.githubusercontent.com/azana-nisaa/beacon-dummy/main/install.sh | sudo bash
```

Then open `http://VM_IP`.

`install.sh` always purges leftover Beacon files first, then prechecks that port 80 is free. `uninstall.sh` removes the service, processes, `/opt/beacon-dummy`, env files, cron, and the `beacon` user.

```bash
sudo ./install.sh --name "Customer DR Canary"
sudo ./uninstall.sh
```

| What | Where |
| --- | --- |
| Page | `http://<vm-ip>/` |
| Health | `http://<vm-ip>/health` |
| JSON | `http://<vm-ip>/api/status` |
| Logs | `journalctl -u beacon-dummy -f` |

## License

MIT.
