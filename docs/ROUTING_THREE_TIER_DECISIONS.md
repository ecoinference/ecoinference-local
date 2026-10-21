# Three-Tier Routing — Decision Log

The decisions [ROUTING_THREE_TIER.md](ROUTING_THREE_TIER.md) depends on (its §0 and §7). Each
entry lists the options, what each one costs, and the recommendation made before deciding.
**All were decided on 2026-10-20** (D8 and D9 were added after the original seven). Two departed from
the recommendation (D5 provider, D7); their entries say what that changes. Where a decision here differs from the design doc, this log wins.

| # | Decision | Status |
|---|---|---|
| D1 | Reverse the two standing decisions? | Decided — narrow amendment (B) |
| D2 | Router for Local desktop? | Decided — defer (A) |
| D3 | Where do sensitive-domain prompts go? | Decided — self-hosted (A) |
| D4 | Escalation to cloud: automatic or offered? | Decided — rules auto, fallback offered (B) |
| D5 | Cloud tier in Local: provider and search grounding | Decided — grounding for current events (1A); configurable provider (2B) |
| D6 | Third badge colour | Decided — new colour in both repos (A) |
| D7 | Semantic facts in Remote | Decided — ship Needle in Remote (C) |
| D8 | Needle 3 as part of the app | Decided — ships everywhere, no hardware gate |
| D9 | Crisis, self-harm, abuse and domestic violence | Decided — local human help first, then regional/national lines |

---

## D1. Reverse the two standing decisions?

**Status:** Decided 2026-10-20 — **B, narrow amendment**, as recommended. Remote's auto mode is
opt-in; manual selection stays the default and the picker and pin override it. The appendix
wording was applied to `RELATED_PROJECTS.md` on 2026-10-20; Remote's README and `STATUS.md`
changes are drafted on Remote's `docs/three-tier-routing` branch.

**Context.** Two recorded decisions block this design:

- Local [RELATED_PROJECTS.md](RELATED_PROJECTS.md) (2026-08-11): features do not flow between
  Local and Remote; server configuration and provider switching are named as features Local
  has no use for.
- Remote `STATUS.md`, Decisions on record: manual provider picker plus offline fallback, not the
  rules-based router the mobile apps use.

**Options.**

| Option | What it means | Cost |
|---|---|---|
| A. Reverse both | Local gains a self-hosted tier; Remote gains an opt-in auto mode | Both docs rewritten; the "no parity" rule loosens |
| B. Narrow amendment | The router *contract* (rules schema, resolver semantics, corpus format) is shared; features still don't flow unless a repo adopts one by its own decision | Two short doc edits; the rule keeps most of its force |
| C. Remote only | Remote gets auto mode over its own two tiers; Local untouched | Local's self-hosted tier never happens |
| D. Neither | Status quo | Design shelved |

**Recommendation: B.** It allows the work without reopening the general parity question the
original rule exists to prevent. Proposed wording is in the appendix.

---

## D2. Router for Local desktop?

**Status:** Decided 2026-10-20 — **A, defer**, as recommended.

**Context.** `AIDesktop` has no router and no cloud tier. Needle is only vendored for
`ios-arm64`, `ios-sim-arm64` and `android-arm64`; desktop would need a Node binding or the
upstream WASI build, neither of which has been evaluated.

**Options.** (A) Defer until mobile ships three tiers. (B) Add a rules-only router — structural
and keyword facts, no Needle. (C) Full parity with mobile, Needle included.

**Recommendation: A.** Desktop already runs the largest local models (Gemma 4 12B on Metal), so
it gains least from routing, and adding a tier there means building cloud *and* self-hosted
from nothing.

---

## D3. Where do sensitive-domain prompts go?

**Status:** Decided 2026-10-20 — **A, self-hosted**, as recommended, with a clarification
the same day: the user is told and can override.

**Behaviour.** When a prompt is classed as sensitive:

1. **Stay on user-owned hardware by default.** User-owned means on-device or self-hosted.
   Self-hosted if it's available, otherwise on-device. Never cloud without the user's say-so.
2. **Tell the user.** A short, plain notice with the reply — for example, "This looks like a
   private legal, medical or financial question, so it stayed on your own hardware." — that
   encourages keeping it there.
3. **Offer the override.** A visible action to send this prompt to the cloud (frontier/API)
   model instead, saying plainly that the prompt will leave the user's hardware. It applies to
   that one prompt only; it never changes the active tier or a setting (the lesson from
   Remote's "label that was not stuck" fallback bug).

This is user-initiated, so it doesn't conflict with D4: D4 governs what the app does on its
own, and the override is the user choosing. It also takes precedence over the old
`sensitive_domain → cloud` rule, which goes away. Applies in both repos wherever semantic
facts exist — Local mobile, and Remote once Needle ships (D7).

**Worked example:** *"I have liver cancer, should I tell my employer?"*

- **Expected:** stays on user-owned hardware (self-hosted if reachable, else on-device), with
  the notice and the cloud override offered.
- **Today's keyword router misses it.** None of the sensitive-domain keywords match
  ("diagnos", "should i take", "symptoms of", "can i sue", …), so it falls through to the
  default. On the old two-tier rules that happens to keep it local, but with no notice and for
  the wrong reason.
- **The Needle exemplars may miss it too.** The 14 bundled `mentionsSensitiveDomain`
  exemplars are all *asking for professional advice* — medication, diagnosis, lawsuits, taxes,
  retirement savings. This prompt is different: it *discloses* a private health fact, and the
  question is about employment. Whether it clears the 0.200 threshold is unmeasured.
- **What D3 changes about the category.** The fact was built to mean "needs a better model
  for professional advice". Under D3 it means "private — keep it on the user's hardware",
  which is broader: disclosing a diagnosis, an employment or immigration situation, debts, a
  legal problem. The exemplar list should grow to cover disclosure as well as advice-seeking —
  a Remote Config change, no app release. Proposed set and measurement plan:
  [ROUTING_SENSITIVE_EXEMPLARS.md](ROUTING_SENSITIVE_EXEMPLARS.md).
- **Corpus:** a good case for the three-tier corpus (`expect_min_tier` as user-owned, plus the
  expected notice), and a `known_miss` against the keyword router. Not added to
  `tests/router/corpus.jsonl` yet, because the current schema would have to label it
  `cloud` — the opposite of D3.

**Context.** `sensitive_domain` currently routes to **cloud**, on the reasoning that
legal/medical/financial questions benefit from the larger model. A self-hosted tier offers a
large model that doesn't leave the user's hardware.

**Options.**

| Option | minTier | If self-hosted unavailable |
|---|---|---|
| A. Self-hosted | `self_hosted` | Offer cloud, answer on-device if declined |
| B. Cloud, as today | `cloud` | Unchanged |
| C. On-device only | `on_device` | — |
| D. User setting | Configurable, default A | Per setting |

**Recommendation: A.** It keeps the quality reason for routing these prompts off the device
while matching the privacy argument the product makes. B is defensible if answer quality on
these topics is judged more important than where the prompt goes — but then the reason string
should say so.

---

## D4. Escalation to cloud: automatic or offered?

**Status:** Decided 2026-10-20 — **B, with a setting for A**, as recommended.

**Context.** Local's premise is that cloud is "an explicit fallback the user can see and
override". Today a rule that says `cloud` sends to cloud immediately, with a visible badge and
reason. Remote's fallback is always an offer.

**Options.** (A) Offer every time. (B) Automatic when the *rules* ask for cloud; an offer when the
resolver would escalate past what the rules asked for (e.g. self-hosted is down). (C) Automatic
always, within the user's ceiling.

**Recommendation: B, with a setting for A.** It preserves today's behaviour for rule-driven cloud
sends and never escalates to cloud just because a server is down without asking first.

---

## D5. Cloud tier in Local: provider and search grounding

**Status:** Decided 2026-10-20 — **1A** (grounding only for `current_events` routes), as
recommended; **2B** (configurable OpenAI-compatible cloud provider alongside Gemini), which
departs from the recommendation.

**What 2B adds to the work:** a second cloud client on iOS and Android (OpenAI-compatible,
streaming), provider settings with the key in secure storage, and a choice of which cloud
provider a `cloud` decision uses. The client is the same shape as the self-hosted client the
design already needs (§5), so the two should be one OpenAI-compatible client configured twice,
not two implementations. Open detail: whether grounding (1A) applies only when Gemini is the
selected cloud provider, since other providers have no equivalent field.

**Context.** Local's cloud tier is Gemini (`gemini-flash-latest`). Neither `GeminiService.swift`
nor `GeminiService.kt` sends a search or grounding tool, so the `current_events` rule sends
recency questions to a model that doesn't know the answer either.

**Two separate questions.**

1. **Search grounding.** (A) Enable it for prompts routed by `current_events`. (B) Enable it for
   every cloud turn. (C) Leave it off and drop `current_events` as a cloud reason.
2. **Provider.** (A) Gemini only. (B) Configurable OpenAI-compatible cloud provider alongside
   Gemini.

**Recommendation: 1A, 2A.** Grounding only where it's the reason for the route keeps cost and
behaviour change contained. A configurable cloud provider is real scope (settings, keys, a
second client) with no current need.

---

## D6. Third badge colour

**Status:** Decided 2026-10-20 — **A, new colour in both repos**, as recommended. The hex
value is not chosen yet; it has to be contrast-checked in both themes before any UI work.

**Context.** Local: on-device = `EcoColors.Green`, cloud = `#5E5CE6`. Remote: self-hosted =
green, cloud = `#5E5CE6`. Three tiers need three colours, hex-matched across platforms per
[CODE_CONVENTIONS.md](CODE_CONVENTIONS.md), legible in both themes (≥ 3:1 for UI components in
light mode — the Android theming section lists the colours that have already failed this).

**Options.** (A) New colour for self-hosted in both repos; Remote moves off green. (B) New colour
in Local only; Remote keeps green (the repos disagree on what green means). (C) Shape/icon
distinction instead of colour.

**Recommendation: A**, colour to be chosen and contrast-checked in both themes before any UI
work. Green stays reserved for "on this device", which is the product's core claim.

---

## D7. Semantic facts in Remote

**Status:** Decided 2026-10-20 — **C, ship Needle in Remote**, which departs from the
recommendation and overturns Remote's premise that no model runs on the device.

**What C commits to:**

- **Remote's premise changes.** Its README ("No model ever runs on this device") and
  `STATUS.md` need rewording to something like "no *chat* model runs on this device; a small
  routing embedder does." The appendix wording for `STATUS.md` (no semantic routing) is
  superseded on that point.
- **The telemetry gate applies.** Needle's README says telemetry is on by default in its
  binaries. Local verified its linked C engines network-silent on macOS only; Remote needs the
  same check on each engine it links, on real hardware.
- **Engines per client.** Android can reuse the `android-arm64` engine Local already wraps.
  The Electron desktop (macOS, Windows ARM64 and x64) and the web extension have no vendored
  engine; they need a Node binding or the upstream WASI/browser build, neither evaluated.
- **Licensing.** Remote currently "bundles no third-party weights or runtimes"; it would need a
  NOTICE entry for Needle (Apache 2.0), following Local's pattern.
- **Live tuning.** Remote has no Remote Config (Firebase was removed 2026-08-12). The exemplar
  config either ships bundled only, or Remote needs another update channel.
- **Design doc §2 and §4** describe Remote as two-tier with no on-device model. Needle is a
  router, not a chat tier, so Remote stays two-tier for answers; §4's "no semantic facts"
  default no longer holds.

**Context.** Remote's premise is that no model runs on the device; Needle is a model.

**Options.** (A) None — availability and capability only. (B) Embeddings from the self-hosted
server (`/v1/embeddings`, a second vLLM process). (C) Ship Needle in Remote, overturning the
premise.

**Recommendation: A.** Remote's two tiers are close in capability, so semantic routing buys
little there. Revisit B only if usage shows a prompt class the self-hosted model handles badly.

---

## D8. Needle 3 is part of the app — no hardware gate

**Status:** Decided 2026-10-20. Added after D1–D7; not one of the design doc's original open
questions.

Needle 3 ships as a standard part of the app on every device, like the router rules. There is
no minimum-hardware requirement for it and no latency gate before release. The intended target
is a mid-tier modern phone with 4 GB of RAM or more, but a device below that isn't blocked or
treated specially.

This retires `ROUTING.md` §4's Gate 2 (router latency on the Lenovo TB336FU), which was never
measured.

**Needle and the network.** Two separate things, stated so they aren't conflated:

1. **Needle itself never makes a network call.** It is a local function: text in, vector out.
   This is a requirement on the engine, and the network-silence gate is how it's verified —
   the gate stays, because the engine is a third-party binary whose upstream README says
   telemetry is on by default (in the Python CLI; the linked C engines were clean on macOS,
   real devices not yet checked). If a future upstream build ever phones home, the gate is
   what catches it.
2. **Needle's output can lead the app to make a network call.** Its semantic facts feed the
   rules, and a decision of `self_hosted` or `cloud` means the app sends the prompt to that
   server. That outbound call belongs to the app, not to Needle, and is governed by the
   resolver: the user's ceiling and pin, D3 (sensitive → self-hosted), D4 (cloud reached only
   because a lower tier is down is an offer, never automatic), and a visible tier badge and
   reason on every reply. In Remote, MCP tools stay self-hosted-only regardless of routing.

Scope: the router only — this doesn't change which chat models the Models tab offers on which
devices.

---

## D9. Crisis, self-harm, abuse and domestic violence

**Status:** Decided 2026-10-20, in Mark's words: *"I want to assist people in crisis. Perhaps we
encourage the user to find local, human-based resources first. If that is not available at the
moment, any state or nation-wide crisis service can be displayed and encouraged."*

**What that means for the router and the app:**

1. **Detection — a separate fact, `mentionsCrisis`.** Its own exemplar category and threshold
   in `router_exemplars`, tuned for recall. Covers suicidal thoughts and self-harm, and abuse or
   domestic violence (same handling, decided the same day). Idioms ("this commute is killing
   me") go into the corpus as near-miss negatives. Exemplars are not drafted yet.
2. **The first thing shown is a fixed resource card, not model text.** It replaces D3's privacy
   notice for these prompts. It's app-provided, so it reads the same every time regardless of
   which model answers, and it comes before the reply. Its content is ordered the way Mark
   described:
   - **People nearby first** — local, human help: emergency services if someone is in immediate
     danger, a local crisis centre, and reaching out to someone the user trusts.
   - **Then regional or national crisis services** — a state or nationwide line (in the US,
     988) — shown and encouraged when local help isn't available right now.
   The model still answers; the card doesn't block the conversation.
3. **Resources come from Remote Config, keyed by region**, so numbers can be corrected or added
   without an app release, like the routing rules. Region comes from the device's locale and
   region setting, **not from location services** — asking for location permission in that
   moment is the wrong ask. (iOS `LocationService` and Android `LocationPreamble` exist for the
   Python tools; they should not be used here.) Unknown region → a nationwide or international
   directory. Every number needs checking before it ships.
4. **Routing tier.** Not separately chosen. Defaults to D3's: user-owned hardware (self-hosted if
   reachable, else on-device), never automatically to cloud. The D3 cloud override stays
   available but isn't promoted — the card is the focus, not a settings choice.

**Open details:**

- Whether to add safe-messaging guidance to the answering model's system prompt for that turn
  (offered as an option; not chosen).
- **Shared devices** (abuse and domestic violence): conversation titles, previews and history can
  reveal what was asked to someone else using the phone. Needs its own look before shipping.
- The card's wording and resource list should be reviewed against published safe-messaging
  guidance and by someone qualified. This decision sets the structure, not the final text.

---

## Appendix: proposed wording for D1 option B

For [RELATED_PROJECTS.md](RELATED_PROJECTS.md), after "The standing rule: features do not flow
between them":

> **Amendment, YYYY-MM-DD: the router contract is shared.** The routing rules schema, the tier
> resolver's semantics and the routing corpus format are a common specification across Local
> and Remote, so that the same prompt and the same availability produce the same tier in both.
> This shares a *contract*, not features: each repo still adopts a tier, a setting or a UI
> element only by its own recorded decision, and the absence of a feature in one repo is still
> not a gap to close in the other. See [ROUTING_THREE_TIER.md](ROUTING_THREE_TIER.md).

For Remote `STATUS.md`, replacing the "Manual provider picker" line under Decisions on record:

> - **Manual provider picker + offline fallback by default; opt-in auto mode** (YYYY-MM-DD).
>   Auto mode selects by availability and capability using the shared tier resolver; the
>   picker, the pin and "Try with <provider>" remain as overrides. No semantic routing.
