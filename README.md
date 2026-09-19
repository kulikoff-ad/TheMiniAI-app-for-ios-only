# AI Agent Hub — AI Agent Hub for iPhone

**Download AI from Hugging Face. Build agents. Create anything. Local or online.**

AI Agent Hub — нативное iOS-приложение (Swift + SwiftUI, iOS 17+) которое превращает iPhone в универсальный центр для AI-моделей и AI-агентов. Ищите модели на 🤗 Hugging Face, подбирайте модели именно для телефона (с учётом RAM, формата и рантайма), качайте выборочно файлы, запускайте GGUF/Core ML/ONNX локально или используйте Online AI провайдеров, создавайте агентов с инструментами (Files, Web, GitHub, Computer) и публикуйте проекты.

---

## ⬇️ Downloads

### Готовый IPA (собран CI на macOS + Xcode 16.4)

**[⬇️ Скачать последний IPA](https://github.com/kulikoff-ad/TheMiniAI-app-for-ios-only/releases/latest)** — неподписанный, ~0.6 MB.

Ставится через **AltStore / Sideloadly**, либо пересобирается с вашей подписью:
`./scripts/build_ipa.sh --team <YOUR_TEAM_ID>`.

Все сборки: [Releases](https://github.com/kulikoff-ad/TheMiniAI-app-for-ios-only/releases) · [Actions](https://github.com/kulikoff-ad/TheMiniAI-app-for-ios-only/actions/workflows/ios.yml). Каждый push публикует новый релиз `build-<номер>` с прямой ссылкой на IPA.

### Исходники и companion

| Файл | Что это |
|---|---|
| `AIAgentHub-src-*.zip` | Полный Xcode-проект |
| `Companion/` | Companion-демон (macOS/Windows/Linux) |
| `Documentation/` | Документация |

---

## 🎯 Что умеет приложение

- 🔎 **Search AI** — поиск моделей Hugging Face
- 🤖 **My Agents** — создание и управление агентами
- 🧠 **My Models** — установленные локальные модели
- 🤗 **Hugging Face** — Hub с вкладками Discover / Search / Phone AI / Downloaded / Favorites
- 🌐 **Online AI** — Provider Manager (несколько провайдеров + Custom API, ключи в Keychain, режимы Local / Online / Auto)
- 📁 **Files** — создание/чтение/редактирование файлов, ZIP, анализ документов (песочница Workspace)
- 🐙 **GitHub** — авторизация, репозитории, создание файлов/веток, коммиты, PRs, diff
- 💻 **Computer** — подключение к macOS/Windows/Linux через безопасный Companion-клиент
- ⚙️ **Settings** — полный набор настроек

### 📱 AI for iPhone

Отдельный режим **📱 AI for iPhone** в приложении. Пользователь вводит “AI для программирования”, “маленькая модель для iPhone”, “AI до 2 GB” — приложение:

- извлекает ключевые слова, теги (`gguf`, `coreml`, `onnx`), `pipeline_tag`
- фильтрует результаты с учётом **модели iPhone, доступной памяти, свободного места, архитектуры, вычислительных возможностей, размера, формата, quantization и рантайма**
- показывает фильтры: **📱 Phone Compatible**, <500 MB, <1 GB, <2 GB, <4 GB, <8 GB, GGUF, ONNX, Core ML, SafeTensors, Text Generation, Coding, Vision, Embeddings, Small Models
- **не утверждает совместимость только по размеру** — проверяет `format.runtime.runsOnDevice` + оценку `estimatedMemory` vs `usableMemoryBudget`

Прогресс загрузки:

```
Downloading model...
████████████░░░░ 78%
3.1 GB / 4.0 GB
```

Пауза / возобновление (`resumeData`) / отмена / удаление / предупреждение >1 GB.

---

## Contents

- [Project layout](#project-layout)
- [Requirements](#requirements)
- [Build & run — 6 шагов для IPA](#build--run--6-шагов-для-ipa)
- [Hugging Face](#hugging-face)
- [Online AI](#online-ai)
- [Agents](#agents)
- [Computer companion](#computer-companion)
- [Security](#security)
- [Workspace](#workspace)

---

## Project layout

```
AIAgentHub.xcodeproj          # Xcode 16, file-system synchronized group
AIAgentHub/
  App/                        # Entry, Theme, RootTabView (9 разделов)
  Core/
    Models/                   # HFModels, LocalModel, ModelFormat, Agent
    Storage/                  # ModelStorage, ModelLibrary, AgentStore, OnlineProviderStore, GitHubStore
    Security/                 # KeychainStore, PermissionManager
    Utils/                    # DeviceCapabilities, Formatting
  Features/
    Home/                     # HomeView — AI IDE dashboard (9 tiles + pulse animation)
    HuggingFace/              # HuggingFaceHubView (5 tabs), Browser, Detail, Store
    PhoneAI/                  # 📱 AI for iPhone (Phone Compatibility filters)
    Models/                   # ModelsView (Discover/Downloaded/Running/Favorites), Finder
    OnlineAI/                 # OnlineAIView + Provider Manager
    Agents/                   # AgentsView + 6 preset agents
    Files/                    # FilesView (sandbox browser)
    Workspace/                # Live workspace TASK/MODEL/PLAN/TOOLS/OUTPUT
    GitHub/                   # GitHubView + ReplaceProjectView (16 шагов)
    Settings/                 # SettingsView (все разделы ТЗ)
  Services/
    HuggingFace/              # HuggingFaceAPI, DownloadManager (background URLSession)
    GitHub/                   # GitHubAPI (реальные REST вызовы)
    Agent/                    # AgentRuntime (ReAct 12 шагов), ToolRegistry, DiffBuilder
    Tools/                    # FileTool, WebTool
    Inference/                # InferenceEngine (llama.cpp / Core ML / ONNX / MLX) + CloudEngine
    Companion/                # CompanionClient
    Networking/               # APIClient
  Resources/
    Assets.xcassets/          # AppIcon 1024 + размеры, AccentColor

AIAgentHub/Networking/, Web/, Files/, GitHub/, HuggingFace/, Security/, Storage/, Agents/, Views/  # алиасы для соответствия ТЗ структуре
Config/                       # Info.plist, entitlements (вне synchronized группы)
Companion/
  aiagenthub_companion.py     # кроссплатформенный демон (stdlib only)
  macOS/                      # README + launchd plist
  Windows/                    # README + run.bat
  Linux/                      # README + systemd service
Documentation/                # ARCHITECTURE.md, HUGGINGFACE.md, AGENTS.md, COMPANION.md, SECURITY.md, RUNTIMES.md, BUILD_IPA.md
scripts/build_ipa.sh
.github/workflows/ios.yml
```

---

## Requirements

- macOS 14+ с **Xcode 16** или новее
- iOS 17.0+ target (iPhone и iPad)
- Apple Developer account для подписанных сборок (free подходит для 7-дневной установки на устройство)

---

## Build & run — 6 шагов для IPA

### 1. Открыть проект в Xcode

```bash
git clone https://github.com/kulikoff-ad/TheMiniAI-app-for-ios-only.git
cd TheMiniAI-app-for-ios-only
open AIAgentHub.xcodeproj
```

Выберите схему **AIAgentHub**, симулятор или устройство, нажмите `⌘R`. Проект использует *file-system synchronized group* — любой `.swift` под `AIAgentHub/` компилируется автоматически.

### 2. Настроить Signing

`Target → Signing & Capabilities → Team` — выберите вашу команду Apple Developer. Если Bundle ID `app.aiagenthub.ios` занят, смените на уникальный, например `app.yourname.aiagenthub`.

### 3. Собрать приложение

`⌘R` для запуска на симуляторе/устройстве. Для проверки сборки без подписи:

```bash
./scripts/build_ipa.sh --unsigned
```

### 4. Archive

В Xcode: `Product → Archive`. Дождитесь окончания сборки архива (Destination: `Generic iOS Device` или `Any iOS Device`).

### 5. Export IPA

**Через скрипт (рекомендуется):**

```bash
# Unsigned (для AltStore / Sideloadly / последующей переподписи)
./scripts/build_ipa.sh --unsigned
# → build/AIAgentHub-unsigned.ipa

# Signed (device / Ad Hoc / TestFlight)
./scripts/build_ipa.sh --team ABCDE12345 --method development
# methods: development | ad-hoc | app-store | enterprise
# → build/ipa/AIAgentHub.ipa
```

**Через Xcode UI:** `Window → Organizer → Archives → Distribute App → Custom → Export → development / ad-hoc` → получите IPA.

CI автоматически собирает unsigned IPA на `macos-15` при каждом push и публикует его в Releases.

### 6. Установить IPA на iPhone

- **AltStore:** перетащите IPA в AltServer → Install (требует запущенный AltServer на Mac/PC в той же сети).
- **Sideloadly:** откройте Sideloadly, выберите IPA и ваш Apple ID, нажмите `Start` → введите пароль приложения.
- **Apple Configurator / Xcode Devices:** подключите iPhone по USB, перетащите IPA в устройство.
- **TestFlight:** загрузите через `Transporter` или `xcodebuild -exportArchive` с `method=app-store`.

> IPA можно собрать только на macOS с Xcode — toolchain Apple не работает на Linux. Всё необходимое для сборки уже в репозитории; запустите скрипт или CI job на Mac.

---

## Hugging Face

Используется официальный Hub REST API: https://huggingface.co/docs/hub/api

- Поиск: `GET /api/models?search=&filter=&pipeline_tag=&author=&sort=&direction=-1`
- Карточка модели: `GET /api/models/{id}/revision/{rev}`
- Дерево файлов: `GET /api/models/{id}/tree/{rev}?expand=true&recursive=true`
- README: `GET /{id}/raw/{rev}/README.md`
- Скачать: `GET /{id}/resolve/{rev}/{file}?download=true`
- Авторизация: `GET /api/whoami-v2` (User Access Token из Keychain)
- Cloud inference: `POST https://router.huggingface.co/v1/chat/completions`

Токен создаётся на https://huggingface.co/settings/tokens (scope `read`, опционально `write`), хранится только в Keychain, пароль никогда не запрашивается.

Вкладки Hugging Face: **Discover / Search / Phone AI / Downloaded / Favorites** — в `HuggingFaceHubView`.

---

## Online AI

**🌐 Online AI** работает независимо от локальных моделей.

- **AI Provider Manager:** добавьте несколько провайдеров (Provider 1, 2, 3 и **Custom API** для любого OpenAI-совместимого endpoint — Groq, Together, Mistral, локальный vLLM/Ollama). Каждый ключ хранится отдельно в Keychain (`app.aiagenthub.online` service).
- Выбор провайдера и модели per-agent или глобально в `Settings → AI Providers`.
- Режимы: **Local AI / Online AI / Auto** — в Auto приложение выбирает подходящий доступный вариант для задачи (локальная если установлена и совместима, иначе выбранный онлайн провайдер).
- Offline Mode (глобальный) принудительно использует только локальные модели.

---

## Agents

Каждый агент имеет: **Name, Description, Model, System Prompt, Tools, Permissions, Memory (via transcript), Task History**.

Готовые агенты (создаются при первом запуске):

- **Coding Agent** — создаёт и редактирует код, создаёт проекты
- **File Agent** — файлы, папки, ZIP, анализ документов
- **Web Research Agent** — ищет в интернете, читает страницы, собирает отчёт
- **GitHub Agent** — работает с репозиториями (файлы, ветки, коммиты, PRs, diff)
- **Phone AI Agent** — оптимизирован для локальных GGUF/Core ML на iPhone
- **PC Agent** — работает с компьютером через Companion-клиент (файлы, команды, тесты)

Tools: **📁 Files** (создание/чтение/правка/ZIP), **🌐 Web** (search DuckDuckGo, fetch, extract, links, report), **🐙 GitHub** (repos, branches, commits, PRs, diff), **💻 Computer** (Companion: list/read/write/exec). Все опасные действия требуют подтверждения с diff.

---

## Computer companion

`Companion/aiagenthub_companion.py` — демон без зависимостей (stdlib only) для macOS/Windows/Linux.

```bash
python3 Companion/aiagenthub_companion.py --root ~/Projects --allow-shell --host 127.0.0.1 --port 8765
```

Печатает 6-значный код. В приложении: `Settings → Computer → Pair` → введите `http://<host>:8765` и код. Создаётся случайный 256-битный PSK в Keychain, все запросы — `Authorization: Bearer <key>`, `constant-time` сравнение, `within_roots` защита, shell только с `--allow-shell`, подтверждение на десктопе + телефоне.

Папки: `Companion/macOS/README.md + plist`, `Companion/Windows/README.md + run.bat`, `Companion/Linux/README.md + service`.

---

## Security

**Permission Manager** — отдельные разрешения: Web Access, File Access, GitHub Access, Computer Access, Terminal Access, Network Access, Model Download. Каждый агент показываетGranted бейджи.

- Секреты только в Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), wipe через Settings → Erase all.
- Подтверждения для `files.write`, `github.putFile`, `companion.fs/write`, `companion.exec` — лист с unified diff.

---

## Workspace

```
AI Agent Workspace
─────────────────
TASK   Create an iOS application
MODEL  Local / Online · Qwen2.5-1.5B-Q4_K_M
PLAN   ✓ Analyze  ✓ Search  → Generate files  ○ Test  ○ GitHub
TOOLS  ✓ Files ✓ Web ✓ GitHub ○ Computer
OUTPUT …
─────────────────
Activity (live, timestamps):
  12:03 thought — Plan created
  12:03 toolCall — 📁 files.write {path: "Sources/App.swift"}
  12:03 toolResult — written 3120 bytes
```

---

## Settings

Включено всё из ТЗ: AI Providers, Hugging Face, GitHub, Download Settings, Storage, Local Models, Online Models, Agent Permissions, Computer Connections, Appearance, Language, About + Device (model, RAM, budget, MLX).

---

## License

MIT — см. `LICENSE`. Модели с Hugging Face — под своими лицензиями (показываются в карточке модели).
