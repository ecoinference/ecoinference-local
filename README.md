# EcoInference

Privacy-first, on-device AI. Most questions are answered entirely on your own hardware —
nothing leaves the device — with an automatic fallback to a cloud model only for the
things a small local model genuinely handles poorly.

The motivation is environmental as much as it is about privacy: inference that runs on
hardware you already own doesn't spin up a datacenter GPU, and doesn't consume the energy
and water that comes with one.

> **Repo status:** private and not currently licensed for redistribution. Note that the
> app bundles third-party components under their own terms (Google's LiteRT-LM runtime,
> Gemma model weights under the Gemma Terms of Use, llama.cpp on desktop) — these are not
> covered by any license granted here.

---

## Layout

```
AIiOS/       iOS app        — Swift / SwiftUI, LiteRT-LM, embedded Python 3.10
AIAndroid/   Android app    — Kotlin / Compose, LiteRT-LM via JNI, Chaquopy Python
AIDesktop/   Desktop app    — Electron + React, llama.cpp (see also: separate repo docs)
functions/   Firebase Functions — presigned model-download URLs, avatar uploads
tests/       Cross-platform test assets
```

The three clients are **independent native implementations that share a backend**, not a
shared codebase. They deliberately mirror each other's features and UX, so a change to one
usually needs porting to the other — but they do not share code, and desktop doesn't even
share an inference runtime.

## Inference

| | Runtime | Models |
|---|---|---|
| **iOS / Android** | LiteRT-LM (`.litertlm`) | Gemma 4 E2B (~2.5 GB), Gemma 4 E4B (~3.6 GB) |
| **Desktop** | llama.cpp (GGUF) | Gemma 4 E4B (~5 GB), Gemma 4 12B (~6.7 GB) |
| **Desktop (Snapdragon)** | GenieX (NPU) | Qwen3 8B, Qwen3-VL 4B — self-caching, no app-side download |

Model weights are **not** in this repo. They're fetched at runtime from a Backblaze B2
bucket fronted by Cloudflare CDN.

### Platform differences that bite

Vision support is **not** uniform, and findings do not transfer between platforms:

- **iOS** — vision works on E2B only. It's explicitly disabled on E4B: its larger SigLIP
  encoder has ops that aren't XNNPack-delegatable in the current native LiteRT-LM build.
- **Android** — vision works on both E2B and E4B; the Kotlin SDK has no equivalent gap.
- **Desktop** — different runtime entirely, with its own independent constraints.

## Routing

Every prompt goes through a rules engine that picks a tier — **local** or **cloud** (Gemini).
Cloud handles current events, very long creative work, and images the local model can't
process. Users can also force a second opinion with *Try with Cloud* on any reply, and tap
the tier badge under a response to see why it routed where it did.

Rules ship bundled (`default_router_rules.json`, identical across platforms) and can be
updated live via Firebase Remote Config (`router_rules`) without an app release.

Cloud answers require the user's own Gemini API key, entered in Settings. No key ships with
the app, and local inference always works without one.

## Tool calling

The model can call ~18 device and compute tools on its own, no special phrasing required:

`get_battery` · `show_map` · `toggle_torch` · `send_sms` · `send_sos` ·
`get_moon_phase` · `get_sun_times` · `get_dawn_dusk` ·
`compute_stats` · `compute_geometry` · `fit_curve` · `run_fft` ·
`plot_line` · `plot_bar` · `plot_scatter` · `generate_qr` · `edit_image` · `run_python`

Beyond that fixed list, typing **`use tool <request>`** has the model write real Python and
execute it on-device immediately — an actual result, not a code preview. `list tools` shows
what's available.

Tool results are wrapped in nonce-delimited untrusted-content markers and length-capped
before reaching the model, as a defense against indirect prompt injection — `run_python`
has network access.

## Backend

Firebase project `ecoinference-28c31`, shared by all three clients:

- **Auth** — email/password only (deliberate: social sign-in triggers extra App Store review)
- **Firestore** — `users/{uid}` profiles, `usernames/{username}` uniqueness reservations
- **Remote Config** — `router_rules`, `available_models` allowlist
- **Functions** — presigned B2 download URLs, avatar uploads

## Requirements

- **iOS** — 17.0+, Xcode. Run `AIiOS/download_frameworks.sh` to fetch the LiteRT-LM
  xcframeworks (~91 MB, not tracked). Embedded-Python artifacts are built by `setup.sh`.
- **Android** — API 30+ (`.litertlm` fails to load the native lib below this; API 29
  devices are out of scope). Gradle needs an explicit `JAVA_HOME`, e.g. Android Studio's
  bundled JBR.
- **Desktop** — Node + Electron; a `llama-server` binary is bundled per platform.

## Development

`STATUS.md` is the cross-machine status board — read it before starting work, and update it
after. This repo is worked on from three machines (macOS for mobile, two Windows machines
for the desktop builds), so `git log` is often ahead of any one session's assumptions.

Both mobile apps have a **Settings → Developer → Inference Tests** screen that runs the
smoke-test suite (inference, Python, cloud, router, vision) directly on-device.
