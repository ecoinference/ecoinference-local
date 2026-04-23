# Gemma 4 Pilot

On-device Gemma 4 inference with a local REST API — two Flutter apps for Android & iOS.

```
AIServer/   Inference server  — downloads & runs Gemma 4, exposes localhost REST API
AIClient/   Chat client       — Flutter/Dart UI that calls AIServer's REST API
```

---

## Architecture

```
AIServer (Flutter + native bridge)
 ├─ Setup wizard: Kaggle creds → model picker → download
 ├─ Native inference: Google AI Edge LLM Inference API (MediaPipe Tasks GenAI)
 │    Android → Kotlin InferencePlugin.kt
 │    iOS     → Swift  InferencePlugin.swift
 └─ shelf REST server on localhost (port configurable, default 8080)

AIClient (Flutter / setState — FlutterFlow compatible)
 ├─ Connection screen: host + port entry, health check
 └─ Chat screen: full conversation history, system-prompt support
```

---

## REST API (AIServer)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Server status + model info |
| GET | `/v1/models` | Loaded model list |
| POST | `/v1/models/load` | `{ "model_id": "..." }` |
| POST | `/v1/chat/completions` | OpenAI-compatible chat |
| POST | `/v1/completions` | OpenAI-compatible text completion |

All responses are JSON. Schema matches the OpenAI API so any OpenAI-compatible client works.

---

## AIServer Setup Flow

1. Launch AIServer on device.
2. Enter your **Kaggle username** and **API key** (kaggle.com → Account → API → Create Token).
3. Select model variant:
   - **Gemma 4 1B INT4** (~650 MB) — best for all devices
   - **Gemma 4 4B INT4** (~2.5 GB) — better quality, needs ≥6 GB RAM
4. Download completes → model loads → server starts.
5. Home screen shows the base URL and available endpoints.

---

## AIClient Usage

1. Launch AIServer first (same device or same local network).
2. Open AIClient, enter host (`127.0.0.1`) and port (`8080`).
3. Tap **Connect** — AIClient checks `/health` and navigates to the chat screen.
4. Chat away.

---

## Requirements

### AIServer — Android
- Android 8.0+ (API 26), 64-bit device
- MediaPipe Tasks GenAI `0.10.22`

### AIServer — iOS
- iOS 16.0+, A12 Bionic or later
- MediaPipeTasksGenAI + MediaPipeTasksGenAIIOS pods `0.10.22`

### AIClient — Android & iOS
- Android 5.0+ / iOS 12+ (standard Flutter requirements)

---

## Build

```bash
# AIServer
cd AIServer && flutter pub get && flutter run

# AIClient
cd AIClient && flutter pub get && flutter run
```

For iOS, run `pod install` inside `AIServer/ios/` before building.

---

## Model URLs

Model `.task` files are downloaded from Kaggle Models:

| Variant | Kaggle path |
|---------|-------------|
| 1B INT4 | `google/gemma-4/tfLite/gemma4-1b-it-gpu-int4/1` |
| 4B INT4 | `google/gemma-4/tfLite/gemma4-4b-it-gpu-int4/1` |

> **Note:** Kaggle may update model versions. If a download fails, check
> `AIServer/lib/constants/model_catalog.dart` and update the URL/version number.

---

## FlutterFlow Integration

AIClient uses plain `setState` with no external state management, making it
straightforward to import into FlutterFlow:

- Copy `lib/models/` and `lib/services/api_service.dart` into your FlutterFlow
  custom code.
- Call `ApiService(config).chatCompletion(messages: ...)` from any action.
