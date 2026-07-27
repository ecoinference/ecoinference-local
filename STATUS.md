# EcoInference — Project Status

This file is the cross-session, cross-machine status board for this repo. The user runs
Claude Code across three machines against this same GitHub repo:
- **This machine (macOS)** — mobile (iOS + Android) and the macOS build of the Electron
  desktop app.
- **Windows 11 ARM64 machine** — Windows desktop build (Snapdragon NPU path).
- **Windows 11 x64 machine** — Windows desktop build (x64 path).

**Convention:** before starting work in a new session, `git pull` and read this file — don't
trust any prior session's memory of "what's done" without checking `git log` too, since work
may have landed from another machine. After finishing meaningful work, update the relevant
section below, commit, and push, so the next session (on any machine) starts from an accurate
picture. Keep entries short and factual — this is a status board, not a design doc.

Last updated: 2026-07-25, from the macOS/mobile machine.

---

## Mobile (iOS + Android)

### Recently completed (2026-07-24)
- Delete confirmation dialog on Models screen, both platforms (`83f2dbb`).
- Storage pre-flight check before starting a model download, both platforms — throws a clear
  "needs ~X MB, only Y MB free" error instead of failing mid-download (`205705a`).
- Budget-exhausted forced-final turn in `AgentLoop`, both platforms — when the tool-call
  iteration cap is hit, injects a "answer now using only what you have" nudge and forces one
  final no-tools turn, instead of just breaking the loop (`205705a`).
- Download speed + ETA shown in Models screen UI, both platforms (`667ebe6`).
- Tool-result security hardening: `wrapUntrusted()` (nonce-delimited markers around tool
  results, defends against indirect prompt injection via e.g. `run_python`'s network access)
  and `truncateToolResult()` (6000-char cap), both platforms (`667ebe6`, plus earlier
  `run_python` findings).
- First-ever test coverage on either platform: iOS `AIiOSTests` (standalone target, no host
  app), Android `src/test/kotlin` JUnit source set. Both cover `AgentLoop` tool-call parsing,
  `wrapUntrusted`, `truncateToolResult` (`667ebe6`).
- iPad blank-screen bug fixed (`UITextEffectsWindow` system overlay was getting the same
  opaque-background treatment as app windows) (`b622d8b`).
- iOS model-download timeout + tool-call parse fallback fixes (`71bf594`).

### Deferred / not started
- **Tool error messages leak raw internal JSON into chat bubbles** — confirmed on iOS
  `PythonTools.swift`'s `run_python` (e.g. `{"error":"'code' parameter is required"}` shown
  as-is in the tool-result bubble). Low severity, cosmetic. Likely affects other tools
  (`ChartTools`, `ImageEditTools`) and both platforms — worth an audit pass, not a one-tool
  patch, when picked up.
- Mobile model downloads still go through the presigned-URL Firebase Function round-trip, not
  the direct public-CDN pattern desktop now uses. Not broken, just the older/costlier path.
- Sharing prompts / friending — future feature, no design yet.
- `minSdk` bumped 26 → 30 on Android (`.litertlm` models require API 30+; a Galaxy S9 on
  Android 10/API 29 was confirmed to hard-fail loading the native lib) — **uncommitted as of
  this writing**, in `AIAndroid/app/build.gradle.kts`.

---

## Desktop (Electron)

### Recently completed
- Full flow verified end-to-end through the real public CDN on macOS: sign in → download →
  load → chat, both `npm run dev` and the packaged `.app`.
- App distribution live: `electron-updater` + `releases.ecoinference.ai`.
- Static, dependency-free `llama-server` (arm64) built from source and bundled into the
  packaged macOS app.
- Windows: Snapdragon NPU / CUDA / Vulkan GPU support work merged (done on the Windows
  machines — see machine-role note above).

### Deferred / not started
- Windows build: tooling is wired (`package:win` runs `electron-vite build` first) but the
  packaged `.exe` has not been verified end-to-end the way macOS was — needs a real run on
  one of the Windows machines with a bundled `llama-server.exe`.
- x64 (Intel) `llama-server` cross-compile — macOS build is arm64-only right now.
- Code signing (macOS notarization + Windows Authenticode) — deferred until the app is more
  stable; without it, `electron-updater` can detect/download updates but installs may be
  Gatekeeper-blocked.
- Vision support for Gemma 4 12B (an `mmproj` file exists upstream, wiring deferred when 12B
  was added).
- RAM/VRAM detection + model recommendation UI — not started.

---

## Reference: findings from PocketPal AI analysis (not EcoInference bugs)

- Two real bugs found in PocketPal AI itself via hands-on testing (interrupted-generation
  repetition loop on backgrounding; GPU/Adreno decode hang) — not yet filed upstream, user
  opted to hold for now.
- Full writeup: local memory `reference_pocketpal_ai.md` (not part of this repo).

## Reference: AIFlutter viability test (untracked in this repo, `AIFlutter/`)

A standalone diagnostic app, not part of the shipped product, built to re-check whether
Flutter's LiteRT-LM bindings (the original reason EcoInference went native) are viable today.
Result: `flutter_gemma`/`flutter_gemma_litertlm`'s FFI-based binding passes all 5 diagnostic
tests (chat, tool calling, cancellation, GPU backend, vision) on both Android and iPhone 15
Pro. **Decision (2026-07-25): stick with native mobile + Electron desktop regardless** — the
finding is good to have on record but isn't changing the architecture. The one test never run
(background-interrupt, the one that actually mirrors PocketPal's Bug A) is a non-blocking
loose end given that decision.
