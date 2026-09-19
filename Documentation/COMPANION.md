# Computer Companion

iPhone подключается к вашему macOS / Windows / Linux через `Companion/aiagenthub_companion.py`.

## Запуск

```bash
python3 Companion/aiagenthub_companion.py \
  --root ~/Projects \
  --root ~/Documents \
  --host 127.0.0.1 \   # или 0.0.0.0 для LAN
  --port 8765 \
  --allow-shell \
  --auto-allow git --auto-allow ls
```

Демон печатает:

```
[companion] Pairing code: 482193
[companion] Roots: /Users/you/Projects
[companion] Listening on 127.0.0.1:8765
```

В приложении: `Settings → 💻 Computer companion → Host = http://192.168.1.20:8765 → Code = 482193 → Pair`.

При успешном Pair создаётся случайный 256-битный pre-shared key, сохраняется в iOS Keychain и используется как `Authorization: Bearer <key>` на каждый запрос. Код одноразовый.

## API

- `POST /v1/pair` `{code, device}` → `{key}`
- `GET  /v1/hello` → `{hostname, os, arch, companionVersion, allowedRoots, shellEnabled}`
- `POST /v1/fs/list` `{path}` → `{entries}`
- `POST /v1/fs/read` `{path}` → `{content}`
- `POST /v1/fs/write` `{path, content}` → `{ok}` (спрашивает подтверждение на десктопе и на телефоне)
- `POST /v1/exec` `{command, cwd}` → `{exitCode, stdout, stderr}` (только если `--allow-shell`)

## Безопасность

- Все пути проверяются `within_roots` (path traversal отклоняется)
- Shell по умолчанию выключен
- Любая команда вне `--auto-allow` спрашивает `Allow? [y/N]` в терминале + подтверждение в приложении
- `compare_digest` для токена (constant-time)
- Биндинг по умолчанию `127.0.0.1`, LAN — опционально

## Платформозависимые подсказки

### macOS (`Companion/macOS/`)

```bash
# запустить в фоне через launchd — см. com.aiagenthub.companion.plist
launchctl load ~/Library/LaunchAgents/com.aiagenthub.companion.plist
```

### Windows (`Companion/Windows/`)

```bat
py Companion\aiagenthub_companion.py --root %USERPROFILE%\Projects --allow-shell
:: или создать задачу в Task Scheduler — см. README в папке
```

### Linux (`Companion/Linux/`)

```bash
# systemd user service — см. aiagenthub-companion.service
systemctl --user enable --now aiagenthub-companion
```
