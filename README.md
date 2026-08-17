# EcoInference

Privacy-first, on-device AI. Most questions are answered entirely on your own hardware —
nothing leaves the device — with an automatic fallback to a cloud model only for the
things a small local model genuinely handles poorly.

The motivation is environmental as much as it is about privacy: inference that runs on
hardware you already own doesn't spin up a datacenter GPU, and doesn't consume the energy
and water that comes with one.

## Licence

The code in this repository is licensed under the **Mozilla Public License 2.0** — see
[LICENSE](LICENSE). MPL is file-level copyleft: modifications to these files stay open, but
you can build proprietary work alongside them.

The **name and brand are handled separately** — see [TRADEMARK.md](TRADEMARK.md). Short
version: fork freely, just call your fork something else.

### The assembled app is not all under one licence

Worth being upfront about, because "the code is MPL" does not mean "the product is freely
usable for anything." Running the app involves several components with their own terms:

| Component | Terms | Notes |
|---|---|---|
| This source code | MPL 2.0 | What the LICENSE file covers |
| Gemma model weights | **Gemma Terms of Use** | **Not** an OSI open-source licence — includes a prohibited-use policy. Redistribution requires providing the terms and a Notice file (see [NOTICE](NOTICE)) |
| LiteRT-LM runtime (iOS, Android) | **Apache 2.0** | Confirmed — permits binary redistribution. Android resolves the official Google artifact via Gradle; iOS fetches prebuilt dylibs via `download_frameworks.sh`. Attribution in [NOTICE](NOTICE); upstream publishes no NOTICE file of its own |
| llama.cpp (desktop) | MIT | Bundled per-platform binaries |
| Chaquopy (Android Python runtime) | **MIT** | Confirmed — open source since 12.0.1, no licence key needed |
| Embedded Python + packages (iOS, Android) | **All permissive** | CPython under the PSF licence, plus numpy/pandas/matplotlib/etc. under BSD, MIT, MIT-CMU and Apache 2.0. Each package's own licence ships beside it in `.dist-info/` — see [NOTICE](NOTICE) |
| Qwen3 8B / Qwen3-VL 4B (NPU) | **Apache 2.0** | Confirmed — upstream Qwen3 weights are Apache 2.0, permissive |
| Llama 3.2 3B 16K (NPU) | **Llama 3.2 Community License** | Requires "Built with Llama" attribution and a Notice file (both present, see [NOTICE](NOTICE)) and compliance with [Meta's Acceptable Use Policy](https://www.llama.com/llama3_2/use-policy) |
| GenieX (NPU orchestration CLI) | BSD 3-Clause | **Not bundled** — the user installs it themselves, and use is also subject to [Qualcomm's Terms of Use](https://www.qualcomm.com/site/terms-of-use), which they accept directly |
| QAIRT / Qualcomm AI Engine Direct | Qualcomm's terms | **Not bundled, and not redistributed by this project** — GenieX downloads the runtime from Qualcomm's own infrastructure onto the user's machine. See the note below before changing that |

The practical upshot: several models' and tools' terms travel with them regardless of what
this repository is licensed under, so the app as a whole carries use restrictions and
attribution obligations the code alone does not. If that matters for your use case, read
each component's terms directly (linked above, plus [NOTICE](NOTICE)) rather than assuming
the MPL covers everything.

> **Note on the Qualcomm NPU path.** Nothing from Qualcomm ships in this app. The packaged
> Windows ARM64 build contains exactly one binary (`llama-server.exe`); `GenieXServer` simply
> invokes `geniex` from `PATH`, the way a tool might shell out to `ffmpeg`. The user installs
> GenieX from Qualcomm's own installer, and GenieX then fetches the QAIRT runtime from
> Qualcomm's release and S3 infrastructure directly. So no redistribution happens here, and
> QAIRT's redistribution terms don't currently bind this project.
>
> **That changes the moment anyone bundles GenieX or QAIRT into the installer** — a tempting
> idea, since it would remove a manual setup step for users. Don't start that work before
> confirming redistribution rights with Qualcomm: the terms are behind a developer-portal
> click-through with no publicly published text, and they could rule the approach out
> entirely.

---

## Layout

```
AIiOS/       iOS app        — Swift / SwiftUI, LiteRT-LM, embedded Python 3.10
AIAndroid/   Android app    — Kotlin / Compose, LiteRT-LM via JNI, Chaquopy Python
AIDesktop/   Desktop app    — Electron + React, llama.cpp (see also: separate repo docs)
functions/   Firebase Functions — presigned model-download URLs, avatar uploads
tests/       Cross-platform test assets
docs/        Engineering notes and device-testing guide
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
- **Desktop on Windows ARM64 / Snapdragon** — additionally requires
  **[GenieX](https://github.com/qualcomm/GenieX) installed separately**, with `geniex` on
  `PATH`. This platform runs the NPU-backed models instead of llama.cpp ones (llama.cpp's own
  GPU backends don't work correctly on Adreno), and the app shells out to `geniex serve`
  rather than bundling it — so **without it, the NPU models won't load**. Grab the Windows
  ARM64 installer from GenieX's releases page; it pulls the QAIRT runtime itself on first
  use. Use of GenieX is subject to [Qualcomm's Terms of Use](https://www.qualcomm.com/site/terms-of-use).

## Development

Start here, in this order:

| Doc | What it's for |
|---|---|
| [STATUS.md](STATUS.md) | Cross-machine status board — what's done, when, and by which commit. Read before starting, update after. |
| [docs/ENGINEERING_NOTES.md](docs/ENGINEERING_NOTES.md) | **Why the code looks the way it does.** Inference constraints, tool-calling contracts, theming rules, and the decisions that look arbitrary without context. Read before touching any of those. |
| [docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md) | Build, install and debug commands per platform, the traps in each, measured performance numbers. |
| [FUTURE_ENHANCEMENTS.md](FUTURE_ENHANCEMENTS.md) | Open items, parity gaps, deferred work, and known limitations that are *not* bugs. |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution process, CLA, and the Android theming convention. |

This repo is worked on from three machines (macOS for mobile, two Windows machines for the
desktop builds), so `git log` is often ahead of any one session's assumptions — pull first.

Both mobile apps have a **Settings → Developer → Inference Tests** screen that runs the
smoke-test suite (inference, Python, cloud, router, vision) directly on-device. Note that a
green run doesn't prove a feature works end-to-end — see
[docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md) for why.
