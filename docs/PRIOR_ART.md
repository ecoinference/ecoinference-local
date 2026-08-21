# Prior Art and Architectural History

Why the three clients are separate native implementations rather than one shared codebase, and
what was learned from the closest comparable open-source project.

This exists because "just use a shared codebase" is the most obvious suggestion anyone will
make about this repo, and it has already been evaluated twice. Re-litigate it with the
evidence, not from first principles.

---

## The project started on Flutter

EcoInference did **not** begin as native-per-platform. It started on Flutter with a shared
codebase. The move to separate Swift and Kotlin implementations was deliberate, driven by
LiteRT-LM having inadequate Flutter bindings at the time, plus other integration friction.

So the parity bugs this architecture produces — the same fix needed twice, colors drifting,
a feature landing on one platform only — are a **known, accepted cost of a decision made for
concrete engine-binding reasons**, not an oversight waiting to be corrected.

## The re-check: `AIFlutter/` (2026-07-25)

Because that premise was years old, a standalone diagnostic app was built to test whether it
still holds. `AIFlutter/` is untracked and **not part of the shipped product** — a throwaway
harness, a single scrollable log screen that auto-runs tests and prints PASS/FAIL.

What changed upstream: `flutter_gemma` (v1.3.2) + `flutter_gemma_litertlm` (v1.2.0) now bind
to the native LiteRT-LM C API via `dart:ffi` / native-assets — **no platform channels at
all**. The historical pain was specifically the Flutter↔native *platform-channel* bridge for a
streaming inference workload. An FFI binding is a structurally different, generally more
robust integration. That's a genuine change in the premise, not a version bump.

**Result: all five tests pass on both platforms** (Gemma 4 E2B only, local file install).

1. Basic chat
2. Structured tool calling (`FunctionCallResponse`)
3. Cancellation mid-stream
4. GPU backend (reload + chat + tool call)
5. Vision (`Message.withImages`)

Android: Xiaomi 24030PN60G, all 5 pass. iOS: iPhone 15 Pro, all 5 pass.

Two bugs found were in the **test script**, not the plugin:

- `Tool(parameters: {})` — a bare empty map makes the native JSON-Schema constraint provider
  choke, failing with error code 13 ("Failed to start streaming"), identically on both
  platforms. Use `{'type': 'object', 'properties': {}, 'required': []}`.
- Vision needs `supportImage: true, maxNumImages: N` at **model-load time**, passed to
  `FlutterGemma.getActiveModel()`. Passing `supportImage: true` only to `createChat()` throws
  *"Vision executor should not be null, please TryLoadingVisionExecutor() first."*

**Decision (2026-07-25): stick with native mobile + Electron desktop regardless.** The finding
is worth having on record but is not changing the architecture.

**The one test never run** is the highest-stakes one: `_runBackgroundTest()` exists in
`main.dart` as a separate manual-trigger button (it needs a human to actually background the
app). It mirrors PocketPal's Bug A below — start a long generation, background mid-stream,
foreground, check for degenerate repetition. Until it passes, the FFI binding's robustness
under the exact failure mode that hit the comparable project is unverified.

**Do not cite "LiteRT-LM has inadequate Flutter bindings" as a current fact** without re-running
this survey. And don't propose a shared codebase without addressing the background-interrupt
gap.

---

## PocketPal AI as a reference point

[`a-ghorbani/pocketpal-ai`](https://github.com/a-ghorbani/pocketpal-ai) — MIT, React Native,
iOS + Android from one TypeScript codebase. Analyzed 2026-07-24 as the closest comparable
project. (Snapshot figures: 7,647 stars, 786 forks, created Aug 2024, very actively
maintained. Re-check before citing.)

Architecture: RN + MobX + WatermelonDB with an `AgentRunner` driving the chat/tool loop →
`llama.rn` JSI bridge → llama.cpp/GGUF (plus ONNX Runtime for TTS) → CPU / Metal / Adreno
OpenCL / Qualcomm Hexagon NPU.

### The reconciling insight

One implementation structurally eliminates the entire class of "fixed on iOS, forgot Android"
bugs that recur here. But **their shared codebase works because llama.cpp/GGUF has a mature RN
bridge** — the same engine this project's own *desktop* app uses successfully.

So the real lever was never "RN vs native" in the abstract. It is: **does the chosen inference
engine have a mature bridge for the cross-platform framework you'd use?** If mobile ever moved
to llama.cpp/GGUF, a shared codebase could become viable again. Staying on LiteRT-LM likely
means native-per-platform remains the only real option.

### What they have that we don't

- Qualcomm Hexagon NPU inference on mobile.
- In-app benchmark screen and an opt-in public leaderboard. We only have ad-hoc log timing.
- On-device TTS (Kokoro via ONNX Runtime).
- Personas — per-persona system prompt, model and personality, with a marketplace.
- Direct Hugging Face model search and download, including gated models via the user's own
  token.

That last one started as a neutral trade-off — flexibility versus control — and their open-bug
tracker turned it into an evidence-backed call. A large share of their open bugs are exactly
the combinatorial explosion that "any model × any device × any backend" produces. **The curated
catalog here is the safer choice, confirmed by real data rather than design philosophy.**

### What we ported from them

Their `talents/` code has `readUrlAllowlist.ts` and `untrustedContent.ts` — explicit
prompt-injection hardening. They wrap all fetched web content in nonce-delimited BEGIN/END
markers with a "treat as data, never instructions" note, and neutralize any literal marker text
already in the content so a hostile page can't forge a closing marker and escape.

Reading that exposed a real gap here: `run_python` advertises and bundles `requests` with no
network restriction (`runner.py`'s `exec()` is commented "sandboxed" — **it isn't**), and tool
results were fed straight back into context with no marking. A page fetched via
`requests.get()` could inject text the model would treat as instructions.

Ported `wrapUntrusted()` into both platforms' `AgentLoop`, applied to **every** tool result,
not just Python's. We have no equivalent of their `read_url` exfiltration allowlist because we
have no web-fetch tool — port that pattern too if one is ever added.

### The single highest-leverage finding

**They get structured tool calls, we parse text.** `llama.rn`/llama.cpp exposes tool calls as
a structured `tool_calls` field (OpenAI-style, grammar-constrained by the engine) — never as
raw `<tool_call>{...}</tool_call>` text the app has to regex out and JSON-repair.

That is the likely root reason our `AgentLoop` needed a four-stage JSON repair pipeline and had
the "raw tags leaked into chat" bug. **If LiteRT-LM has or gains an equivalent
grammar-constrained structured tool-call mode, that eliminates the whole bug class at the
source** rather than continuing to patch the parser. Worth checking on any LiteRT-LM upgrade.

### Smaller things worth stealing

- **KV-cache-aware replay.** They rebuild history from the parsed `content` field, not raw
  streamed text — raw text would double up the tool-call JSON and break the engine's KV-cache
  prefix match, forcing a full reprefill.
- **Downloads survive app kill on Android.** `syncWithActiveDownloads()` queries the native
  WorkManager module on next launch and rehydrates the job map. Ours is purely in-process on
  both platforms — killing the app mid-download loses it entirely, with no resume.
- **Cancel vs failure disambiguation.** A dedicated `DownloadCancelledError` and a
  `cancelledModelIds` set, so a user cancel never surfaces as a "download failed" toast.
- **HF token host-pinning.** `isHuggingFaceUrl()` gates the token so it can only ever attach to
  a `huggingface.co` request. Same posture as our `x-goog-api-key`-in-header rule.

Already adopted from this analysis: pre-flight storage checks before a multi-GB download, the
budget-exhausted forced-final turn in `AgentLoop`, and download speed/ETA in the UI.

### Two real bugs found in their app

Found while using the retail Android build with Gemma 3 1B, diagnosed live via
`adb logcat -s "RNLlama:*" "ReactNativeJS:*"` — no source access needed. **Neither has been
filed upstream**; the decision was to hold.

**Bug A — an interrupted decode gets replayed as history, causing an unrecoverable repetition
loop.** Backgrounding mid-generation triggers their auto-release
(`"Active → Background: Auto-releasing context"` → `nextToken:569 Decoding Interrupted`). The
interrupted decode had already begun degenerating in the ~1 s before the interrupt. On
foregrounding, the next `loadPrompt` shows the clean prompt followed by **hundreds of repeated
token 31** — the degenerate partial output was persisted as valid history. From there the
model is conditioned on hundreds of repeated tokens, which forces *any* autoregressive LLM into
an unrecoverable loop regardless of sampler settings.

Control test: full data clear → fresh download → CPU backend → no backgrounding → clean
12-token prompt, correct varied response. Same model, same device, same quantization.

**Bug B — the Adreno/OpenCL GPU backend can hang indefinitely on first token.** Decode stalled
**3 min 50 s** producing zero tokens; `loadPrompt:221 [DEBUG] Input processed` then total
silence until the user hit Stop. UI stayed responsive — decode hung, not the app. Their own
`patch_c_api.sh` documents a related Adreno issue (upstream #364), so this looks like a
recurring theme on that backend family rather than a one-off.

### Their open-bug tracker says where on-device inference is actually hard

Reviewed all 55 open `bug`-labeled issues. The volume is unremarkable for a project that size;
the **shape** is the finding. The weak point is squarely the native inference layer, not UI or
features:

1. **GPU/accelerator fragility on both platforms** — iOS #453 "All models do not load with
   Metal enabled"; Android #626 crash on GPU, #809 GPU not detecting, #481 flash-attention
   crash, #528 OpenCL gaps.
2. **Device/chipset-specific load crashes** — #89 (open since Nov 2024, their oldest), #512
   Snapdragon 8 Gen 5 traced to Android 16's 16 KB memory page migration breaking native
   library assumptions, #595 Mali-G78 incompatibility, #824 iOS crash on all quants of one
   model.
3. **App-lifecycle bugs** — #135 backgrounding kills generation, #450 downloads restart when
   not foregrounded. Same family as Bug A.
4. **Chat-template/model-specific bugs** — system prompts ignored, reasoning-tag extraction
   broken, text hidden after a special token.
5. **Accessibility** — #833 VoiceOver, #247 TalkBack cannot download a model at all.

**The lesson for us:** do not treat their shared codebase or feature richness as proof that
architecture solves on-device reliability. GPU-backend selection and background/foreground
lifecycle handling are apparently hard *regardless* of architecture — our own GPU-vs-CPU
tablet findings are the same class of problem. These are precisely the bugs that are easy to
introduce and easy to miss without real device testing across varied hardware, which is the
resource-intensive part neither project has solved.

Re-check this survey before touching GPU backend selection or app-state handling here.
