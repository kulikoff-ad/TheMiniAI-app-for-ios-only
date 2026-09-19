# Architecture

```
AIAgentHub.xcodeproj          # Xcode 16, File System Synchronized Group
AIAgentHub/
  App/                        # AIAgentHubApp.swift (entry), Theme.swift
  Core/
    Models/                   # HF DTOs, ModelFormat, LocalModel, Agent, Enums
    Security/                 # KeychainStore
    Storage/                  # ModelStorage, ModelLibrary, AgentStore, GitHubStore
    Utils/                    # DeviceCapabilities, Formatting
  Features/
    Home/                     # HomeView — 9-tile AI IDE dashboard
    HuggingFace/              # Browser, Store, Detail, PhoneAI
    Models/                   # ModelsView, LocalModelViews, PhoneAIAnalyzer
    Agents/                   # AgentsView, Agent presets
    Workspace/                # Live workspace (TASK/MODEL/PLAN/TOOLS/OUTPUT)
    GitHub/                   # GitHubView, ReplaceProject flow
    Files/                    # FilesView (sandbox browser)
    OnlineAI/                 # Provider Manager, Router
    Settings/                 # SettingsView + sub-screens
    Companion/                # Pairing UI (wraps Services/Companion)
  Services/
    HuggingFace/              # HuggingFaceAPI, DownloadManager
    GitHub/                   # GitHubAPI
    Agent/                    # AgentRuntime, ToolRegistry, DiffBuilder
    Tools/                    # FileTool, WebTool, GitHubTool, CompanionTool
    Inference/                # InferenceEngine + adapters (llama.cpp, CoreML, ONNX, MLX)
    Companion/                # CompanionClient
    Networking/               # HTTP helpers
  Resources/
    Assets.xcassets/          # AppIcon 1024 + 60@2x/3x etc, AccentColor

Config/                       # Info.plist, entitlements (вне synchronized группы)
Companion/
  aiagenthub_companion.py     # кроссплатформенный демон (stdlib only)
  macOS/                      # launchd + инструкции
  Windows/                    # .bat + инструкции
  Linux/                      # systemd + инструкции

Documentation/                # эта папка
scripts/build_ipa.sh          # сборка signed / unsigned IPA
.github/workflows/ios.yml     # CI на macos-15
```

## Поток данных

`Home → Hugging Face → Download → LocalModel → Agent → Workspace → Files/Web/GitHub/Computer`

И в параллель: `Online AI → ProviderManager → AgentRuntime (CloudEngine) → те же Tools`

`AgentRuntime` делает:

1. `makeEngine(for: agent)` — выбирает Cloud или Local (проверяет совместимость через DeviceCapabilities)
2. Планирование: просит модель вернуть JSON массив 3-6 шагов
3. ReAct цикл до 12 итераций: `LLM → ToolCall JSON → ToolRegistry.invoke → обратно в транскрипт`
4. Подтверждение: любой `FileTool.write` / `GitHubAPI.putFile` / `CompanionClient.exec` заворачивается в `requestConfirmation` → лист с Diff → Approve/Reject

## Хранение

- Модели: `Documents/Models/<repoId>/<revision>/<file>` + `Library/model-library.json`
- Workspace файлов агента: `Documents/Workspace/` (sandbox)
- Агент-конфиги и история: `UserDefaults + Library/agent-store.json`
- Токены: iOS Keychain `kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
