# AI Agent Hub

**Download AI from Hugging Face. Build agents. Create anything.**

A native iOS app (Swift + SwiftUI) that turns your iPhone or iPad into a universal manager for
AI models and AI agents. Find models on the Hugging Face Hub, pick exactly which files to
download, install them locally, then wire them into agents that use real tools — files, web,
GitHub, and your own computer.

---

## Contents

- [Feature tour](#feature-tour)
- [Project layout](#project-layout)
- [Requirements](#requirements)
- [Build & run](#build--run)
- [Building an IPA](#building-an-ipa)
- [Connecting Hugging Face](#connecting-hugging-face)
- [Connecting GitHub](#connecting-github)
- [Computer companion](#computer-companion)
- [Local inference runtimes](#local-inference-runtimes)
- [Offline Mode](#offline-mode)
- [iOS sandbox & security](#ios-sandbox--security)
- [Limitations & honesty notes](#limitations--honesty-notes)

---

## Feature tour

### 🤗 Hugging Face
Backed by the real [Hugging Face Hub API](https://huggingface.co/docs/hub/api).

| Capability | Endpoint used |
|---|---|
| Search by name | `GET /api/models?search=` |
| Filter by tag / format / task / author | `?filter=`, `?pipeline_tag=`, `?author=` |
| Sort (trending, downloads, likes, updated) | `?sort=&direction=-1` |
| Model card page | `GET /api/models/{id}/revision/{rev}` |
| README / model card | `GET /{id}/raw/{rev}/README.md` |
| Repository file tree with real sizes | `GET /api/models/{id}/tree/{rev}?expand=true&recursive=true` |
| Download a file | `GET /{id}/resolve/{rev}/{file}` |
| Account identity | `GET /api/whoami-v2` |
| Cloud inference for agents | `POST https://router.huggingface.co/v1/chat/completions` |

Downloads are handled by a background `URLSession` and support **progress, pause, resume
(via `resumeData`), cancel and delete**. Free disk space is shown before every download,
and repositories over 1 GB show an explicit `Model size: XX GB` warning.

**Nothing is downloaded automatically.** The Files tab of a model lists every artefact with
its format, quantization and byte size; you tick the files you actually want.

### Supported formats

| Format | Detected from | Runtime |
|---|---|---|
| GGUF | `.gguf` | llama.cpp |
| SafeTensors | `.safetensors` | not executable on iOS (convert first) |
| ONNX | `.onnx`, `.onnx_data` | ONNX Runtime GenAI |
| Core ML | `.mlpackage`, `.mlmodelc`, `.mlmodel` | Core ML |
| MLX | `.npz`, `mlx-*` | MLX Swift (8 GB+ devices) |
| TFLite | `.tflite` | not supported on iOS |
| PyTorch | `.bin`, `.pt`, `.pth`, `.ckpt` | not executable on iOS |

Quantization (`Q4_K_M`, `Q8_0`, `IQ3`, `F16`, …) is parsed from the filename and used to
estimate the working set.

### Models tab
Four tabs — **Discover · Downloaded · Running · Favorites** — with a prominent
🤗 **HUGGING FACE** entry point and a `Search Hugging Face models…` field.

Each downloaded model card shows name, size, format, quantization, parameter count,
runtime and status, plus **Start** and **Delete**. If a model can't run on the device the
app says exactly why, e.g.

> **This model cannot be loaded on this device.**
> Estimated working set is 9.4 GB but this device can only dedicate about 3.3 GB to a model
> (6 GB total RAM). Pick a smaller parameter count or a lower quantization such as Q4_K_M.

### Find Model for Task
Describe what you need in plain language ("Мне нужна модель для программирования на Mac")
and the app maps that onto real Hub filters, then shows name, size, format, supported
languages, purpose, license and a link to Hugging Face. You choose what to download.

### AI Agent Builder
Create agents with **Name, Description, Model, System Prompt, Temperature, Max Tokens,
Tools and Permissions**. The model can be a **Cloud Model** (HF Inference or any
OpenAI-compatible endpoint) or a **Downloaded Hugging Face Model**.

### Tools

- **📁 Files** — create, read, edit, append, list, tree, mkdir, delete, **ZIP**, analyze
  documents. Confined to `Documents/Workspace` inside the app sandbox.
- **🌐 Web** — search (DuckDuckGo HTML endpoint, no key), open pages, extract readable text,
  analyze site structure, save results to the workspace.
- **🐙 GitHub** — list repos, browse and read code, create branch, create/update files
  (real commits), unified diff, open Pull Requests.
- **💻 Computer** — macOS / Windows / Linux through the companion daemon, with explicit
  user permission.

### Agent Workspace
A live console showing exactly what the agent is doing:

```
AI Agent
────────────────────
Model: Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf
Status: Running
PLAN
✓ Analyze task
✓ Search files
→ Generate code
○ Run tests
○ Create Git commit
TOOLS
🌐 Web   📁 Files   💻 Computer   🐙 GitHub
OUTPUT
...
```

Every tool call, tool result, error and final answer is timestamped in the Activity feed.

### GitHub agent flow
`task → analyze → plan → generate files → run/verify → show diff → ask confirmation →
commit → push / Pull Request`. The **diff is always presented for approval before anything
is published**; rejecting it tells the agent to stop rather than retry.

---

## Project layout

```
AIAgentHub.xcodeproj/          Xcode 16 project (file-system synchronized group)
AIAgentHub/
  App/                         Entry point, tab shell, theme
  Core/
    Models/                    HF DTOs, formats/runtimes, LocalModel, Agent types
    Storage/                   ModelStorage, ModelLibrary, AgentStore, GitHubStore
    Security/                  KeychainStore
    Utils/                     Formatting, DeviceCapabilities
  Features/
    Home/ HuggingFace/ Models/ Agents/ Workspace/ GitHub/ Settings/
  Services/
    HuggingFace/               HuggingFaceAPI, DownloadManager
    GitHub/                    GitHubAPI
    Agent/                     AgentRuntime, ToolRegistry, DiffBuilder
    Tools/                     FileTool, WebTool
    Inference/                 InferenceEngine + llama.cpp / Core ML / ONNX / MLX adapters
    Companion/                 CompanionClient
  Resources/                   Info.plist, entitlements, asset catalog
Companion/aiagenthub_companion.py   Desktop companion daemon (stdlib only)
scripts/build_ipa.sh                Signed & unsigned IPA builds
.github/workflows/ios.yml           CI that produces an unsigned IPA artifact
```

---

## Requirements

- macOS 14+ with **Xcode 16** or newer
- iOS 17.0+ target (iPhone and iPad)
- An Apple Developer account for signed builds (a free account works for 7-day device installs)

---

## Build & run

```bash
git clone <this repo>
cd TheMiniAI-app-for-ios-only
open AIAgentHub.xcodeproj
```

Select the **AIAgentHub** scheme, pick a simulator or your device, press ⌘R.
The project uses a *file-system synchronized group*, so any `.swift` file you add under
`AIAgentHub/` is compiled automatically — no pbxproj editing needed.

For a device build, set your team once:
`Target → Signing & Capabilities → Team`, and change the bundle id
`app.aiagenthub.ios` to something unique to you.

---

## Building an IPA

### Unsigned (simulator testing, AltStore/Sideloadly, later re-signing)

```bash
./scripts/build_ipa.sh --unsigned
# → build/AIAgentHub-unsigned.ipa
```

### Signed (device, Ad Hoc, TestFlight)

```bash
./scripts/build_ipa.sh --team ABCDE12345 --method development
# other methods: ad-hoc | app-store | enterprise
# → build/ipa/AIAgentHub.ipa
```

The script archives with `xcodebuild archive`, writes an `ExportOptions.plist`, then exports
with `xcodebuild -exportArchive -allowProvisioningUpdates`.

### CI

Pushing to any branch runs `.github/workflows/ios.yml` on a macOS runner and uploads
`AIAgentHub-unsigned-ipa` as a build artifact.

> **Note:** an IPA can only be produced on macOS with Xcode — Apple's toolchain does not run
> on Linux. Everything needed to produce it is in this repo; run the script (or the CI job)
> on a Mac.

---

## Connecting Hugging Face

**Settings → 🤗 Hugging Face → Connect Hugging Face**

AI Agent Hub uses the official **User Access Token** mechanism. Create a token at
<https://huggingface.co/settings/tokens> with `read` scope (add `write` only if you need it),
paste it once, and the app verifies it against `/api/whoami-v2`.

- The token is stored in the **iOS Keychain** with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — never in `UserDefaults`, never in backups.
- **Your password is never requested or stored.**
- A token unlocks gated repos (after you accept their license on the website), private models,
  and higher rate limits. Public browsing works without one.

---

## Connecting GitHub

**GitHub tab → Connect**. Paste a fine-grained personal access token with
*Contents: read & write* and *Pull requests: read & write* on the repositories you choose.
Stored in the Keychain, used only against `api.github.com`.

The agent can then create branches, commit files and open PRs — always behind the
confirmation sheet showing the unified diff.

---

## Computer companion

`Companion/aiagenthub_companion.py` is a dependency-free Python 3 daemon that runs on your
**macOS, Windows or Linux** machine.

```bash
python3 Companion/aiagenthub_companion.py \
    --root ~/Projects \
    --host 0.0.0.0 \
    --allow-shell \
    --auto-allow git
```

It prints a 6-digit pairing code and its LAN address. In the app go to
**Settings → 💻 Computer companion**, enter the address and the code, and tap **Pair**.

Security properties:

| Control | Behaviour |
|---|---|
| Pairing | one-time 6-digit code → random 256-bit pre-shared key, stored in the iOS Keychain |
| Auth | `Authorization: Bearer <key>` required on every request; constant-time comparison |
| Filesystem | all reads/writes confined to `--root` directories; path traversal rejected |
| Shell | off unless `--allow-shell`; non-allow-listed commands prompt on the desktop |
| Writes & exec | the phone also shows a confirmation sheet before the agent proceeds |
| Binding | `127.0.0.1` by default; LAN exposure is opt-in |

API surface: `GET /v1/hello`, `POST /v1/pair`, `/v1/fs/list`, `/v1/fs/read`, `/v1/fs/write`,
`/v1/exec`.

---

## Local inference runtimes

`Services/Inference/InferenceEngine.swift` defines a runtime-agnostic protocol with adapters
for llama.cpp, Core ML, ONNX Runtime and MLX. The GGUF adapter is written against a
`LlamaFramework` module and is activated by `#if canImport(LlamaFramework)`.

To enable real on-device generation, add one of these in
*File → Add Package Dependencies…* and expose it as `LlamaFramework`:

- **llama.cpp (Swift)** — <https://github.com/ggml-org/llama.cpp> (`swift/` package), or
- **LLM.swift** — <https://github.com/eastriverlee/LLM.swift>, or
- **MLX Swift Examples** — <https://github.com/ml-explore/mlx-swift-examples> for MLX.

Until a runtime is linked, the app does **not** fake generation: it tells you precisely
*"The llama.cpp runtime is not linked into this build"* and everything else (search,
download, management, cloud-backed agents) works normally.

Device fitness is computed in `DeviceCapabilities`: weights are estimated from parameter
count × bits-per-weight of the detected quantization, plus KV-cache and runtime overhead,
and compared against a conservative share of physical RAM (45–55%).

---

## Offline Mode

Enable globally in **Settings → Offline Mode**, or per-agent under **Permissions → Offline Mode**.

When on:
- the agent must be bound to a **downloaded** model (cloud bindings are refused with a clear message);
- inference runs on device, no network call is made for generation;
- Web, GitHub and Computer tools are disabled for that agent;
- files stay in the app sandbox and run history stays in Application Support.

If the selected model's runtime can't execute locally on iPhone, the app says so instead of
pretending to run.

---

## iOS sandbox & security

- All model files live in `Application Support/Models/<owner__repo>/<revision>/<file>` and are
  excluded from iCloud backup. Agent files live in `Documents/Workspace` (exposed via
  `UIFileSharingEnabled`, so you can get them out through the Files app).
- `FileTool` resolves and validates every path against the workspace root — traversal outside
  is rejected with an explicit error. No private APIs, no jailbreak paths, no attempts to reach
  system directories.
- Secrets (HF token, GitHub token, OpenAI-compatible key, companion PSK) live only in the
  Keychain; **Settings → Erase all stored tokens** wipes them.
- `NSLocalNetworkUsageDescription` is declared for companion discovery, and ATS local
  networking is scoped to the local network exception only.

---

## Limitations & honesty notes

These are real constraints, stated plainly rather than hidden behind mock UI:

1. **IPA generation requires macOS + Xcode.** The repo contains the full project and build
   script; run it on a Mac or via the included GitHub Actions workflow.
2. **On-device generation needs a runtime package** (see above). Without it the model manager,
   Hub integration and cloud-backed agents are fully functional, and local Start reports the
   missing runtime honestly.
3. **Core ML / ONNX / MLX text generation** adapters are wired but report "runtime not linked"
   until you add the corresponding package; GGUF via llama.cpp is the shortest path.
4. **iOS background downloads** continue while the app is backgrounded but the system may
   throttle them; huge multi-GB downloads are best done on Wi-Fi with the app in the foreground.
5. **DuckDuckGo HTML** is used for web search because it needs no API key; if the markup
   changes, `WebTool.parseDuckDuckGo` is the single place to adjust.

---

## License

Provided as-is for the repository owner. Model files you download from Hugging Face remain
subject to their own licenses, shown on each model's detail screen.
