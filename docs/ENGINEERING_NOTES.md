# Engineering Notes

Hard-won findings about this codebase and the native SDKs under it. Most of these cost real
debugging time to establish, and several are counter-intuitive enough to be re-discovered the
hard way without a written record.

Read this before making changes to inference, tool calling, theming, or model loading.

**Companions:** [DEVICE_TESTING.md](DEVICE_TESTING.md) for the build/install/debug commands
and measured numbers · [../STATUS.md](../STATUS.md) for what happened when ·
[../FUTURE_ENHANCEMENTS.md](../FUTURE_ENHANCEMENTS.md) for what's still open.

---

## 1. The three clients are independent — findings do not transfer

iOS, Android and desktop are **separate native implementations that share a backend**, not a
shared codebase. They deliberately mirror each other's features, so a change to one usually
needs porting — but their runtimes differ, and a result measured on one platform tells you
nothing about the others.

| | Runtime | Notes |
|---|---|---|
| iOS | LiteRT-LM (C API via prebuilt dylibs) | One persistent `Conversation` per chat |
| Android | LiteRT-LM (Kotlin SDK via JNI) | Fresh `Conversation` **every turn** |
| Desktop | llama.cpp (GGUF), or GenieX/QAIRT on Snapdragon | Entirely different stack |

That iOS/Android difference in conversation lifetime is the root of several bugs below.

### Vision support differs and is not transferable

- **iOS** — vision works on E2B only. Explicitly **disabled on E4B**: its larger SigLIP
  encoder has ops that aren't XNNPack-delegatable in the current native LiteRT-LM build.
- **Android** — vision works on **both** E2B and E4B; the Kotlin SDK has no equivalent gap.
- **Desktop** — different runtime, independent constraints.

Never infer one platform's vision capability from another's.

---

## 2. Inference / LiteRT-LM

### iOS: one session per engine, and `resetConversation()` is a partial lie

For **non-multimodal (text-only)** models the SDK allows only **one session per engine
lifetime**. `resetConversation()` can therefore only zero a Swift-side counter
(`committedMessageCount`) — **the real native KV-cache keeps every previously "reset" turn's
tokens forever.**

Consequences:

- Enough independent turns on one loaded text-only model exhausts the real context ceiling,
  after which every `generate_content` call fails. Confirmed via native stderr:
  `Failed to allocate tensors`, then cascading `Prefill turn prefill:N already started`.
- This is **not** test-only. Repeatedly hitting "New Chat" on a text-only model can reach it.
- Mitigation shipped: `ChatView` force-unloads and reloads the engine when it sees
  `"generate_content returned nil"` (it previously only handled the multimodal
  `"conversation_send_message returned nil"`).
- **Do not "fix" this by reload-cycling the model between turns.** That was tried and made
  things worse — resident memory climbed on every load/unload cycle until even a freshly
  created engine failed. Whether `unload()` genuinely leaks native memory is unresolved and
  needs Instruments; it is not diagnosable from Swift source.

### iOS: `chat()`'s `maxTokens` parameter is dead code

It is declared but never referenced in the function body. The real per-turn output cap is a
hardcoded `litert_lm_session_config_set_max_output_tokens(sessCfg, 2048)` set once at load
time. **Tuning the `maxTokens` argument does nothing** — don't try to fix token-budget issues
that way. The parameter should probably be wired up or removed.

### E4B's context ceiling is compiled into the model bundle

`maxContextTokens` was raised 4096 → 8192 for E4B. The engine loads fine, but the very first
`generate_content` call fails instantly with `generate_content returned nil` — the `.litertlm`
bundle rejects a value above what it was compiled for. **4096 is the confirmed-safe value.**
Don't raise it without verifying live on-device *generation*, not just `engine_create`.

### Android rebuilds the whole conversation every turn

Android creates a new `Conversation` per local turn and replays history via
`initialMessages`. Two bugs came out of this:

1. **Canceled turns.** A user message whose assistant reply was canceled (blank) was still
   replayed as history, landing as a dangling image-only turn → native
   `"Provided less images than expected in the prompt"`. Fix: drop the whole canceled
   *(user, assistant)* pair, not just the blank assistant half.
2. **Replayed images.** The history builder re-attached `imageBytes` to *every* past user
   turn. The engine (`maxNumImages = 1`) and the SDK's `initialMessages` seeding don't handle
   a replayed image the way a live `sendMessageAsync` turn does → same native error on the
   turn *after* any image. Fix: **only the current turn keeps its image bytes**; past turns
   keep their text.

   Watch out: `historySource = messages.dropLast(1)` drops only the trailing empty assistant
   placeholder — the **current** user turn is still its last element. Stripping images from
   everything in that list breaks the live turn.

iOS is immune to both: it only ever sends the new uncommitted turn.

### Stop / cancellation

- **Android**: cancelling the coroutine alone races `Conversation.close()` against the native
  decode thread → SIGSEGV in `liblitertlm_jni.so`. Must call `cancelProcess()` first.
- **iOS**: the local chat call is blocking, so a user Stop surfaces as `send_message`
  returning nil, not as Swift task cancellation. Cancelling mid-prefill can corrupt the
  speculative-decoding drafter, so the engine is always force-unloaded and then auto-reloaded.

---

## 3. Tool calling and `use tool`

### The location preamble must be prepended to the code that RUNS

`buildToolPrompt()` only *describes* `user_latitude` / `user_longitude` / `user_timezone` to
the model. If the preamble isn't also prepended to the generated code before execution, those
names don't exist at runtime and every location- or time-dependent request fails with
`NameError`.

This was broken on **both** platforms while **both Inference Tests screens prepended it
correctly** — which is exactly why the Python tests passed while the user-facing feature was
broken. A green test screen is not evidence the feature path works.

### Preamble contract

Both platforms must emit the same shape, because the prompt documents one contract:

```python
user_latitude  = <float>
user_longitude = <float>
user_timezone_offset = <float hours>
import datetime          # unaliased — see below
import datetime as _dt
user_timezone = _dt.timezone(_dt.timedelta(hours=<offset>))
```

- `datetime` must be imported **unaliased**. The prompt tells the model to call
  `datetime.date.today()` and models routinely emit that without also emitting the import.
- `user_timezone` must be a real **tzinfo**, not the zone-name string. Android used to emit a
  string, so `sun(..., tzinfo=user_timezone)` worked on iOS and broke on Android.

### astral specifics (verified against the bundled astral 3.2 source)

`phase(date=None) -> float` — **one optional argument, no location**, returning **0..27.99**
(a 28-day scale, with 0 = new, 7 = first quarter, 14 = full, 21 = last quarter).

To name a phase, the prompt supplies this exact one-liner, whose thresholds are even eighths
centred on astral's own anchors and were verified across a full cycle:

```python
import bisect
result = ["New Moon","Waxing Crescent","First Quarter","Waxing Gibbous","Full Moon",
          "Waning Gibbous","Last Quarter","Waning Crescent","New Moon"][
    bisect.bisect([1.75,5.25,8.75,12.25,15.75,19.25,22.75,26.25], phase(d))]
```

The repeated ninth name handles wrap-around without a special case.

**Do not derive these thresholds by scaling the app's own Kotlin moon-phase algorithm.** That
uses a 29.53-day synodic scale with a *different epoch* — measured ratio 0.9268, not
28/29.53 = 0.9482. Scaling gives wrong answers for much of the month.

### Prompt minimalism vs. indentation

The prompt asks for "MINIMAL code, no blank lines, semicolons where natural". That pushed the
model into writing `if/elif` chains with **flush-left bodies** → `IndentationError`. It now
also says to prefer one-liners/indexing over if-chains, and to indent 4 spaces when branching
is unavoidable. Prefer giving the model a form that needs no control flow at all.

### Security posture

Tool results are wrapped in nonce-delimited untrusted-content markers and length-capped
(6000 chars) before reaching the model, because `run_python` has network access and tool
output is an indirect prompt-injection vector. See [SECURITY.md](../SECURITY.md).

---

## 4. Model sizing and device capability

### E4B needs ~8 GB of *usable* RAM, not 8 GB installed

Measured on a Lenovo TB336FU (7.6 GB installed, Android 16):

| | |
|---|---|
| App footprint | 5.15 GB PSS / 4.5 GB RSS |
| Device left free | 1.0 GB |
| Swap in use | 2.30 GB of 4.17 GB |

The system memory killer escalated through its tiers and terminated essentially every other
app — Gmail, Photos, Calendar, the launcher. **The user saw the screen blank when the
launcher died.**

**Key diagnostic:** the app's own PID never changed. When someone reports "the screen
blanked" with a big model loaded, check the app PID before assuming it crashed — Android may
be sacrificing everything *else* to keep your model resident.

`ModelInfo.minRamMb` now encodes this (E4B = 8000) and `ModelCard` warns before loading on a
device below the floor. It is a **warning with "Load anyway"**, not a hard block, because the
model genuinely does run — it just does so by evicting the rest of the device.

### GPU acceleration costs ~1.8 GB of RAM

Same model (E2B), same device, only the backend differs:

| | App PSS | Device left free |
|---|---|---|
| CPU | 753 MB (925 MB RSS) | 4.90 GB |
| GPU | 2,589 MB | 2.46 GB |

The CPU path appears to memory-map weights from the model file; the GPU path copies them into
GPU-accessible memory. The GPU run also produced `Fence: waitForever … didn't signal in
3000 ms` timeouts under load.

**On speed, be careful — the evidence is mixed.** An earlier benchmark on this same tablet
(2026-07-23, via `AgentLoop.kt`'s benchmark logging) found **GPU TTFT 29.7s / decode 5.2
chunks/s** vs **CPU TTFT 47.9s / decode 5.1 chunks/s** — i.e. GPU reached first token *sooner*
and decode was effectively identical. So GPU can win on latency while costing far more memory.
The in-app guidance therefore recommends CPU on the **memory** argument only, and says GPU
"may start answering sooner on some devices".

Large Adreno GPUs do benefit from the GPU delegate; small Mali parts (e.g. Mali-G57 MC2) show
little decode gain. **Adreno results do not transfer to Mali.**

### The TB336FU is slow regardless of backend

~5 chunks/s decode with a 30–48s wait for the first token, on either backend. That is a poor
experience even for E2B. If this class of hardware must be supported, the lever is a smaller
or more aggressively quantized model — **not** further backend tuning. Don't spend time
debugging backend selection for slowness reports on this device.

---

## 5. Android theming — light mode is easy to break

The app was built dark-first. A color that looks right in dark mode is frequently invisible
in light mode. All three of these shipped at some point:

- Text hardcoded to `EcoColors.NearWhite` — correct in dark (where `onSurface` *is* NearWhite),
  near-white-on-near-white in light.
- Labels hardcoded to `EcoColors.DimGreen` — a pale accent for near-black surfaces; ~1.5:1 on
  the light scheme's pale-green ones.
- `EcoColors.Green` used as text or icon tint — ~2.2:1 in light, below WCAG AA.

**The rule and the two exceptions are documented in
[CODE_CONVENTIONS.md](CODE_CONVENTIONS.md#colors-and-theming-android).** Read it before touching
colors — a blanket find-and-replace breaks the legitimate cases.

Short version: use `MaterialTheme.colorScheme.*`, or the `ecoAccent` / `ecoBrand` helpers in
`EcoTheme.kt`. A raw palette constant is only correct as a **fill**, or as content on a
surface that is dark in **both** themes. Background and foreground must be converted together.

Always regression-check **dark** mode — it's the one a careless theming change silently
breaks. `adb shell cmd uimode night no|yes|auto`.

---

## 6. Desktop (Electron)

### Offline auth: `file://` defeats Firebase persistence detection

The packaged app loads its renderer with `mainWindow.loadFile()`, so the origin is `file://`.
`getAuth()` probes for a storage backend and **silently falls back to in-memory persistence**
when it can't confirm one — discarding the session on every quit.

Online this only looks like an annoyance (sign in again). **Offline it is fatal**: signing in
needs the network, so the app is stuck on the auth screen. `npm run dev` hides it entirely,
because dev serves over `http://` from Vite where probing succeeds.

Fix: `initializeAuth()` with an explicit persistence chain (`indexedDBLocalPersistence`,
`browserLocalPersistence`), with a `getAuth()` fallback for the already-initialised case that
Vite HMR can trigger.

**Status: build-verified only. Not yet confirmed on the Windows machine.**

### Windows ARM64 requires GenieX installed separately

The app shells out to `geniex` on `PATH`; nothing Qualcomm ships in the build. Without it the
NPU models won't load. See the README's requirements section.

---

## 7. Backend

### Neither Firestore nor Storage existed until 2026-08-04

Deploying the security rules revealed the Firestore database had **never been created** — the
CLI logged `Creating the new Firestore database (default)…`. That is why
`UserProfileService.startListening()` had been failing on every launch, silently, since the
feature was written. Storage's bucket likewise had to be provisioned.

**So profile sync and avatar upload have never actually run successfully.** Both still need a
real end-to-end test. Any account created before 2026-08-04 has an auth user but **no
`users/{uid}` document** — check how the clients handle a missing profile.

### Security rules

Live in `firestore.rules` / `storage.rules`, declared in `firebase.json`. Default deny; only
`users/{uid}` and `usernames/{username}` are opened. Four decisions worth not undoing:

1. **Profiles are owner-only, not world-readable** — they hold `phoneNumber`. A future public
   profile feature should add a *separate* collection with only public fields.
2. **`usernames/{username}` allows `get` while signed out**, deliberately: sign-up checks
   availability *before* the account exists. `list` stays closed. Accepted trade: a username
   can be tested and its uid read; a uid is an identifier, not a credential.
3. **`username` and `createdAt` are pinned on update** — username has a matching reservation
   doc, and drift would desync them.
4. **Storage enforces the 4 MB / JPEG limits server-side** — `StorageService`'s checks are
   advisory only.

### Firebase CLI gotcha

Storage has **no `:rules` sub-target**. `--only storage:rules` fails with
"Could not find rules for the following storage targets: rules" because everything after the
colon is parsed as a deploy-target alias. Correct usage:

```bash
firebase deploy --only firestore:rules --project ecoinference-28c31
firebase deploy --only storage --project ecoinference-28c31
```

To check whether a Storage bucket exists without the CLI:
`https://firebasestorage.googleapis.com/v0/b/<bucket>/o` — **403 = exists**, 404 = doesn't.

---

## 8. Project structure reference

### Firebase

- Project `ecoinference-28c31` (number `333037511007`), shared by all three clients
- Bundle ID / package: `ai.ecoinference.eiapp` on both mobile platforms
- **Auth**: email/password only — deliberate, social sign-in triggers extra App Store review
- **Firestore**: `users/{uid}` (profile), `usernames/{username}` (uniqueness reservation)
- **Storage**: `avatars/{uid}.jpg`, 4 MB JPEG cap
- **Remote Config**: `router_rules` (RouterRuleSet JSON), `available_models` (download
  allowlist, shared with desktop)
- Model files are **not** in Firebase Storage — they come from Backblaze B2 via Cloudflare CDN

### Key files

| File | Purpose |
|---|---|
| `AIiOS/AIiOS/AppState.swift` | iOS state: models, download/load, Remote Config, deep links |
| `AIiOS/AIiOS/ChatView.swift` | iOS chat, router wiring, `use tool` handling |
| `AIiOS/AIiOS/Inference/LiteRtLmEngine.swift` | iOS native inference bridge |
| `AIiOS/AIiOS/Services/RouterService.swift` | iOS router + Remote Config refresh |
| `AIiOS/AIiOS/Services/LocationService.swift` | iOS Python preamble (`pythonPreamble`) |
| `AIiOS/AIiOS/Models/ModelInfo.swift` | iOS model catalog |
| `AIAndroid/.../AppState.kt` | Android state — mirrors iOS `AppState` |
| `AIAndroid/.../ui/chat/ChatScreen.kt` | Android chat, router wiring, `use tool` |
| `AIAndroid/.../inference/LiteRtLmEngine.kt` | Android native inference bridge |
| `AIAndroid/.../services/LocationPreamble.kt` | Android Python preamble |
| `AIAndroid/.../services/PythonCommand.kt` | Code-gen prompt for `use tool` (mirror of iOS) |
| `AIAndroid/.../models/ModelCatalog.kt` | Android model catalog + descriptions |
| `AIAndroid/.../ui/theme/EcoTheme.kt` | Palette, both color schemes, `ecoAccent`/`ecoBrand` |
| `AIiOS/AIiOS/default_router_rules.json` | Bundled rules — byte-identical on both platforms |
| `AIDesktop/src/main/backends/GenieXServer.ts` | Desktop NPU backend (shells out to `geniex`) |

### Conventions

- **Cross-platform parity**: a behavior change on one mobile platform should be ported to the
  other, or the PR should say why it doesn't apply. Silent divergence is the most common
  source of bugs here.
- **Router rules must stay byte-identical** across platforms.
- **User-facing strings stay plain-language**; technical detail belongs in code comments.
- **Verify build output literally** — grep for `BUILD SUCCESSFUL` / `BUILD SUCCEEDED`. A task
  summary saying "done" is not evidence, and a stale APK will happily install and mislead you.
