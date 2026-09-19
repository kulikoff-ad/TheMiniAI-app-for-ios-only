# AI Agent Hub — Documentation

Полная документация проекта. Все документы на русском и английском.

## Содержание

- [Архитектура](ARCHITECTURE.md)
- [Hugging Face интеграция](HUGGINGFACE.md)
- [Агенты и инструменты](AGENTS.md)
- [Companion — подключение компьютера](COMPANION.md)
- [Безопасность и разрешения](SECURITY.md)
- [Локальные модели и рантаймы](RUNTIMES.md)
- [Сборка IPA](BUILD_IPA.md)

## Быстрый старт

1. `git clone https://github.com/kulikoff-ad/TheMiniAI-app-for-ios-only.git`
2. `open AIAgentHub.xcodeproj`
3. Выберите схему `AIAgentHub` и устройство, нажмите `⌘R`
4. Для установки на iPhone: `Target → Signing & Capabilities → Team` → выберите вашу команду, измените `Bundle Identifier`
5. `Product → Archive → Distribute App → Export IPA`

Подробнее: [BUILD_IPA.md](BUILD_IPA.md)
