# Routing: How It Works, and Where It's Going

Every prompt is routed to a **local** or **cloud** tier before inference. This covers how that
decision is made today, a design for measuring it properly, and one third-party model evaluated
as a possible replacement for the weak part.

The harness below is a **design agreed 2026-09-19. It is not built.**

---

## 1. How routing works today

A rule engine evaluates a fact map against an ordered rule set; first match wins, falling back
to `defaultDecision: "local"`.

- **Rules:** `default_router_rules.json` — 7 rules, byte-identical on both platforms (iOS
  bundle resource, Android `assets/`). Updatable live via Firebase Remote Config's
  `router_rules` without an app release.
- **Engine:** `RuleEngine.{kt,swift}` — pure logic, no platform imports.
- **Facts:** `RouterFactExtractor.{kt,swift}`.

Facts come in two kinds, and the distinction matters for everything below:

| Kind | Facts | How derived |
|---|---|---|
| **Structural** | `promptLength`, `wordCount`, `conversationTurns`, `hasImage`, `hasCodeBlock`, `hasMathSymbols` | Measured. Right, or a code bug. |
| **Semantic** | `mentionsCurrentEvents`, `mentionsSensitiveDomain`, `requestsDeepReasoning`, `requestsCreativeWriting` | **Substring match against ~62 hardcoded English phrases.** |

### The known weakness

The four semantic facts are keyword matching, so they fail on paraphrase:

- *"Who won the game yesterday?"* matches no keyword → routed local → the local model invents a
  score. This is exactly the case routing exists to catch.
- *"What's the latest with the election?"* needs the literal phrase `"latest news"`.
- Non-English prompts match nothing and always route local.
- False positives too: *"Can I sue for some peace and quiet?"* matches `"can i sue"` and leaves
  the device.

### Two things that are easy to lose

**Live tunability is the current router's best property.** Not accuracy — the fact that a
routing mistake is fixed by pushing ~2 KB of JSON to Remote Config, live, with instant
rollback. Any replacement that trades this for marginal accuracy is probably a bad trade.

**Cross-platform parity is guaranteed by a code comment.** `RouterFactExtractor` says "keep
keyword lists in sync between platforms" and nothing enforces it. Verified in sync on
2026-09-19, but silent iOS/Android divergence is this codebase's most common bug class — see
[CASE_STUDIES.md](CASE_STUDIES.md).

**The router currently has no tests at all.**

---

## 2. Design: a routing test harness

Build this **first and independently of any model change.** It is the instrument that says
whether a replacement earns its cost, and the corpus outlives whatever router wins.

### Shape

A shared corpus at `tests/router/corpus.jsonl`, loaded by both platforms' existing unit-test
targets. `RuleEngine` has no platform imports, so on Android this is a plain JVM test — fast,
no device.

Per case: `id`, `prompt`, `expect`, `because`, context (`turns`, `hasImage`,
`localSupportsImage`), `notes`, `known_miss`.

### Ground truth is measured, not asserted

Hand-labeling encodes the author's intuitions, and you then tune a router to agree with a
guess. Instead: **run each prompt through both tiers and have Gemini judge the pair.**
`GeminiService` is already wired up. This runs at development time only, so there is no privacy
cost and spend is bounded by corpus size.

**The judging question is "was local good enough?" — not "which answer is better."** Cloud
almost always answers marginally better. If that is the bar, everything routes to cloud and the
product's entire argument collapses. Where "good enough" sits is a **product** decision and the
real tuning knob, so it should be an explicit parameter — you want to be able to ask "what does
loosening this by 10% do to cloud volume?"

### Four metrics, not one

- **Local-retention rate — the headline.** Accuracy alone is gameable: a router that sends 100%
  of prompts to cloud is never wrong about quality and is a total product failure. Frame the
  goal as *maximize local retention subject to a quality floor.*
- **False local** — should have escalated, didn't. Quality harm: a confidently wrong answer.
- **False cloud** — should have stayed local, went out. Privacy *and* energy harm, and it
  quietly contradicts the project's own thesis. Most routers are tuned to minimize false-local;
  this one should weight false-cloud at least as heavily. That is deliberate, and unusual.
- **Cross-platform divergence** — any case where iOS and Android disagree is always a bug. This
  converts the "keep in sync" comment into something mechanically enforced, and is probably the
  most valuable metric day to day.

### Scope is smaller than it sounds

Only the four **semantic** facts need corpus evaluation. Structural facts are measurements —
ordinary unit tests cover them. A couple hundred cases is meaningful. Seed with near-miss
paraphrases; prompts that obviously match a keyword test nothing.

### `known_miss: true` is the decision instrument

It lets the corpus record cases the current router provably cannot handle, without breaking the
build. When a semantic replacement is wired up, the measurement is simply: **how many
`known_miss` cases flip to passing?** Most of them, and the integration earns itself. A handful,
and you saved three platform ports.

### Two cautions

- **Hold out ~30% of the corpus.** Tuning substring lists against everything overfits trivially
  — you can always add one more phrase.
- **Current-events labels decay.** It is the only fact whose correctness expires. Flag those
  cases time-sensitive so a later session doesn't trust stale labels.

---

## 3. Opt-in example contribution

Users may volunteer routing examples. **Default off.**

**Per-example consent, not a settings toggle.** A toggle gets flipped once and forgotten, after
which prompts leave the device silently forever — precisely what this product exists to prevent.
A "contribute this example" action on the tier badge, showing exactly what would be sent and
allowing edits first, fits the promise. The prompt text *is* the payload; there is no
anonymizing it.

**Site copy will need qualifying.** ecoinference.ai currently states flatly that nothing is
transmitted. Any opt-in upload makes that false as written.

Plumbing: the `feedback/{feedbackId}` Firestore collection specced in
[ROADMAP_FINETUNING.md](ROADMAP_FINETUNING.md) has the same shape. Reuse the pattern, and write
the security rules **before** the collection exists — `firestore.rules` is default-deny and this
schema holds user-submitted prompts.

> **The signal already exists and is currently discarded.** Every time a user reads a local
> answer and taps *"Try with Cloud"*, that is a labeled routing miss — the cleanest one
> available, and free. It cannot leave the device without breaking the privacy promise, but it
> could plausibly adjust **local** exemplar weights on-device, improving each user's router with
> nothing transmitted. Unexplored.

---

## 4. Evaluated, not adopted: Cactus Needle

[`cactus-compute/needle`](https://github.com/cactus-compute/needle) — Apache 2.0. A 2-bit,
8–29 MB foundation model for tool calls, structured extraction and embeddings on small devices.

**It is not a router**, but it can serve as one: its own documentation notes that extraction
generalizes to classification, every response carries a calibrated confidence score, and
`needle_embed` returns sentence vectors explicitly so an app can route locally.

Integration surface is small: engines exist for `ios-arm64`, `ios-sim-arm64` and
`android-arm64`, each under 1 MB, behind a three-function C API (`needle_init`,
`needle_complete`, `needle_embed`) — bindable from Swift and JNI the same way LiteRT-LM already
is. *(It also ships a simulator slice, which the vendored LiteRT-LM frameworks do not — see
[DEVICE_TESTING.md](DEVICE_TESTING.md).)*

### If adopted, use it as an embedder — not a classifier

| Approach | Changing a routing decision costs |
|---|---|
| Today (rules JSON) | Edit ~2 KB, push to Remote Config. Minutes, live, instant rollback. |
| Needle as classifier | Labeled data → fine-tune → quantize → export → validate → 8–29 MB download. Hours to days. |
| Needle as embedder | Edit the exemplar list in Remote Config. **Minutes — same as today.** |

As an embedder the model is a fixed feature extractor shipped once and never touched, while all
tunable intelligence stays as JSON in Remote Config. That preserves live tunability. As a
classifier, every routing tweak becomes a training run — and the labeled data required is
exactly the usage data this product declines to collect.

Distribution itself is solved either way: `DownloadService` is format-agnostic, and models
already load and unload without an app restart.

### Blocking flag: telemetry

**Needle's README states telemetry is enabled by default in the binary**, disabled with
`NEEDLE_TELEMETRY=0` and `DO_NOT_TRACK=1`. Its supported-devices guide does not mention
telemetry at all, so the README is the only disclosure found.

For an application whose central claim is that nothing leaves the device, shipping a
third-party binary that reports by default is close to disqualifying. **Verify network silence
on real hardware, with and without those variables, before any integration work.** That check
is the gate; everything else is downstream of it.

### What to measure before writing any integration

1. **Network silence with telemetry disabled** — the gate condition.
2. **Router latency on the Lenovo TB336FU**, not on a Mac. That device already runs ~5 chunks/s;
   per-prompt model inference has to be affordable on the hardware that can least afford it.
3. **`known_miss` conversion rate** against the corpus. If embeddings barely beat keywords, this
   is a lot of work for nothing.

Licensing is clean — Apache 2.0 drops into the existing [NOTICE](../NOTICE) pattern alongside
LiteRT-LM.
