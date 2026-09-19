# Companion — Linux

## Запуск
```bash
python3 Companion/aiagenthub_companion.py --root ~/Projects --allow-shell --host 127.0.0.1
```

## systemd (user)
```bash
mkdir -p ~/.config/systemd/user
cp Companion/Linux/aiagenthub-companion.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now aiagenthub-companion
journalctl --user -u aiagenthub-companion -f
```
