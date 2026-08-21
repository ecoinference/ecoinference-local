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

Last updated: 2026-08-20, from the macOS/mobile machine.

**Companion docs.** This file is *what happened and when*. Two others cover *why things are
the way they are* — read them before touching inference, tool calling, theming or device
work:
- **[docs/ENGINEERING_NOTES.md](docs/ENGINEERING_NOTES.md)** — architecture, hard-won
  constraints, and the reasoning behind decisions that look arbitrary from the code alone.
- **[docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md)** — build/install/debug commands per
  platform, the traps in each, and measured performance numbers.
- **[docs/](docs/README.md)** — eight more: case studies of expensive bugs, desktop/Electron,
  infrastructure (B2/Cloudflare/Firebase/IAM), prior art, licensing rationale, model
  evaluations, related projects, and the fine-tuning roadmap.
- **[FUTURE_ENHANCEMENTS.md](FUTURE_ENHANCEMENTS.md)** — everything known to be incomplete,
  deferred, or blocking.

---

## Mobile (iOS + Android)

### Recently completed (2026-08-20) — history rewritten for public release

- **Repo renamed `gemma4-pilot` → `ecoinference-local`**, published at
  `github.com/ecoinference/ecoinference-local`. The old name undersold it: "pilot" reads as an
  abandoned experiment, and "gemma4" pins it to one model family when desktop already runs Qwen
  and Llama. The new name pairs with **EcoInference Remote** — local runs on your device,
  remote calls an API — so the split is obvious to anyone browsing the org. See
  [docs/RELATED_PROJECTS.md](docs/RELATED_PROJECTS.md).
  *(The `gemma4-pilot-*` names below are on-disk backup filenames from before the rename, not
  repo references.)*

- **All 256 commits re-authored to `EcoInference <info@ecoinference.ai>`.** 208 of them
  carried a personal Gmail address, which would have become public with the repo. The
  repo-local git config was already correct; the history predated it. Commit *messages* were
  scrubbed too — they referenced a personal dynamic-DNS home-server hostname and a personal
  GitHub account.
- **~150 MB of vendored binaries purged from every commit**: `AIiOS/Frameworks/` (plus dead
  `.xcframework.old/` duplicates), `AIiOS/litertlm_official_extract/`, the iOS `.tar.gz`
  archives, and `AIDesktop/resources/bin/`. 47 files removed, **zero source files touched** —
  verified by diffing the tracked-file list against a pre-rewrite backup bundle.

  | | Before | After |
  |---|---|---|
  | Pack size | 55.6 MB | **3.0 MB** |
  | Tracked in HEAD | 310.6 MB | **2.1 MB** |

  A 310 MB clone was working against the whole point of publishing this.
- **Found and fixed a false claim in the docs.** README and FORKING.md both said the iOS
  xcframeworks were "not tracked" and told forkers to run `download_frameworks.sh`. They
  *were* tracked — the `.gitignore` rules were added after the files had already been
  committed, and gitignore doesn't untrack anything. The claim is now true. `.gitignore` also
  gained the two paths it was missing, verified with `git add --dry-run`.
- **Binaries preserved locally** at `gemma4-pilot-BINARIES-20260820/` beside the repo, and a
  full pre-rewrite bundle at `gemma4-pilot-BACKUP-20260820-212859.bundle`. iOS frameworks are
  re-fetchable via `download_frameworks.sh`; desktop binaries are built or downloaded per
  `docs/DESKTOP.md`.
- **All 21 commit SHAs cited in the docs were remapped** to their post-rewrite equivalents and
  verified to resolve. (The one that doesn't is `571d0d5`, an upstream llama.cpp commit.)

> **If you are reading this on another machine:** the remote history was replaced. `git pull`
> will not work. Re-clone, or `git fetch origin && git reset --hard origin/main` — and check
> for uncommitted work first, because it will be lost.

### Recently completed (2026-08-20) — licence changed to MIT, fork-only

- **Relicensed MPL 2.0 → MIT, and the project no longer accepts pull requests.** The goal
  changed: maximize the chance someone actually uses and forks this, rather than capture value
  from forks or build a contributor community. MIT asks one thing (keep the copyright notice)
  and requires nothing of the maintainer. No public release ever happened under MPL, so the
  change is clean — nothing was ever distributed under the old terms. Reasoning, and why
  Apache 2.0 and 0BSD were passed over, in
  [docs/LICENSING_RATIONALE.md](docs/LICENSING_RATIONALE.md).
- **The CLA blocker is gone** — one of the two remaining pre-publication items. A CLA exists
  only to preserve the ability to relicense later, which otherwise needs agreement from every
  past contributor. With no PRs, no third-party copyright ever enters the codebase, so the
  copyright holder keeps that right permanently with no paperwork. No legal review, no bot.
  **And the other supposed blocker turned out not to be one:** the two HuggingFace tokens
  flagged as unrevoked by the 2026-07-30 audit both return **401** from
  `huggingface.co/api/whoami-v2` — checked 2026-08-20. They are dead and authenticate nothing.
  The audit recorded them as live and nobody re-tested for three weeks; the token list masks
  the *last* four characters while the leak was recorded by its *first*, so they could not be
  matched by eye. **There are now no blockers to making the repo public.**
- **New [FORKING.md](FORKING.md)** — the practical guide that decides whether a fork succeeds:
  every value hardcoded to this deployment (Firebase config in 5 files, CDN/bucket names in 3,
  bundle and namespace identifiers), the per-platform setup traps, and a plain statement of why
  PRs are closed. `CONTRIBUTING.md` is now a short redirect to it.
- **Engineering content moved out of `CONTRIBUTING.md` into
  [docs/CODE_CONVENTIONS.md](docs/CODE_CONVENTIONS.md)** rather than being lost with the
  contribution process — parity rules, the Android theming convention, build-verification and
  regression-isolation discipline. A forker needs these more than a contributor would.
- Swept MPL/CLA references out of `README.md`, `NOTICE`, `TRADEMARK.md` and
  `FUTURE_ENHANCEMENTS.md`. No source file ever carried an MPL header, so there were none to
  strip.

### Recently completed (2026-08-20) — device guardrails and docs migration
- **Device-capability guardrails on Android, driven by real measurements on a Lenovo TB336FU
  tablet (7.6 GB RAM, Mali-G57 MC2).** Loading E4B there caused the screen to blank and other
  apps to be killed — the tablet was under genuine memory pressure, not faulting. E4B needs
  roughly 8 GB *usable*, which an 8 GB-class device doesn't have once the OS takes its share.
  Added `ModelInfo.minRamMb`, set E4B to 8000, and gated the Load button behind a warning
  dialog that reads total device RAM. **Deliberately a warning, not a hard block** — E4B does
  load and run there; it just does so by evicting the rest of the system, and someone testing
  on purpose should be allowed to. E4B's catalog description now says so plainly too.
- **CPU/GPU guidance corrected.** Same tablet, same model (E2B): **GPU held 2,589 MB PSS vs
  CPU's 753 MB** — the weights are copied into GPU memory rather than mapped from the file —
  and decode throughput was effectively identical (5.2 vs 5.1 chunks/s). GPU *did* reach first
  token sooner (29.7 s vs 47.9 s). The load dialog and Settings now steer an unsure user to
  CPU **on the memory argument only**. An earlier draft of this text claimed CPU is often
  faster; that contradicted our own 2026-07-23 benchmark and was wrong — corrected before
  shipping. Note this device is slow either way; the lever there is a smaller model, not
  backend choice.
- **Documentation migration — `docs/` created.** Durable engineering knowledge that had lived
  only in a local assistant memory store (~1,900 lines, machine-local, not portable) is now in
  the repo under `docs/` — ten files, indexed in [docs/README.md](docs/README.md). Beyond the
  engineering notes and device guide, a second pass added `CASE_STUDIES.md` (ten bugs written up
  as narratives, including the wrong turns), `DESKTOP.md` (Electron, the static `llama-server`
  build recipe, release process), `INFRASTRUCTURE.md` (B2/Cloudflare/DNS/Firebase and the IAM
  incident), `PRIOR_ART.md` (why the clients are separate native implementations; the PocketPal
  analysis) and `LICENSING_RATIONALE.md` (licence reasoning, trademark strategy).
  Standing conventions that had lived only in memory are now in `CONTRIBUTING.md`.
  A third pass added `MODEL_EVALUATIONS.md` (Gemma 4 12B on LiteRT-LM measured at 0.61 tok/s
  and shelved; the MLX Swift shortlist), `RELATED_PROJECTS.md` (the boundary between this repo,
  EcoInference Remote, the website and the fine-tuning work — including the standing rule that
  Remote features are never back-ported here) and `ROADMAP_FINETUNING.md`. Build-verification
  and simulator coordinate-scale traps went into `DEVICE_TESTING.md`. **Deliberately not
  migrated:** personal working preferences and anything about the maintainer's own devices —
  see the note in `docs/README.md`.
  `FUTURE_ENHANCEMENTS.md` was rewritten — it had still described a Morse-code receiver for
  the Flutter version of the app, referencing `pubspec.yaml` and a `camera` plugin that no
  longer exist. Prior STATUS entries pointing at "local memory" now point at `docs/` instead.

### Recently completed (2026-08-10)
- **`use tool` was broken for anything location- or time-dependent — fixed (`4e92053`).** The
  Help screen's own moon-phase example failed. Four stacked bugs, the main one being that the
  location preamble was passed to the code-gen *prompt* but never prepended to the code that
  actually runs — so `user_latitude` and friends never existed at runtime, on both platforms.
  Both Inference Tests screens always prepended it correctly, which is why the Python tests
  passed while the feature was broken. Also: neither preamble bound `datetime` unaliased;
  Android's `user_timezone` was a string where the prompt (and iOS) promised a tzinfo; and the
  astral guidance had the wrong signature and no phase-name mapping — now derived from the
  bundled astral 3.2 source and verified across a full lunar cycle. Verified on device: the
  example returns the correct phase.
- **Generated Python now collapsed behind a "Show Python" toggle (`137d43d`, Android).** The
  snippet used to run longer than the screen with the answer off-view. **Build-verified only —
  not yet eyeballed, and not yet ported to iOS.**

### Recently completed (2026-08-04)
- **Android light theme — fixed across five commits.** The app was built dark-first, so
  colours picked for dark surfaces were hardcoded throughout and light mode ranged from
  washed-out to fully invisible: text, section headers, cards, chat bubbles, dividers and
  brand-green icons. Added `ecoAccent` / `ecoBrand` helpers plus `DeepGreen` / `LightBorder`,
  and filled in the light scheme so it mirrors dark slot-for-slot. Dark mode is unchanged —
  regression-checked by screenshot. **The convention is now documented in
  [CONTRIBUTING.md](CONTRIBUTING.md)**, including the two cases where a hardcoded palette
  colour is still correct (fills, and content on surfaces that are dark in both themes) —
  worth reading before touching colours, since a blanket find-and-replace breaks those.
- **Added `SECURITY.md`** — `CONTRIBUTING.md` had linked to it without it existing. Covers
  reporting plus where the real attack surface is (on-device execution of model-generated
  Python with network access, tool results as an injection vector, locally stored keys).

### Recently completed (2026-07-30, later) — open-sourcing prep
- **Licensed under MPL 2.0**, plus `CONTRIBUTING.md` (with CLA rationale) and `TRADEMARK.md`.
  *(Superseded 2026-08-20 — now MIT, fork-only. See the top of this file.)*
  MPL over Apache/GPL deliberately: file-level copyleft keeps changes to our files open
  without blocking commercial use, and unlike the GPL family it has no App Store conflict.
  Trademark — not the licence — is what protects the project name. README now states plainly
  that the assembled app isn't uniformly MPL (Gemma weights carry their own use restrictions).
- **Repo audit ahead of going public.** Removed the dead `AIServer/` Flutter tree (archived
  separately), rewrote the stale README, and fixed a `.gitignore` whose paths had been wrong
  since an old directory rename — leaving `Local.xcconfig` and 91MB of vendored binaries
  unprotected. **Still open before publishing:** revoke two old HuggingFace tokens that
  remain in git history, and get the CLA legally reviewed plus a CLA bot wired up. *(The CLA
  item was dropped 2026-08-20 — fork-only means no CLA is needed.)* (Security
  rules — previously the biggest blocker — are done; see below.) Full list in
  [FUTURE_ENHANCEMENTS.md](FUTURE_ENHANCEMENTS.md).
- **Firestore + Storage security rules — written, committed and deployed (`4a9a2ab`).** They
  were console-only before, so unreviewable and unversioned, and they're the whole boundary
  protecting the project once its ID is public. Now in `firestore.rules` / `storage.rules`,
  declared in `firebase.json`, derived from what the clients actually do (default deny; only
  `users/{uid}` and `usernames/{username}` opened). Profiles are owner-only because they hold
  `phoneNumber`; `usernames/` allows signed-out reads because sign-up checks availability
  before the account exists; Storage now enforces the 4 MB / JPEG limits server-side rather
  than only in `StorageService`.
  **Deploying revealed that neither backend existed.** The CLI logged
  `Creating the new Firestore database (default)…` — the database had never been created, which
  is why `UserProfileService` was failing on every launch, silently. Storage's bucket likewise
  had to be provisioned. **So profile sync and avatar upload have never worked.** Both need a
  real end-to-end test. Note any account created before 2026-08-04 has an auth user but no
  `users/{uid}` document.
  CLI note: Storage has no `:rules` sub-target — use `--only firestore:rules` but plain
  `--only storage`.
- **Third-party licensing — all three resolved (`565d10d`, `f57782e`, `2c18153`).** None was
  a blocker; each had looked worse than it was.
  **LiteRT-LM is Apache 2.0** — confirmed from the upstream LICENSE and the published Android
  POM — so binary redistribution is permitted. The real gap was attribution, now in
  [NOTICE](NOTICE) (upstream ships no NOTICE file of its own, so §4(d) doesn't apply).
  **QAIRT/Qualcomm isn't redistributed at all** — the ARM64 build ships one binary
  (`llama-server.exe`) and shells out to a user-installed `geniex` on PATH, which fetches the
  runtime from Qualcomm itself. That only becomes a constraint if anyone bundles GenieX or
  QAIRT into the installer — confirm rights with Qualcomm *before* starting that. The GenieX
  setup requirement is now documented in the README; without it the NPU models won't load.
  **Chaquopy is MIT** — open source since 12.0.1, no licence key needed. It surfaced a wider
  gap though: both apps embed CPython plus ~10 Python packages (29 resolved distributions on
  iOS) that NOTICE didn't mention. All permissive, and the attribution requirement turns out
  to be met already — every bundled distribution ships its own licence in its `.dist-info/`
  directory. NOTICE now records that rather than duplicating ~30 licence texts that would go
  stale on every rebuild.

### Recently completed (2026-07-30) — tagged `v2.17-android-image-history-fix`
- **Android: fixed "Provided less images than expected" crash on the turn after any image
  turn.** Android rebuilds its whole conversation from scratch every local turn (unlike iOS's
  one persistent Conversation, which only ever sends the new uncommitted turn) — the local
  history builder was re-attaching a past turn's image bytes on every rebuild, which the
  engine (`maxNumImages=1`) doesn't handle the way a live turn's image does. Fix: only the
  current turn keeps its image; past turns keep the text, drop the bytes. iOS needed no
  change — confirmed unaffected by both code review and a live test. `91e47f4`.

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
  full 27-test suite — 26 passed, 1 skipped, 0 failed.** Full writeup in
  [docs/ENGINEERING_NOTES.md §2](docs/ENGINEERING_NOTES.md).

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
  live-device attempt, since all the hard debugging happened on iOS first. Full writeup in
  [docs/ENGINEERING_NOTES.md §3](docs/ENGINEERING_NOTES.md).

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
  writeup in [docs/ENGINEERING_NOTES.md §2](docs/ENGINEERING_NOTES.md).

### Recently completed (2026-07-24)
- Delete confirmation dialog on Models screen, both platforms (`2b249a5`).
- Storage pre-flight check before starting a model download, both platforms — throws a clear
  "needs ~X MB, only Y MB free" error instead of failing mid-download (`9076a17`).
- Budget-exhausted forced-final turn in `AgentLoop`, both platforms — when the tool-call
  iteration cap is hit, injects a "answer now using only what you have" nudge and forces one
  final no-tools turn, instead of just breaking the loop (`9076a17`).
- Download speed + ETA shown in Models screen UI, both platforms (`bc79b64`).
- Tool-result security hardening: `wrapUntrusted()` (nonce-delimited markers around tool
  results, defends against indirect prompt injection via e.g. `run_python`'s network access)
  and `truncateToolResult()` (6000-char cap), both platforms (`bc79b64`, plus earlier
  `run_python` findings).
- First-ever test coverage on either platform: iOS `AIiOSTests` (standalone target, no host
  app), Android `src/test/kotlin` JUnit source set. Both cover `AgentLoop` tool-call parsing,
  `wrapUntrusted`, `truncateToolResult` (`bc79b64`).
- iPad blank-screen bug fixed (`UITextEffectsWindow` system overlay was getting the same
  opaque-background treatment as app windows) (`12008f9`).
- iOS model-download timeout + tool-call parse fallback fixes (`d8fbb74`).
- Android `minSdk` bumped 26 → 30 — `.litertlm` models require API 30+; a Galaxy S9 (Android
  10/API 29) was confirmed to hard-fail loading the native `libLiteRtLm.so` (`2cd1411`).
  S9-class hardware is now explicitly out of scope.

### Deferred / not started
- Mobile model downloads still go through the presigned-URL Firebase Function round-trip, not
  the direct public-CDN pattern desktop now uses. Not broken, just the older/costlier path.
- Sharing prompts / friending — future feature, no design yet.
- **MLX Swift explored as a possible fix for iOS's disabled E4B vision — deferred, not
  started.** MLX (Apple's on-device ML framework, Metal-native) could potentially run vision
  on `gemma-4-e4b-it-4bit` (5.18 GB on `mlx-community`) where LiteRT-LM currently can't
  (SigLIP ops not XNNPack-delegatable). Target device discussed: iPad Pro M5, 16GB. No
  prototype built yet — explicit "hold off, return to later." See
  [FUTURE_ENHANCEMENTS.md](FUTURE_ENHANCEMENTS.md).

---

## Desktop (Electron)

### Recently completed
- **Offline use after first login — fixed, NEEDS VERIFYING ON WINDOWS (`0b8e0fe`).** Reported
  as "doesn't function without internet; seems to require Firebase auth every time". Root
  cause: the packaged app loads its renderer via `loadFile()`, so the origin is `file://`, and
  `getAuth()` silently falls back to **in-memory** persistence when it can't confirm a storage
  backend — throwing the session away on every quit. Online that's just an annoyance; offline
  it's fatal, since signing in needs the network. `npm run dev` hid it entirely (http:// from
  Vite persists fine). Fixed by calling `initializeAuth()` with an explicit persistence chain.
  **Build-verified only — could not be reproduced from macOS.** Please test on the Windows
  machine: sign in online, quit, disconnect, relaunch — you should land straight in the app.
- **Qwen3-VL-4B-Instruct added to the model catalog (Windows ARM64, `157d89b`)** — second
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

## Infrastructure

### Recently completed (2026-08-20)
- **CDN access check — `cdn.ecoinference.ai` and `releases.ecoinference.ai` are still
  gated behind a Cloudflare Access login.** First found in the 2026-08-20 repo audit and
  re-verified by live probe the same day: both hosts 302-redirect to
  `round-salad-4639.cloudflareaccess.com`, so anonymous model downloads and
  `electron-updater` release checks fail. The B2 origin (`f005.backblazeb2.com`) is still
  publicly reachable. Fix lives in the Cloudflare Zero Trust console — remove these hosts
  from the Access application or add a bypass policy. **Open question before fixing:
  confirm whether the gating was deliberate.**

---

## Reference: findings from PocketPal AI analysis (not EcoInference bugs)

- Two real bugs found in PocketPal AI itself via hands-on testing (interrupted-generation
  repetition loop on backgrounding; GPU/Adreno decode hang) — not yet filed upstream, user
  opted to hold for now.
- Both are upstream's bugs, not ours. The transferable lessons (backgrounding behaviour,
  Adreno GPU decode) are folded into [docs/ENGINEERING_NOTES.md](docs/ENGINEERING_NOTES.md).

## Reference: AIFlutter viability test (untracked in this repo, `AIFlutter/`)

A standalone diagnostic app, not part of the shipped product, built to re-check whether
Flutter's LiteRT-LM bindings (the original reason EcoInference went native) are viable today.
Result: `flutter_gemma`/`flutter_gemma_litertlm`'s FFI-based binding passes all 5 diagnostic
tests (chat, tool calling, cancellation, GPU backend, vision) on both Android and iPhone 15
Pro. **Decision (2026-07-25): stick with native mobile + Electron desktop regardless** — the
finding is good to have on record but isn't changing the architecture. The one test never run
(background-interrupt, the one that actually mirrors PocketPal's Bug A) is a non-blocking
loose end given that decision.
