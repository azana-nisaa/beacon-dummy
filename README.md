# Beacon Dummy

Dummy website for disaster recovery drills. If this page opens, the VM is serving HTTP.

No database, no login, no npm. Python 3 only. Always on port 80.

## Install

On a dummy VM, this is the whole job:

```bash
curl -fsSL https://raw.githubusercontent.com/azana-nisaa/beacon-dummy/main/install.sh | sudo bash
```

Or from a clone:

```bash
git clone https://github.com/azana-nisaa/beacon-dummy.git
cd beacon-dummy
sudo ./install.sh
```

Then open `http://VM_IP`.

`install.sh`, `setup.sh`, and `start.sh` do the same thing. Safe to run again after `git pull`. The installer stops leftover Beacon processes, frees port 80, starts the service, and enables it on boot.

```bash
sudo ./install.sh --name "Customer DR Canary"
sudo ./install.sh --uninstall
```

| What | Where |
| --- | --- |
| Page | `http://<vm-ip>/` |
| Health | `http://<vm-ip>/health` |
| JSON | `http://<vm-ip>/api/status` |
| Config | `/etc/default/beacon-dummy` |
| Logs | `journalctl -u beacon-dummy -f` |

## License

MIT.
