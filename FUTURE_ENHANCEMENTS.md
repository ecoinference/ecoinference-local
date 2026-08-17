# Open Items and Future Enhancements

Things known to be incomplete, deferred, or worth doing. `STATUS.md` records what *has*
happened; this file records what hasn't.

Ordered roughly by whether it blocks something.

---

## Blocking: before this repo goes public

- **Revoke two HuggingFace tokens still live in git history.**
  `hf_eLEvJKgES…` (was in `AIiOS/Local.xcconfig`, commits `58f8451`, `0e20452`) and
  `hf_mJjDwmaeN…` (was in the since-removed `AIServer/lib/services/settings_service.dart`,
  commits `28f88e3`, `a88e08a`). **The fix is revoking them at
  huggingface.co/settings/tokens, not rewriting history** — scrubbing can't recall copies
  that already exist. Worth doing whether or not the repo is ever published.

  Everything else scanned clean: no `.env`, `.pem`, service-account, AWS, Slack or GitHub
  credentials were ever committed. The `AIza…` hits are Firebase *client* config, which is
  designed to ship publicly and is not a leak.

- **Get the CLA legally reviewed and wire up a CLA bot.** `CONTRIBUTING.md` describes a CLA
  that no automation currently enforces. [cla-assistant.io](https://cla-assistant.io) is the
  usual free option. The CLA is what makes future relicensing possible, so it should be in
  place from the first outside contribution rather than retrofitted — see
  `CONTRIBUTING.md` for the reasoning.

---

## Correctness gaps

- **Profile sync and avatar upload have never successfully run end-to-end.** Deploying the
  security rules on 2026-08-04 revealed that the Firestore database and the Storage bucket
  had never been created — `UserProfileService` had been failing silently on every launch
  since it was written. Both backends now exist and are rule-protected, but the feature has
  never actually been exercised. Any account created before 2026-08-04 has an auth user with
  no `users/{uid}` document, so the migration path for those accounts needs testing too.

- **Desktop offline auth fix is unverified.** `614e7aa` fixed the `file://`-origin
  persistence bug that made the packaged app demand a network login on every launch. It was
  build-verified only — the bug can't be reproduced from macOS. Test on Windows: sign in
  online, quit, disconnect, relaunch; you should land straight in the app.

- **The packaged Windows `.exe` has never been verified end-to-end** the way the macOS build
  was. Tooling is wired (`package:win` runs `electron-vite build` first) but a real run with
  a bundled `llama-server.exe` hasn't happened.

- **iOS `unload()` may leak native memory.** Reloading the model between tests made failures
  *worse*, not better — resident memory climbed across reload cycles until even a freshly
  created engine failed. That's consistent with a leak but isn't proof. Answering it needs
  Instruments or a memory graph; it is not diagnosable from source. See
  [docs/ENGINEERING_NOTES.md §2](docs/ENGINEERING_NOTES.md).

---

## Parity gaps (one platform has it, the other doesn't)

The three clients are independent implementations that deliberately mirror each other, so
these are drift, not design.

- **RAM gate → iOS.** Android now reads total device RAM and warns before loading a model
  that won't comfortably fit (`ModelCard.kt`, driven by `ModelInfo.minRamMb`). iOS has no
  equivalent, no per-model description field to carry the warning, and its existing 600/1500
  MB thresholds predate the tablet measurements that motivated the gate.

- **"Show Python" collapse → iOS.** Android hides generated Python behind a toggle so the
  answer isn't pushed off-screen (`MessageBubble.kt`, `40f4a0a`). Not ported, and **not yet
  eyeballed on Android either** — build-verified only.

- **iOS E4B vision is disabled**, Android's is not. E4B's larger SigLIP encoder has ops that
  aren't XNNPack-delegatable in the current native LiteRT-LM build. The Kotlin SDK has no
  equivalent gap. See the MLX note below.

---

## Deferred by explicit decision

- **MLX Swift for iOS E4B vision.** Apple's Metal-native ML framework could potentially run
  vision on `gemma-4-e4b-it-4bit` (5.18 GB on `mlx-community`) where LiteRT-LM can't. Target
  device discussed was an iPad Pro M5 with 16 GB. **No prototype built** — explicitly
  deferred ("let's hold off… we will return to this later", 2026-07-29). Would mean carrying
  a second inference runtime on iOS only, which is the real cost.

- **Mobile model downloads still use the presigned-URL Firebase Function round-trip**, not
  the direct public-CDN pattern desktop moved to. Not broken — just the older and costlier
  path. The B2 models bucket is already public and CDN-fronted.

- **Avatars are still on Firebase Storage**, not migrated to B2 alongside the models.

- **Bundling GenieX or QAIRT into the Windows ARM64 installer.** Tempting, because it would
  remove a manual setup step. **Don't start before confirming redistribution rights with
  Qualcomm** — the terms sit behind a developer-portal click-through with no published text,
  and could rule the approach out entirely. Today nothing from Qualcomm ships in this app, so
  QAIRT's terms don't bind the project at all; bundling changes that. See `README.md`.

- **Code signing** (macOS notarization + Windows Authenticode) — deferred until the app is
  more stable. Without it `electron-updater` can detect and download updates, but installs
  may be Gatekeeper-blocked.

- **Trademark registration** — the free path was chosen. Contact the UIC trademark clinic
  (`law-tmclinicinfo@uic.edu`) when ready. `TRADEMARK.md` and the ™ markings on public
  surfaces already build the common-law evidentiary record in the meantime.

---

## Not started, no design yet

- **Sharing prompts / friending.**
- **Vision for Gemma 4 12B on desktop** — an `mmproj` file exists upstream; wiring was
  deferred when 12B was added.
- **x64 (Intel) `llama-server` cross-compile** — the macOS build is arm64-only.
- **RAM/VRAM detection and model recommendation UI on desktop.** Mobile now has the beginnings
  of this in the RAM gate; desktop has nothing.
- **A smaller or more aggressively quantized mobile model.** The measurements in
  [docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md) show mid-range hardware is slow on *either*
  backend — ~5 chunks/s with a 30–48 s wait on E2B. Backend tuning won't fix that; model size
  is the lever.

---

## Known limitations that are not bugs

Recorded so they don't get rediscovered and "fixed."

- **iOS text-only models can't truly reset a conversation.** The SDK allows one session per
  engine lifetime, so the native KV-cache accumulates every "reset" turn forever. Enough
  independent conversations on one loaded model exhausts the real context ceiling. Mitigated
  with auto-recovery (force-unload + reload) rather than fixed. See ENGINEERING_NOTES §2.

- **E4B's context ceiling is 4096 and cannot be raised.** Setting 8192 loads fine and then
  fails the first generation outright — the `.litertlm` bundle was compiled for 4096.

- **`chat()`'s `maxTokens` parameter is dead code** (`LiteRtLmEngine.swift:866`) — never
  referenced in the function body. The real per-turn cap is a hardcoded 2048 set at `load()`.

- **Android API 29 and below are out of scope.** `.litertlm` models need API 30+; a Galaxy S9
  was confirmed to hard-fail loading `libLiteRtLm.so`.

---

*Previously this file described a Morse-code receiver screen for the Flutter version of the
app, which no longer exists. That design is in git history if anyone wants it.*
