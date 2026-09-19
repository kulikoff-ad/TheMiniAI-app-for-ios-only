# Hugging Face

Используется официальный Hub REST API: https://huggingface.co/docs/hub/api

| Задача | Эндпоинт |
|---|---|
| Поиск | `GET /api/models?search=&filter=&pipeline_tag=&author=&sort=&direction=-1&limit=&full=true&config=true` |
| Деталь модели | `GET /api/models/{id}/revision/{rev}?blobs=false` |
| Дерево файлов | `GET /api/models/{id}/tree/{rev}?expand=true&recursive=true` |
| README | `GET /{id}/raw/{rev}/README.md` |
| Скачать файл | `GET /{id}/resolve/{rev}/{path}?download=true` |
| WhoAmI | `GET /api/whoami-v2` |
| Cloud Inference (агенты) | `POST https://router.huggingface.co/v1/chat/completions` |

Токен — User Access Token, создаётся на https://huggingface.co/settings/tokens (scope `read`, опционально `write`). Хранится только в Keychain.

## Фильтры «AI for iPhone»

В приложении есть отдельный режим **📱 AI for iPhone** (экран Phone AI). Пользователь вводит фразу вроде:

- “AI для программирования”
- “маленькая модель для iPhone”
- “AI до 2 GB”

`TaskIntent.parse` (оффлайн, без LLM) извлекает:

- ключевые слова → `search`
- теги (`gguf`, `coreml`, `onnx`, `mlx`)
- `pipeline_tag` (`text-generation`, `translation`, …)

Затем делается `searchModels` с этими фильтрами, а после — **проверка совместимости** каждого результата:

```
DeviceCapabilities.evaluate(model: LocalModel)
  ├─ runtime.incompatibilityReason? → нельзя
  ├─ MLX требует ≥8GB RAM? → нельзя
  └─ estimated = bitsPerWeight(quant) * params + 0.22*weights + 180MB
      budget = 0.55*RAM (≥6GB) иначе 0.45*RAM
      estimated > budget ? → нельзя + причина
```

Пользователь видит для каждого файла:

- формат (GGUF, SafeTensors, ONNX, Core ML, MLX…)
- quantization (`Q4_K_M` и т.д.)
- размер в байтах
- runtime (`llama.cpp`, `Core ML`, `ONNX Runtime`, `Unsupported`)
- предупреждение если формат не исполняется на iOS

Никогда не утверждаем совместимость только по размеру — всегда проверяем формат + рантайм.

## Загрузка

`DownloadManager` — `URLSessionConfiguration.background` с идентификатором `app.aiagenthub.downloads`:

- прогресс: `didWriteData` → `received / total`
- пауза: `cancel(byProducingResumeData:)`
- возобновление: `downloadTask(withResumeData:)`
- отмена + удаление
- проверка свободного места до старта (`freeDiskBytes`)
- предупреждение для файлов >1GB: `Model size: XX GB`

Экран загрузки показывает:

```
Downloading model...
████████████░░░░ 78%
3.1 GB / 4.0 GB
```

Ничего не скачивается автоматически — пользователь ставит галочки на нужные файлы.
