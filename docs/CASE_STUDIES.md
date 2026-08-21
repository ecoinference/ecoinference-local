# Case Studies

Bugs that were expensive to find, written up as narratives rather than conclusions.
[ENGINEERING_NOTES.md](ENGINEERING_NOTES.md) records *what is true*; this file records *how it
was established*, because the method usually generalizes further than the fix does.

Each entry ends with the transferable part.

**Contents**

1. [One vague report, five real bugs — the Stop button](#1-one-vague-report-five-real-bugs--the-stop-button)
2. [A passing test screen hiding a broken feature — `use tool`](#2-a-passing-test-screen-hiding-a-broken-feature--use-tool)
3. [The same error message, two unrelated causes — "Provided less images than expected"](#3-the-same-error-message-two-unrelated-causes)
4. [The model denies having an image it demonstrably received](#4-the-model-denies-having-an-image-it-demonstrably-received)
5. [A fix that made things worse — KV-cache exhaustion](#5-a-fix-that-made-things-worse--kv-cache-exhaustion)
6. [A bug that was structurally impossible on the test device — iPad blank screen](#6-a-bug-that-was-structurally-impossible-on-the-test-device--ipad-blank-screen)
7. [Two releases shipped broken because `npm run dev` worked](#7-two-releases-shipped-broken-because-npm-run-dev-worked)
8. [The same bug, independently, on three platforms — per-model loading state](#8-the-same-bug-independently-on-three-platforms)
9. [Scaling a constant instead of reading the source — the astral thresholds](#9-scaling-a-constant-instead-of-reading-the-source)
10. [A symptom that looked like a crash and wasn't — tablet memory pressure](#10-a-symptom-that-looked-like-a-crash-and-wasnt)

---

## 1. One vague report, five real bugs — the Stop button

**Reported as:** "Stop doesn't seem to work."

That sentence hid five distinct confirmed bugs across both platforms. Each only became
visible after the previous one was fixed and testing continued — which is the whole lesson.

**Bug 1 — Android: a real native SIGSEGV.** Stop only called `generatingJob?.cancel()`, with
no native cancel at all. `LiteRtLmEngine.kt`'s `chat()`/`chatStream()` create a short-lived
`Conversation` inside `.use { }`; cancelling the coroutine propagates `CancellationException`
through `.collect{}`, which triggers `.use{}`'s auto-close — **while the native thread is
still decoding on that same Conversation**. Use-after-close.

Confirmed with a device repro: `Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr
0x0` inside `liblitertlm_jni.so`, backtrace entirely native.

> Note the search that found it: `grep -i "FATAL EXCEPTION"` **misses this entirely**. A
> native crash appears as `F libc : Fatal signal 11` and `F DEBUG` tombstone lines.

Fixed using the SDK's own `Conversation.cancelProcess()` — found via `javap` on the cached
AAR's API jar under `~/.gradle/caches/modules-2/files-2.1/com.google.ai.edge.litertlm/`. An
`AtomicReference<Conversation?>` tracks whichever conversation is mid-generation; Stop signals
it *before* coroutine cancellation tears anything down.

Found while designing that fix: the generic `catch (e: Exception)` also caught
`CancellationException`, overwriting the already-streamed partial text with an "Error: …"
bubble on every stop. Added a dedicated `catch (e: CancellationException)` ahead of it that
preserves the text and rethrows.

**Bug 2 — iOS: the Stop UX.** `inference.chat()` is blocking and non-streaming, so
`cancel_process()` does interrupt it, but only after the blocking call notices and returns.
For those seconds the button looked dead. Added a `userRequestedStop` flag that writes
"Stopping…" immediately, and reordered `stopGeneration()` to call `cancelInference()` *before*
`inferTask?.cancel()` — the same "signal native first" principle bug 1 proved matters.

**Bug 3 — iOS: cancelling mid-prefill corrupts the speculative-decoding drafter.** While
fixing bug 2 I also skipped the existing safety force-unload for user-requested stops,
reasoning that "a clean `cancel_process()` shouldn't leave the engine any worse off than a
real error would."

**That assumption was wrong, and the log proved it.** Turn 1 canceled cleanly
(`CANCELLED: Session is cancelled during prefill`, no crash) → turn 2 in the *same* session,
with no stop involved, failed with a genuine XNNPACK tensor-allocation error in the MTP
drafter (`llm_litert_mtp_drafter.cc:357`, `unsupported scale value (0.000000)… INT8 tensor`).
E2B has `supportsSpeculativeDecoding: true` on iOS (a real 21→24 tok/s gain). Cancelling
mid-prefill leaves that subsystem corrupted even though the cancellation API call itself
returns cleanly.

Reverted to always force-unloading, and added an auto-reload of the same model immediately
after so the safety unload is transparent instead of stranding the user in Models. **Android
deliberately did not get this** — it doesn't use speculative decoding at all, so porting it
would have been manufacturing a fix for a problem with no evidence there.

**Bug 4 — iOS: a stuck keyboard with no way out.** The `TextField` was only
`.disabled(isGenerating)`, never disabled when no model was loaded, and the *only*
keyboard-dismiss path was `.scrollDismissesKeyboard(.interactively)` — which needs a drag on
scrollable content and isn't discoverable. When the model auto-unloaded mid-chat (bug 3's
fix), there was genuinely no escape short of force-quitting.

Fixed with an always-visible "Done" in `ToolbarItemGroup(placement: .keyboard)` **and** an
`.onChange(of: appState.modelLoaded)` that clears focus on unload. Belt and suspenders,
deliberately.

**Bug 5 — Android: a dangling image-only turn after a canceled generation.** The blank
assistant reply was already filtered from the next send's history — but its *paired user
message, which still had an image attached*, was not. Since Android replays full history into
a fresh `Conversation` every turn, that left a lone image-bearing turn with no reply, and the
next message died on `INVALID_ARGUMENT: Provided less images than expected in the prompt`.
Fixed by making the history loop pair-aware: a `user` message followed by a blank-text
`assistant` message is the signature of a canceled turn — skip **both**.

**Transferable:**

- On Android, check for a native tombstone before concluding a button is a UI/logic bug.
  `FATAL EXCEPTION` alone will not find a SIGSEGV.
- With this SDK pattern (`engine.createConversation(config).use { }` around a
  `Flow.collect{}`), the native cancel must happen **before** coroutine cancellation reaches
  the auto-close. Kotlin's cooperative cancellation does not prevent a native use-after-free.
- **A clean cancellation API call does not imply a clean engine.** Verify with a real
  follow-up turn in the same session, not just "the cancel didn't error."
- When history is rebuilt from messages each turn, an incomplete turn must be excluded as a
  whole *pair*, not just its empty half.
- Never let a single indirect gesture be the only escape from a UI state, especially one the
  app can enter programmatically.
- **Keep testing after the first fix.** Five bugs surfaced sequentially; stopping at any point
  would have left "Stop doesn't work" partly true.

---

## 2. A passing test screen hiding a broken feature — `use tool`

**Reported as:** the Help screen's own moon-phase example returns a wrong answer.

Four stacked bugs, each hidden behind the one before it.

**1. The location preamble was never prepended to the code that actually runs.**
`handleToolCommand` fetched the preamble and passed it to `buildToolPrompt()` — which only
*describes* `user_latitude`/`user_longitude`/`user_timezone` to the model. The generated code
then executed **without** it, so those names never existed at runtime. Both platforms.

The part worth internalizing: **both Inference Tests screens had always prepended it
correctly** (`PythonRunner.execute(preamble + code)`). That is precisely why the Python test
suite passed green while the user-facing feature was broken for every location- or
time-dependent request. The test exercised a different code path than the feature.

**2. Neither preamble bound `datetime` unaliased.** The prompt tells the model to call
`datetime.date.today()`, and models emit that without also emitting `import datetime`. iOS
bound only `_dt`; Android bound nothing.

**3. Android's `user_timezone` was a string** (the zone name) where the prompt documented — and
iOS supplied — a real tzinfo. So `sun(..., tzinfo=user_timezone)` worked on iOS and broke on
Android. A silent cross-platform divergence against a documented contract.

**4. The astral guidance in the prompt was simply wrong** — see [case 9](#9-scaling-a-constant-instead-of-reading-the-source).

**Transferable:**

- **A green test screen is not evidence the feature works.** When a test harness and the
  production path build their inputs separately, they will drift. Prefer sharing the builder;
  failing that, treat "tests pass but users report failure" as evidence the test is on the
  wrong path, not that the report is wrong.
- A prompt that *describes* a runtime contract is not the same as code that *establishes* it.
  Check both ends.

---

## 3. The same error message, two unrelated causes

`INVALID_ARGUMENT: Provided less images than expected in the prompt` appeared twice, three
days apart, and the second one looked like a regression of the first. It wasn't.

**First (2026-07-27):** a canceled turn left a dangling image-bearing user message with no
paired reply — [case 1, bug 5](#1-one-vague-report-five-real-bugs--the-stop-button).

**Second (2026-07-30):** attach an image, ask about it (fine), then send a **plain text
follow-up** — crash. Different cause entirely. Android rebuilds a brand-new `Conversation`
every local turn and replays the whole history via `initialMessages`, and the history builder
was re-attaching `imageBytes` to *every* past user turn. With `maxNumImages = 1`, replaying
turn 1's image on turn 2 broke native prompt construction. The SDK's `initialMessages` seeding
evidently doesn't handle image content the way a live `sendMessageAsync` turn does.

iOS is structurally immune: it keeps one persistent `Conversation` and only ever sends the new
uncommitted turn. Confirmed by code review *and* a live test rather than assumed.

**The first fix attempt was wrong**, and instructively so: I stripped `imageBytes` from every
message the history loop touched. That broke turn 1 — the model started claiming there was no
image even on the live turn. Cause: `historySource = messages.dropLast(1)` only drops the
trailing *empty assistant placeholder* appended a few lines earlier, so the brand-new user
turn with its image is still `historySource`'s **last** element. The blanket strip hit the
live turn too.

Corrected: strip `imageBytes` only when not processing `historySource.lastIndex`.

**Transferable:**

- An identical error string is not an identical bug. Re-derive the cause before assuming a
  regression.
- Before mutating anything in a list built with `dropLast(N)`, verify what `dropLast` is
  actually removing *in that context*. It's easy to assume it excludes the current turn when
  it's really removing a UI placeholder added moments earlier.

---

## 4. The model denies having an image it demonstrably received

**Reported as:** attaching a photo and asking a real question ("What bird is this") gets a
refusal claiming no image was provided — while the auto-filled generic "Describe this image."
prompt always works.

The instinct is a plumbing bug. The native engine log said otherwise: the image was resized,
run through the vision encoder (`vision_280`/`vision_adapter_280`), and prefill completed
(`RunPrefillAsync status: OK`). The image genuinely reached the model. The bundle's sampler
config has a fixed `seed: 0`, which explains the *exact* reproducibility — same input, same
output, not random variance.

**Root cause, found after one wrong iteration:** the system prompt's tool-calling block ("You
have access to device hardware tools…") primes the model to look for a tool when a question
sounds specialized. The first fix — prepending "Looking at the attached image, …" — changed
the failure from "no image provided" to "I don't have a tool to identify this." Progress, and
a strong hint about the real mechanism.

The actual fix has to rule out tool use explicitly: *"Looking at the attached image, {text}
Answer directly from what you see — you already have full vision of the image and do not need
any tool for this."* Applied only to the **outgoing inference text** for turns with both an
image and custom text; the displayed bubble keeps the user's original wording.

**Transferable:**

- When a vision-language response contradicts what the engine trace proves was delivered,
  don't assume an app bug. Pull the native log first — on iOS,
  `xcrun devicectl device copy from … --source /Documents/native_stderr.log` (single file, not
  the whole `/Documents` directory, which also drags multi-gigabyte model files).
- If the system prompt advertises tool-calling, a specialized-sounding question about an image
  may be treated as "needs a tool." Grounding nudges have to rule out tool use, not merely
  assert that an image is present.
- A fixed sampler seed makes "reproducible" much weaker evidence of a deterministic *code*
  path than it looks.

---

## 5. A fix that made things worse — KV-cache exhaustion

Running many Python E2E tests in one pass, roughly five deep, started failing with
`Failed to allocate tensors` and then cascading `Prefill turn prefill:5 already started`.

Root cause was architectural: iOS's text-only Session API allows **one session per engine
lifetime**, so `resetConversation()` can only zero a Swift-side counter — the native KV-cache
keeps every "reset" turn's tokens forever.

**The obvious fix made it worse.** Unloading and reloading the model before each independent
test — giving each a genuinely clean cache — produced *7* failures instead of 6. The native
log showed resident memory climbing every cycle: 653 → 676 → 695 → 797 → … → 1059 MB, never
returning near baseline, until even a **freshly created** engine failed its first
`generate_content`. Reverted.

Two checks that made the conclusion trustworthy:

- **Ruled out cross-run contamination.** Force-killed the app via `devicectl … process signal
  --signal SIGKILL`, relaunched clean, re-ran: identical 5 E2E failures. So it's pure
  within-run accumulation, not leftover state.
- **Ruled out a plausible non-fix.** `chat()`'s `maxTokens` parameter turned out to be dead
  code — declared, never referenced. The real cap is a hardcoded 2048 set once at `load()`.
  So `TestView.swift` passing `maxTokens: 1024` had zero effect, and "tune that value" would
  have been a fix that did nothing while appearing to.

**Decision: stop and document.** A real fix meant either lowering the production-shared 2048
cap or cutting retry iterations — which only delays the failure. Instead: broadened the
existing auto-recovery to catch this error string too, and added a plain-language UI note so a
partial-run failure doesn't read as a regression.

Still open: whether `unload()` genuinely leaks native memory or the climbing RSS is
allocator/mmap residency that would settle under real pressure. **Not answerable from Swift
source** — it needs Instruments. Until then, don't add more load/unload-cycling "fixes."

**Transferable:**

- When a fix makes the metric worse, that's information. Revert and understand the new failure
  before layering another attempt.
- Verify a parameter is actually wired before tuning it. A dead parameter makes a fix look
  applied when nothing changed.
- It's legitimate to stop at "known limitation, surfaced honestly in the UI" when the real fix
  costs more than the bug. Write down what would be needed to answer the open question.

---

## 6. A bug that was structurally impossible on the test device — iPad blank screen

On first-ever iPad testing (iPad Air M1), the sign-in screen rendered correctly for ~2 seconds
and then the entire screen went blank — solid background, no controls. Never crashed. Never
happened on iPhone across months of testing.

**Cause:** `AIiOSApp.swift`'s `applyWindowFix()` — an iOS-26 "Liquid Glass" workaround that
inserts an opaque background sentinel view to fix black safe-area bars — looped over **every**
window in `scene.windows`. On Pencil-capable iPads, iPadOS lazily creates a system
`UITextEffectsWindow` a couple of seconds after launch, which sits *above* the app's content
window by design. The loop inserted a full-screen opaque view into that one too.

iPhone has no Pencil overlay window, so the bug was structurally impossible there.

**Wrong fix first:** filtering `where window.rootViewController != nil`. Didn't work —
`UITextEffectsWindow` *does* have a (system-internal) rootViewController. Only its view's
`backgroundColor` was nil, which is a different property.

**Actual fix:** `where window.windowLevel == .normal`. System overlays are deliberately placed
above `.normal` so they render on top of app content — that's the robust signal, and it
doesn't depend on private class names.

**Transferable:**

- Never assume every window in a scene is your app's. Filter to `.normal` before mutating
  backgrounds or inserting views.
- "Tested for months without this" says nothing about a device class you've never run on. This
  code had shipped and been exercised heavily — on hardware where the trigger cannot exist.
- When a filter doesn't work, check whether you're filtering on the property you think you
  are.

---

## 7. Two releases shipped broken because `npm run dev` worked

v0.1.0 and v0.1.1 both went to B2 completely non-functional. Found only by launching the
packaged `.app` directly for the first time, while testing something unrelated.

Two independent bugs, both masked by dev mode:

1. **`npm run package:mac` never ran `electron-vite build`.** So `out/renderer/` — the
   compiled HTML/JS — didn't exist on disk when packaging ran. Only `npm run dev` had ever
   been used, and it serves the renderer live from Vite without ever writing it out. Every
   packaged build shipped with zero renderer content: blank window, `ERR_FILE_NOT_FOUND`.
2. **`llama-server` was never bundled.** Dev always fell back to the Homebrew binary on
   `PATH`, hiding that production's expected `Contents/Resources/bin/llama-server` was empty.
   Clicking Load spawned nothing (`ENOENT`) — and the spawn-failure handler only *logged* the
   `'error'` event without resolving the pending promise, so the UI sat on "Loading…" for the
   full 60-second health-check timeout before reporting a misleading "startup timed out."

Then **the fast-fail fix regressed dev mode**: the new `fs.existsSync(binaryPath)` pre-check
doesn't account for `binaryPath` sometimes being a bare command name (`'llama-server'`, the
dev PATH-fallback). `existsSync` does no `PATH` resolution, so it returned false for a binary
that would have spawned fine. Fixed by gating the pre-check on `isAbsolute(binaryPath)`.

**Transferable:**

- **`npm run dev` working is not evidence a package works.** They take different code paths
  for both the renderer (live Vite vs compiled `out/`) and the sidecar binary (PATH fallback
  vs bundled resource). Launch the real packaged binary before any upload.
- Any `fs.existsSync()` on a value that might be a bare command name must branch on
  `path.isAbsolute()` first — otherwise "resolvable via PATH" reads as "file missing."
- A spawn-failure path that logs without resolving turns an instant, specific error into a
  slow, generic one.

---

## 8. The same bug, independently, on three platforms

A single global `isLoading` boolean with no associated model ID — so *every* model card showed
"Loading…" whenever *any* model was loading. The adjacent `downloadingModelId` had always been
correctly scoped per-model, which is what makes this notable: the correct pattern was sitting
right there.

Found on desktop first, then iOS via live testing, then confirmed in Android by inspection
before it was ever run. Not independently introduced — mirrored from shared origin code.

Fixed the same way everywhere: add `loadingModelId`, compare against the specific model's id,
guard `loadModel()` against re-entry, and disable other cards' buttons while one loads.
Desktop had the same shape a third time in `downloadErrorModelId`.

**Transferable:** any shared-state boolean in `AppState` that means "the currently active
model" should be paired with an `xModelId: String?` from the start, following the
`downloadingModelId` pattern. This class has now recurred on three platforms — assume the next
per-model async operation will have it too.

---

## 9. Scaling a constant instead of reading the source

Bug 4 of the `use tool` chain. The prompt's astral guidance had the wrong function signature
and no phase-name mapping.

**What I did first, and shouldn't have:** took the app's existing Kotlin thresholds (built for
a 29.53-day synodic scale), multiplied by 28/29.53 = 0.9482, and shipped that as the fix for
astral's 0–27.99 scale.

The user pushed back on the guessing, correctly. astral's epoch differs by about 0.6 days —
the **measured** ratio is 0.9268, not 0.9482. Scaling one constant into another library's
frame assumes the frames share an origin, and these don't.

**What actually worked:** read the bundled `AIiOS/app_packages/astral/moon.py`, confirm the
real signature (`phase(date=None) -> float`, one optional arg, no location, returning
0..27.99), then derive thresholds from astral's *own* documented anchors — 0 = new, 7 = first
quarter, 14 = full, 21 = last quarter — and verify across a full cycle. All four anchors land
correctly and all eight names are reachable in order.

The final clause uses a 9-element name list whose last entry repeats "New Moon", so the
wrap-around needs no special case.

**Transferable:** when a value must match a third-party library's frame of reference, read
that library's source and derive from its own anchors. Converting a constant from a different
frame is a guess that produces plausible, subtly wrong numbers — the worst failure mode, since
it looks right in spot checks. The bundled source is right there.

---

## 10. A symptom that looked like a crash and wasn't

**Reported as:** loading E4B on a 7.6 GB Android tablet, then "the screen just blanked."

Measured with the model resident: app at **5.15 GB PSS / 4.5 GB RSS**, device down to 1.0 GB
available, **2.30 GB of 4.17 GB swap in use**, `kswapd` highly active. Lenovo's
`ZuiMemoryCleaner` escalated `Moderate-MemFreeLow` → `Moderate-KSwapdActive` →
`Aggressive-KSwapdHighlyActive`, killing Turbo, Gmail, Photos, Calendar, the calendar
provider, partnersetup and setupwizard. A launcher process (`mediahome.launcher`) died and
restarted — **that** was the blank screen.

**The diagnostic detail worth keeping: the app itself was never killed.** Its PID stayed
constant throughout. Android sacrificed every *other* app to keep E4B resident, and the
visible symptom was a system-UI casualty.

**Transferable:** when a user reports a blank screen or apparent crash while a large model is
loaded, check the app's PID before assuming it died — `adb shell pidof <pkg>`, then
`logcat | grep -iE "lowmemorykiller|Killing [0-9]+:"` to see who the real victims were. The
app surviving while the launcher dies is a specific, recognizable signature of memory
pressure, and it points at a very different fix than a crash would.
