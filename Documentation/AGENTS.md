# Agents

Каждый агент — это:

```swift
struct Agent {
  name, descriptionText, systemPrompt
  binding: Cloud(provider, model) | Local(modelId)
  temperature, maxTokens
  tools: Set<AgentToolKind>  // files, web, github, computer
  permissions: AgentPermissions
  history: [AgentRun]
}
```

## Готовые агенты (создаются при первом запуске)

- **Coding Agent** — создаёт и редактирует код (`files`, `github`)
- **File Agent** — создаёт/изменяет файлы, ZIP, анализ документов (`files`)
- **Web Research Agent** — ищет и собирает информацию (`web`, `files`)
- **GitHub Agent** — работает с репозиториями (`github`, `files`)
- **Phone AI Agent** — оптимизирован под локальные GGUF/CoreML на iPhone (`files`, локальная модель)
- **PC Agent** — работает с компьютером через Companion (`computer`, `files`)

User может создать любого кастомного агента и выбрать `Local AI / Online AI / Auto`.

`Auto` в текущей версии реализован как: если у агента локальная привязка и модель установлена — используется она, иначе fallback на выбранный Cloud провайдер (настраивается в Settings → Online AI → Preferred provider).

## Tools

- **Files**: `list`, `read`, `write`, `append`, `mkdir`, `delete`, `tree`, `zip`, `analyze`. Песочница: `Documents/Workspace`
- **Web**: `search` (DuckDuckGo HTML, без ключа), `fetch`, `extract`, `links`, `report`
- **GitHub**: `listRepos`, `contents`, `fileText`, `createBranch`, `putFile` (commit), `createPullRequest`, `compare` (diff)
- **Computer** (Companion): `hello`, `fs/list`, `fs/read`, `fs/write`, `exec`

Каждый инструмент требует разрешения (см. `AgentPermissions` + `Security/PERMISSIONS.md`). Опасные действия (`putFile`, `fs/write`, `exec`) идут через `AgentRuntime.requestConfirmation` — на экране появляется diff + кнопки Approve/Reject.

## Workspace

```
AI Agent Workspace
─────────────────
TASK   Create an iOS application
MODEL  Local / Online · Qwen2.5-1.5B-Q4_K_M / gpt-4o-mini
PLAN   ✓ Analyze  ✓ Search  → Generate files  ○ Test  ○ GitHub
TOOLS  ✓ Files ✓ Web ✓ GitHub ○ Computer
OUTPUT …
─────────────────
Activity (live):
  12:03 thought — Plan created
  12:03 toolCall — 📁 files.write {path: "Sources/App.swift"}
  12:03 toolResult — written 3120 bytes
```

Всё стримится в `AgentRun.events` и показывается в реальном времени.
