# Local Inference Runtimes

| Формат | Детект по имени файла | Рантайм | Статус на iOS |
|---|---|---|---|
| GGUF (.gguf) | `*.gguf` | llama.cpp | ✅ (рекомендуется для телефонов) |
| SafeTensors | `*.safetensors` | — | ❌ конвертируйте в GGUF/CoreML/ONNX |
| ONNX | `*.onnx` | ONNX Runtime GenAI | ✅ |
| Core ML | `*.mlpackage`, `*.mlmodelc`, `*.mlmodel` | Core ML | ✅ |
| MLX | `*.npz`, `mlx-*` | MLX Swift | ⚠️ только ≥8GB RAM (iPhone 15 Pro+, iPad Pro) |
| TFLite | `*.tflite` | — | ❌ |
| PyTorch | `*.bin`, `*.pt`, `*.pth` | — | ❌ |

Квантование парсится из имени файла: `Q2_K … Q8_0, IQ2/IQ3/IQ4, F16/BF16/F32, INT4/INT8`.

## Оценка памяти

```
bits = Quantization.bitsPerWeight(quantString)
weights = params * bits / 8   (или sizeBytes если params неизвестны)
estimated = weights * 1.22 + 180MB
budget = 0.55*RAM если RAM≥6GB иначе 0.45*RAM
canRun = runtime.runsOnDevice && estimated < budget && (runtime≠mlx || RAM≥8GB)
```

Если `canRun == false`, карточка модели показывает точную причину, а кнопка Start отключена.

## Как запустить модель

`ModelsView → LocalModelDetailView → Start`. Это отмечает модель как running и позволяет агенту с `binding.local == model.id` использовать `InferenceEngineFactory.make(for: model)` → `LlamaCppEngine / CoreMLEngine / ONNXEngine / MLXEngine`. В текущей сборке `LlamaCppEngine` содержит обоснование интеграции (требует под-модули llama.cpp) и fallback на cloud, если локальный бинарник не слинкован.

Для production: добавьте сабмодуль `llama.cpp` и `onnxruntime-genai` как XCFramework и реализуйте `InferenceEngine.complete` нативными вызовами.
