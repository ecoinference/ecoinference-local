# Three-Tier Routing — Decision Log

The decisions [ROUTING_THREE_TIER.md](ROUTING_THREE_TIER.md) depends on (its §0 and §7). Each
entry lists the options, what each one costs, and a recommendation. **None is decided yet.**
When one is, change its status line to `Decided YYYY-MM-DD — <option>` and note anything that
changed from the recommendation.

| # | Decision | Status |
|---|---|---|
| D1 | Reverse the two standing decisions? | Open |
| D2 | Router for Local desktop? | Open |
| D3 | Where do sensitive-domain prompts go? | Open |
| D4 | Escalation to cloud: automatic or offered? | Open |
| D5 | Cloud tier in Local: provider and search grounding | Open |
| D6 | Third badge colour | Open |
| D7 | Semantic facts in Remote | Open |

---

## D1. Reverse the two standing decisions?

**Status:** Open

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

**Status:** Open

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

**Status:** Open

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

**Status:** Open

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

**Status:** Open

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

**Status:** Open

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

**Status:** Open

**Context.** Remote's premise is that no model runs on the device; Needle is a model.

**Options.** (A) None — availability and capability only. (B) Embeddings from the self-hosted
server (`/v1/embeddings`, a second vLLM process). (C) Ship Needle in Remote, overturning the
premise.

**Recommendation: A.** Remote's two tiers are close in capability, so semantic routing buys
little there. Revisit B only if usage shows a prompt class the self-hosted model handles badly.

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
