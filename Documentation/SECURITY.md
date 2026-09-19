# Security — Permission Manager

## Хранение секретов

- Hugging Face token, GitHub PAT, OpenAI-compatible key, Companion PSK — только в **iOS Keychain** (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Никогда в UserDefaults, файлах или бэкапах.
- Пароль Hugging Face / GitHub никогда не запрашивается.

## Permission Manager

Каждому агенту можно выдать:

- **Web Access** — `web.search`, `web.fetch`
- **File Access** — `files.read/list/tree` (всегда), `files.write/mkdir` (если `allowFileWrite`), `files.delete` (если `allowFileDelete`)
- **GitHub Access** — чтение всегда, запись только если `allowGitHubWrite` + `requireConfirmationBeforePush`
- **Computer Access** — только если `allowComputerControl` + успешный Pair
- **Terminal Access** — Companion `--allow-shell` + `shellSandbox` tool
- **Network Access** — общий свитч `allowNetwork` (если off — web и cloud inference блокируются)
- **Model Download** — скачивание файлов Hugging Face (проверка свободного места, предупреждение >1GB)

UI показывает бейджи разрешений на карточке агента и в Workspace → Tools. При попытке вызова запрещённого инструмента агент получает `ERROR: denied by permissions`.

## Подтверждения

Эти действия требуют двойного подтверждения (десктоп + iPhone):

- `files.write` с перезаписью
- `github.putFile` (commit)
- `github.createPullRequest`
- `companion.fs/write`
- `companion.exec`

На iPhone показывается `ConfirmationSheet` с unified diff (см. `Services/Agent/DiffBuilder`).

## Offline Mode

Переключатель `Settings → Offline Mode`:

- агент обязан иметь `binding = .local`
- `allowNetwork = false` принудительно
- web/github/computer tools удаляются
- история задач не загружается
