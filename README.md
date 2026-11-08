# Beacon Dummy

A small dummy website for disaster recovery drills. If the page opens, the VM is serving HTTP.

No database. No login. No npm. Python 3 only.

## Install on the dummy VM

That is the whole job. The installer puts the site on port 80, starts it, and enables it so it comes back after reboot.

```bash
curl -fsSL https://raw.githubusercontent.com/azana-nisaa/beacon-dummy/main/install.sh | sudo bash
```

Or, if you already cloned the repo:

```bash
git clone https://github.com/azana-nisaa/beacon-dummy.git
cd beacon-dummy
sudo ./install.sh
```

Then open `http://VM_IP`.

`install.sh`, `setup.sh`, and `start.sh` all do the same job. Safe to run again after `git pull`. If the site is already up, it is restarted on port 80.

Optional flags:

```bash
sudo ./install.sh --name "Customer DR Canary"
sudo ./install.sh --uninstall
```

## After install

| What | Where |
| --- | --- |
| Page | `http://<vm-ip>/` |
| Health | `http://<vm-ip>/health` |
| JSON | `http://<vm-ip>/api/status` |
| Config | `/etc/default/beacon-dummy` |
| Logs | `journalctl -u beacon-dummy -f` |

Re-running `sudo ./install.sh` updates the files and keeps the current name and role. It always listens on port 80.

## License

MIT.
