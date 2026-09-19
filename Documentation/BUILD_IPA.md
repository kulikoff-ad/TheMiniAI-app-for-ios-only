# Сборка IPA

> IPA собирается только на macOS с Xcode — toolchain Apple не работает на Linux.

## Требования

- macOS 14+, Xcode 16+
- iOS Deployment Target 17.0 (iPhone + iPad)
- Apple Developer account (free подходит для 7-дневной установки)

## 1. Открыть проект

```bash
git clone https://github.com/kulikoff-ad/TheMiniAI-app-for-ios-only.git
cd TheMiniAI-app-for-ios-only
open AIAgentHub.xcodeproj
```

Выберите схему `AIAgentHub`, симулятор или устройство, `⌘R`.

Проект использует *file-system synchronized group*: любой `.swift` под `AIAgentHub/` компилируется автоматически без правки `pbxproj`.

## 2. Signing

`Project → Target AIAgentHub → Signing & Capabilities → Team` → выберите вашу команду.

Если Bundle ID `app.aiagenthub.ios` занят — смените на уникальный, например `app.yourname.aiagenthub`.

## 3. Собрать и запустить

`⌘R` на симуляторе/устройстве.

## 4. Собрать IPA

### Unsigned (для AltStore / Sideloadly / последующей подписи)

```bash
./scripts/build_ipa.sh --unsigned
# → build/AIAgentHub-unsigned.ipa
```

### Signed

```bash
./scripts/build_ipa.sh --team ABCDE12345 --method development
# methods: development | ad-hoc | app-store | enterprise
# → build/ipa/AIAgentHub.ipa
```

Скрипт делает `xcodebuild archive` → `ExportOptions.plist` → `xcodebuild -exportArchive`.

## 5. Archive вручную (Xcode UI)

`Product → Archive` → `Distribute App` → `Custom` → `Export` → выберите `development` / `ad-hoc` → получите IPA.

## 6. Установка IPA на iPhone

- **AltStore**: перетащите IPA в AltServer → Install.
- **Sideloadly**: откройте Sideloadly, выберите IPA и Apple ID, нажмите Start.
- **TestFlight**: загрузите через `Transporter` или `xcodebuild -exportArchive` с `method=app-store`.

## CI

Каждый push запускает `.github/workflows/ios.yml` на `macos-15`:

1. `xcodebuild -list` — проверка проекта
2. `./scripts/build_ipa.sh --unsigned`
3. публикация артефакта `AIAgentHub-unsigned-ipa`
4. создание/обновление релиза `build-<run_number>` с прямой ссылкой на IPA

Лог сборки публикуется комментарием к коммиту через `gh api`.
