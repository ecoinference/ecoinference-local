# Gemma 4 Pilot

On-device Gemma 4 inference with a local REST API — two Flutter apps for Android & iOS.

```
app1/   Inference server  — downloads & runs Gemma 4, exposes localhost REST API
app2/   Chat client       — Flutter/Dart UI that calls app1's REST API
```

---

## Architecture

```
app1 (Flutter + native bridge)
 ├─ Setup wizard: Kaggle creds → model picker → download
 ├─ Native inference: Google AI Edge LLM Inference API (MediaPipe Tasks GenAI)
 │    Android → Kotlin InferencePlugin.kt
 │    iOS     → Swift  InferencePlugin.swift
 └─ shelf REST server on localhost (port configurable, default 8080)

app2 (Flutter / setState — FlutterFlow compatible)
 ├─ Connection screen: host + port entry, health check
 └─ Chat screen: full conversation history, system-prompt support
```

---

## REST API (app1)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Server status + model info |
| GET | `/v1/models` | Loaded model list |
| POST | `/v1/models/load` | `{ "model_id": "..." }` |
| POST | `/v1/chat/completions` | OpenAI-compatible chat |
| POST | `/v1/completions` | OpenAI-compatible text completion |

All responses are JSON. Schema matches the OpenAI API so any OpenAI-compatible client works.

---

## app1 Setup Flow

1. Launch app1 on device.
2. Enter your **Kaggle username** and **API key** (kaggle.com → Account → API → Create Token).
3. Select model variant:
   - **Gemma 4 1B INT4** (~650 MB) — best for all devices
   - **Gemma 4 4B INT4** (~2.5 GB) — better quality, needs ≥6 GB RAM
4. Download completes → model loads → server starts.
5. Home screen shows the base URL and available endpoints.

---

## app2 Usage

1. Launch app1 first (same device or same local network).
2. Open app2, enter host (`127.0.0.1`) and port (`8080`).
3. Tap **Connect** — app2 checks `/health` and navigates to the chat screen.
4. Chat away.

---

## Requirements

### app1 — Android
- Android 8.0+ (API 26), 64-bit device
- MediaPipe Tasks GenAI `0.10.22`

### app1 — iOS
- iOS 16.0+, A12 Bionic or later
- MediaPipeTasksGenAI + MediaPipeTasksGenAIIOS pods `0.10.22`

### app2
- Android 5.0+ / iOS 12+ (standard Flutter requirements)

---

## Build

```bash
# app1
cd app1 && flutter pub get && flutter run

# app2
cd app2 && flutter pub get && flutter run
```

For iOS, run `pod install` inside `app1/ios/` before building.

---

## Model URLs

Model `.task` files are downloaded from Kaggle Models:

| Variant | Kaggle path |
|---------|-------------|
| 1B INT4 | `google/gemma-4/tfLite/gemma4-1b-it-gpu-int4/1` |
| 4B INT4 | `google/gemma-4/tfLite/gemma4-4b-it-gpu-int4/1` |

> **Note:** Kaggle may update model versions. If a download fails, check
> `app1/lib/constants/model_catalog.dart` and update the URL/version number.

---

## FlutterFlow Integration

app2 uses plain `setState` with no external state management, making it
straightforward to import into FlutterFlow:

- Copy `lib/models/` and `lib/services/api_service.dart` into your FlutterFlow
  custom code.
- Call `ApiService(config).chatCompletion(messages: ...)` from any action.
