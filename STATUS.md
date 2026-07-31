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

Last updated: 2026-07-30, from the macOS/mobile machine.

---

## Mobile (iOS + Android)

### Recently completed (2026-07-30)
- **Android: fixed "Provided less images than expected" crash on the turn after any image
  turn.** Android rebuilds its whole conversation from scratch every local turn (unlike iOS's
  one persistent Conversation, which only ever sends the new uncommitted turn) — the local
  history builder was re-attaching a past turn's image bytes on every rebuild, which the
  engine (`maxNumImages=1`) doesn't handle the way a live turn's image does. Fix: only the
  current turn keeps its image; past turns keep the text, drop the bytes. iOS needed no
  change — confirmed unaffected by both code review and a live test. `1b5dd77`.

### Recently completed (2026-07-29) — tagged `v2.16-json-leak-settings`
- **Tool-error JSON leak on Settings → Developer → Inference Tests screens — fixed, both
  platforms.** Same class of bug as the chat-bubble fix: `TestView.swift`'s and
  `PythonTestScreen.kt`'s `evaluate()` reused one raw string for both pass/fail detection
  (must stay raw — that's what's being tested) and for what's displayed. Fix: detection stays
  on the raw string; a separate humanized variant (`ToolResult.humanReadable()`) is used
  everywhere the result is actually rendered. Android also got iOS's existing "no model
  loaded" warning (disabled Run button + banner) — a misleading "12 failed" turned out to
  just mean no model was loaded.
- **Found a real, deep architectural limitation — partially mitigated, not fully fixed.**
  iOS's non-multimodal (text-only) `LiteRtLmEngine` session can only exist once per engine
  lifetime (SDK constraint) — `resetConversation()` can't give it a true fresh start, so the
  real native KV-cache keeps every "reset" turn's tokens forever. Enough independent
  conversations/tests on one loaded text-only model (e.g. E4B) eventually exhaust the real
  context ceiling and every `generate_content` call starts failing — confirmed via native log.
  Not test-only: this can hit real users hitting "New Chat" repeatedly. **Fixed**: broadened
  `ChatView.swift`'s existing auto-recovery (force-unload + reload) to also catch this
  error string, not just the multimodal one, so text-only models get the same safety net.
  **Attempted and reverted**: reloading the model before every Inference-Tests E2E test made
  things worse via a different failure (climbing resident memory across reload cycles,
  eventually failing even a freshly-recreated engine) — reverted to the original behavior.
  Confirmed via a force-kill + fresh relaunch that this is pure within-run accumulation, not
  leftover state from a prior run — identical 5 E2E failures every time regardless. Also
  found `chat()`'s `maxTokens` param (`LiteRtLmEngine.swift:866`) is dead code — never
  referenced in the function body, so tuning it does nothing; the real per-turn output cap is
  a hardcoded 2048 set once at `load()` time. **Decision: stop here, treat as a known/expected
  limitation** — a real fix means either touching the production-shared 2048 cap or only
  partially delaying the failure, and that trade-off wasn't worth chasing further today.
  Whether `unload()` genuinely leaks native memory needs Instruments/memory-graph profiling to
  answer; not diagnosable from source alone. Instead added a plain-language note under the
  Inference Tests summary bar, both platforms, shown whenever a test fails, so a partial-run
  failure doesn't read as a regression. **Verified 2026-07-29 from a clean device restart:
  full 27-test suite — 26 passed, 1 skipped, 0 failed.** Full writeup in local memory
  `project_gemma4pilot.md`, not this repo.

### Recently completed (2026-07-28, later)
- **New Help tab, both platforms** — new bottom-nav tab explaining EcoInference's
  model-interaction features (automatic tool-calling, the `use tool` command, images,
  local/cloud routing + how to set up a free Gemini API key). Deliberately scoped to
  model-interaction only, not general app chrome (Settings/Models are self-explanatory UI).
  `use tool` examples are tappable cards that pre-fill the chat input via the existing
  deep-link mechanism. **Found and fixed a real pre-existing gap on Android**: its deep-link
  handling only ever switched tabs, never actually read `prefill`/`autoSend` — meaning
  `ecoinference://chat?message=...` had silently done nothing on Android since it was added.
  Also fixed on Android: text hardcoded to a fixed color instead of the theme-aware color the
  rest of the app uses (poor contrast in light mode), two missing experimental-API opt-ins,
  and a low-contrast link color — all found via live device testing, not just compiling clean.

### Recently completed (2026-07-28)
- **Tool-error JSON leaking into chat bubbles — fixed, both platforms.** Tool errors are
  `{"error":"..."}` JSON meant for the model, not the user — added `ToolResult.displayText`/
  `humanReadable()` to unwrap it into a clean "⚠️ <message>" line (Python tracebacks reduced to
  just their summary line). Verified with 6 deterministic unit tests, not just live spot checks.
  Turned out Android's production chat UI already discarded tool output entirely, so this
  specific leak was iOS-only in practice — the fix was still added to Android for parity.
- **`use tool <request>` command made to actually execute code, and ported to Android from
  scratch.** Previously iOS-only and non-functional — it only ever displayed model-generated
  Python as a read-only code block, never ran it (despite there being a working embedded Python
  interpreter already available via the same runner the automatic `run_python` tool uses). Now
  wired to actually execute, with real defensive hardening found through live debugging: fence-
  marker extraction fixed for both truncated-response and stray-marker cases; a genuine
  token-budget truncation issue traced to the model's fixed total prompt+response budget (tried
  raising E4B's ceiling 4096→8192, confirmed **unsafe** — the model loads fine but the first
  generation fails outright, meaning it exceeds what the `.litertlm` bundle was compiled to
  support; reverted to 4096); fixed by shrinking the prompt's own token cost and asking for
  compact, non-human-readable code instead (Python runs the same either way); added a 30s
  execution timeout and non-code/truncation detection so a bad generation never leaves the user
  stuck or executes obvious garbage. Full port to Android (`use tool`/`list tools` detection,
  compact prompt, execution, new "code"/"tool" message-bubble styles) worked on the first
  live-device attempt, since all the hard debugging happened on iOS first. Full writeup with
  exact log evidence in local memory `project_gemma4pilot.md`, not this repo.

### Recently completed (2026-07-27)
- **About section on Settings screen, both platforms** — replaces iOS's bare version-only row
  and Android's hardcoded static footer with a real About block (🌿, name, tagline, dynamic
  version, LiteRT-LM attribution), matching desktop's existing About screen.
- **"Try with Cloud" was dropping the attached image, both platforms** — `retryWithCloud()`
  never actually had the image available to re-send (iOS hardcoded `image: nil`; Android read
  a field that was only ever populated on the user bubble, never the assistant one despite a
  comment claiming it worked). Fixed by storing the source image on the assistant message at
  creation time.
- **Local vision + a custom text question made the model deny having an image, both
  platforms** — confirmed via native engine logs that the image genuinely reached the vision
  encoder and prefill completed; the model's own generation just didn't ground on it for
  specific questions (worked fine for the generic auto-filled "Describe this image." prompt).
  Root cause: the tool-calling system prompt primes the model to look for a tool for
  specialized questions. Fix: append an explicit "you already have vision, no tool needed"
  nudge to the outgoing inference text (not the displayed bubble) when an image accompanies
  custom text. Confirmed working live on iPhone 15 Pro and a Xiaomi 24030PN60G (both correctly
  identified a bird from a photo + "What bird is this").

- **Stop button — a chain of five confirmed bugs, both platforms, all fixed and live-device
  verified.** What started as "Stop doesn't seem to work" uncovered: (1) Android had a real
  native SIGSEGV crash — cancelling the coroutine closed the native `Conversation` while a
  background thread was still decoding on it; fixed via the SDK's `Conversation.cancelProcess()`
  called before teardown. (2) iOS Stop button UX — changed to an icon, added immediate
  "Stopping…" feedback instead of looking unresponsive during the real multi-second delay before
  the blocking native call returns. (3) iOS: cancelling mid-prefill was found to genuinely
  corrupt the speculative-decoding "drafter" model state (confirmed via native log — a
  subsequent turn failed with a real XNNPACK tensor-allocation error) even though the
  cancellation itself completes cleanly — reverted an initial "skip the safety unload for
  user-requested stops" change, always force-unload now, but auto-reload the same model right
  after so it's transparent rather than stranding. Android has no equivalent risk (doesn't use
  speculative decoding at all) so this wasn't ported there. (4) iOS: found a real stuck-keyboard
  trap with no way out except force-quit, when the model auto-unloaded mid-chat — added an
  explicit "Done" button plus auto-dismiss on unload; ported a defense-in-depth version to
  Android. (5) Android: a cancelled turn's image-bearing user message was still being replayed
  as dangling history on the next send (no paired assistant reply), causing a native
  "Provided less images than expected in the prompt" error — fixed by dropping the whole
  cancelled (user, assistant) pair from history, not just the empty assistant half. Full
  writeup with exact log evidence in local memory `project_gemma4pilot.md`, not this repo.

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
- Android `minSdk` bumped 26 → 30 — `.litertlm` models require API 30+; a Galaxy S9 (Android
  10/API 29) was confirmed to hard-fail loading the native `libLiteRtLm.so` (`54d2d9f`).
  S9-class hardware is now explicitly out of scope.

### Deferred / not started
- Mobile model downloads still go through the presigned-URL Firebase Function round-trip, not
  the direct public-CDN pattern desktop now uses. Not broken, just the older/costlier path.
- Sharing prompts / friending — future feature, no design yet.
- **MLX Swift explored as a possible fix for iOS's disabled E4B vision — deferred, not
  started.** MLX (Apple's on-device ML framework, Metal-native) could potentially run vision
  on `gemma-4-e4b-it-4bit` (5.18 GB on `mlx-community`) where LiteRT-LM currently can't
  (SigLIP ops not XNNPack-delegatable). Target device discussed: iPad Pro M5, 16GB. No
  prototype built yet — explicit "hold off, return to later." Full model shortlist and
  reasoning in local memory `project_gemma4pilot.md`, not this repo.

---

## Desktop (Electron)

### Recently completed
- **Qwen3-VL-4B-Instruct added to the model catalog (Windows ARM64, `74410ae`)** — second
  GenieX/NPU model alongside the existing Qwen3-8B, confirmed working via the same backend
  architecture (Snapdragon X2 chip) with zero changes needed to `AppContext`/`ModelsScreen`.
  Also wires up real image-attach support in `ChatScreen.tsx`, gated on a new
  `supportsImageInput` flag, so the VL model's vision capability is actually usable rather
  than just advertised in the catalog.
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
