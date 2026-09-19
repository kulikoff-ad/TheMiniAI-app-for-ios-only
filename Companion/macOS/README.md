# Companion — macOS

## Запуск вручную
```bash
python3 ../aiagenthub_companion.py --root ~/Projects --allow-shell --host 127.0.0.1
```

## Автозапуск через launchd
```bash
cp com.aiagenthub.companion.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.aiagenthub.companion.plist
launchctl start com.aiagenthub.companion
```

Код для Pair покажется в `log stream --predicate 'process == "aiagenthub_companion.py"'` или в терминале если запускаете вручную.
