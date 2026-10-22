# Three-Tier Routing — Design Draft

**Status:** draft for review, 2026-10-20. No code changed in either repo.
**Decisions:** all seven in §7 were made on 2026-10-20 and are recorded in
[ROUTING_THREE_TIER_DECISIONS.md](ROUTING_THREE_TIER_DECISIONS.md), which overrides this draft
where they differ (notably D7: Needle ships in Remote).
**Scope:** extend routing from `local | cloud` to **on-device | self-hosted | cloud**, across
`ecoinference-local` and `ecoinference-remote`.
**Read against:** [ROUTING.md](ROUTING.md), [RELATED_PROJECTS.md](RELATED_PROJECTS.md),
[CODE_CONVENTIONS.md](CODE_CONVENTIONS.md); Remote's own `STATUS.md` ("Decisions on record",
"Use only this server", fallback).

Vocabulary used throughout: **on-device** (Local's LiteRT-LM / llama.cpp models), **self-hosted**
(an OpenAI-compatible server on hardware the user owns — Remote's `ProviderKind 'self-hosted'`),
**cloud** (a hosted frontier API — Gemini in Local, Qwen MAX in Remote). "Self-hosted" is taken
from Remote's existing type rather than invented.

---

## 0. Two standing decisions this reverses — decide these first

This design cannot be built without explicitly overturning two recorded decisions. They were
made deliberately, so they should be revisited deliberately, not eroded.

1. **Local `RELATED_PROJECTS.md` (2026-08-11): features do not flow between Local and Remote.**
   It names "server configuration, provider switching, cloud retry" as exactly the
   on-device-irrelevant features that must not be dragged into Local. A self-hosted tier in
   Local *is* server configuration.
2. **Remote `STATUS.md`, Decisions on record: "Manual provider picker + offline fallback, not
   the rules-based router the mobile apps use."**

The case for revisiting both: the self-hosted tier is the one place the two products' premises
overlap — both exist so that no datacenter GPU spins up. Routing "too big for the phone" work to
the user's own box instead of Gemini serves Local's thesis directly.

**What I'd propose recording instead:** the router *contract* (rules schema, resolver semantics,
corpus) becomes a shared spec; *features* still don't flow by default. Each repo adopts the
tiers its premise allows (§2).

If you don't want to reverse either decision, the rest of this document collapses to §4 alone
(Remote gets availability-aware auto-selection, nothing else changes).

---

## 1. What exists today (grounded)

### Local (iOS, Android — desktop has no router)

- `RouterService.decide()` → `RouterFactExtractor` (structural + keyword semantic facts) →
  `NeedleEmbedder.semanticFacts()` overrides the four semantic facts when the engine is up
  (fails open to keywords) → `RuleEngine` first-match over `default_router_rules.json` v2.
- Output: `RouterTier { LOCAL, CLOUD }`. Android maps `decision == "cloud"` → CLOUD, else LOCAL;
  iOS maps `Tier(rawValue:) ?? .local`. **Any unknown decision string routes on-device on
  both** — this matters for rollout (§6).
- Live tuning: Remote Config `router_rules` and `router_exemplars`, version-gated.
- Call sites: `ChatView.send()` / `ChatScreen` branch on tier → `GeminiService.chat()` or the
  local engine. "Try with Cloud" retries a local answer. Tier badges (`#5E5CE6` cloud,
  `EcoColors.Green` local). `lifetimeLocalCount` / `lifetimeCloudCount`.
- Harness: `tests/router/corpus.jsonl` (30 cases), JVM + XCTest runners, cross-platform
  decision-dump parity test. Needle real-device network-silence gate still owed (the latency
  gate was retired — D8).
- Desktop (`AIDesktop`): llama-server sidecar, no router, no cloud tier at all.

### Remote (desktop Electron, Android, web extension; iPad dormant)

- Providers: `{ kind: 'self-hosted' | 'cloud', baseUrl, model, hasApiKey,
  supportsImageInput, contextLimit, enableThinking, systemPrompt }`. Built-ins: GX10 (vLLM,
  Qwen3.8-27B, 262k window, over Tailscale) and Qwen MAX.
- Selection is manual: header picker, "Use only this server" pin, "Try with <provider>".
- On a **self-hosted** error, offers (doesn't auto-take) the first usable cloud provider;
  accepting no longer persists the switch (the "label that was not stuck" fix).
- Reachability via `/v1/models` probe; context-window discovery from the same call.
- MCP tools are offered to self-hosted providers only (privacy boundary already encoded by
  `kind`).
- Premise: **"No model ever runs on this device."**

### Findings worth knowing before designing

- **The `current_events → cloud` rule doesn't get fresh information.** Neither
  `GeminiService.swift` nor `GeminiService.kt` sends a `tools`/search-grounding field, so
  "Who won the game yesterday?" — the canonical case routing exists to catch — goes to a model
  that also doesn't know. With three tiers this becomes a *capability* question (who has web
  access?), and Remote's self-hosted tier already has `fetch_url`.
- **`sensitive_domain` routes *to* cloud** ("benefits from broader training"). With a
  self-hosted tier, sensitive prompts could go to a large model *without* leaving the user's
  hardware. That's a product call, not something to change silently.
- **Badge colours collide.** Green means on-device in Local and self-hosted in Remote; both use
  `#5E5CE6` for cloud. A third tier needs a third colour, matched by hex per
  `CODE_CONVENTIONS.md`.

---

## 2. Which tiers each client gets

| Client | On-device | Self-hosted | Cloud | Notes |
|---|---|---|---|---|
| Local iOS / Android | yes (today) | **new** | yes (today) | The main change |
| Local desktop | yes (today) | open question | open question | Has no router today; Needle has no desktop engine vendored |
| Remote desktop / Android / web | **no** — premise | yes (today) | yes (today) | Router is 2-tier here |
| Remote iPad | — | — | — | Dormant; out of scope |

Remote stays 2-tier unless you decide to break "no model ever runs on this device" — including
for Needle itself, which is a model (35 MB). Options for Remote's semantic facts are in §4.

---

## 3. Core design: rules decide the *minimum tier*, a resolver picks the *actual tier*

Today one rule set answers two different questions at once: "what does this prompt need?" and
"what's available?" (`image_unsupported_locally` mixes a capability check into a prompt rule).
Three tiers make that untenable — the answer depends on whether the self-hosted box is up, which
has nothing to do with the prompt.

Split it into two pure steps:

```
facts ──► RuleEngine (unchanged algorithm) ──► minTier + reason + ruleId
                                                    │
availability + capabilities + user policy ──► TierResolver ──► tier + resolution reason
```

### 3.1 RuleEngine — algorithm unchanged, decision vocabulary widened

- `decision` ∈ `"on_device" | "self_hosted" | "cloud"`, read as **the cheapest tier that can
  handle this**. Tier order: on_device < self_hosted < cloud.
- Existing rules re-expressed, e.g. `long_conversation`, `long_complex_prompt`,
  `creative_writing_long`, `complex_code` → `self_hosted` (they're about size, which the
  user's own big model satisfies). `current_events` → whatever tier has web access (see 3.3).
  `sensitive_domain` → user-owned hardware with a notice and a per-prompt cloud override
  (decided — D3 in the decision log).
- First-match, Remote Config live updates, byte-identical JSON across platforms: all kept.
  `ROUTING.md` calls live tunability "the current router's best property" — this design
  doesn't touch it.

### 3.2 TierResolver — new, pure, no platform imports

Inputs: `minTier`, per-tier **availability** (`configured`, `reachable: yes | no | unknown`),
per-tier **capabilities** (`vision`, `contextLimit`, `web`), and **user policy** (`ceiling`:
highest tier allowed; `pin`: force one tier; `escalation`: `auto | ask`).

Algorithm:

1. `pin` set → that tier (mirrors Remote's "Use only this server").
2. Candidates = tiers ≥ `minTier`, ≤ `ceiling`, available, and meeting the capability
   requirements derived from facts (`hasImage → vision`, estimated tokens → `contextLimit`).
3. Pick the lowest candidate.
4. No candidate → **degrade downward** to the best available tier ≤ ceiling, with a reason the
   user can see ("Your server is unreachable — answered on-device"). Escalating *upward* past
   what the rules asked for, or to cloud when `escalation = ask`, becomes an **offer**, never
   an automatic send — the same shape as Remote's fallback bar.

Why downward by default: Local's premise is that cloud is "an explicit fallback the user can
see and override", and `ROUTING.md` weights false-cloud at least as heavily as false-local.

`reachable: unknown` must not block a send. Routing is synchronous today and must stay that way;
reachability comes from a cached probe (Remote's `/v1/models` pattern) refreshed in the
background, with failure handled by step 4 after the fact. Note the known ~20 s first-request
hang after `tailscale serve` starts — a cold probe must never sit on the send path.

### 3.3 Capabilities move out of rules

`localSupportsImage` already behaves like a capability fact. Generalise: each tier advertises
`vision`, `contextLimit`, `web` (Remote already stores the first two per provider). Rules state
needs (`needsRecency`, `hasImage`, estimated size); the resolver matches needs to capabilities.
`image_unsupported_locally` then disappears from the rules file.

### 3.4 Needle stays an embedder

`ROUTING.md` §4's reasoning holds unchanged for three tiers: a classifier makes every routing
tweak a training run and needs the usage data the product declines to collect. If size-vs-
frontier needs a new semantic distinction, it's a new exemplar category in `router_exemplars`
(e.g. separating "needs a bigger model" from "needs frontier knowledge"), tunable live.

---

## 4. Remote: what a router means there

Remote's self-hosted Qwen3.8-27B and cloud Qwen MAX are much closer in capability than Gemma
on a tablet versus Gemini. So most of Remote's routing value is **availability and capability,
not semantics**:

- Auto mode (opt-in; manual picker and pin remain as overrides): default self-hosted; resolve
  to cloud only for a capability gap (image to a non-vision model, context beyond the window)
  or unavailability — and per the existing fallback, as an offer.
- This reuses the resolver from §3.2 with `minTier` always `self_hosted` and needs **no
  semantic facts at all**.

If semantic facts turn out to be wanted, three options in order of preference:

1. **Rules + structural facts only** (no model; keyword facts if needed). Keeps the premise.
2. **Embed on the self-hosted server** (`/v1/embeddings` on a second vLLM process). Prompt
   stays on owned hardware; if the server is down you're resolving to cloud anyway.
3. **Ship Needle in Remote.** Breaks the premise — would need its own decision.

The resolver must respect Remote's existing privacy boundary: MCP tools are self-hosted-only,
and anything read from allowed folders during a cloud turn goes to Alibaba (accepted
2026-08-11). An *automatic* move to cloud mid-tool-loop would quietly widen that; the resolver
runs per user turn, never inside the agent loop.

---

## 5. Local: what adding the self-hosted tier involves

- **`SelfHostedService`** (Swift + Kotlin, mirrored) — OpenAI-compatible streaming chat,
  shaped like `GeminiService` (takes `InferenceMessage`s). Lessons from Remote worth taking
  as lessons, not code: probe with `/v1/models` not `/health`; blank model = first reported
  id; non-streaming reasoning arrives on `message.reasoning`; low `max_tokens` starves
  thinking models; empty-answer retry; stream-stall guards; `stream_options` 400 → retry
  without.
- **Settings**: server URL, optional key (secure storage), optional model. Local is a public,
  fork-first repo, so a forker's server must be first-class — nothing tailnet-specific baked
  in (same rule Remote applies to itself).
- **History separation**: `cloudHistoryMessages()` exists because cloud turns must never touch
  `inferenceHistory` (KV-cache desync). Self-hosted turns need the same treatment — generalise
  to "remote-tier history" rather than adding a second copy.
- **UI**: third badge colour (hex-matched on both platforms), "Try with Cloud" generalised to
  "Try with <tier>" on the sliced message array (the image-drop lesson), a manual tier
  override, a third lifetime counter.
- **Privacy copy**: ecoinference.ai and the README say nothing leaves the device except
  explicit cloud fallback. Self-hosted traffic leaves the device too, to the user's own box —
  the copy needs a sentence.

---

## 6. Harness and rollout

### Corpus

- Add to each case: `expect_min_tier`, and an `availability` matrix so resolver behaviour is
  tested per case (server down, no cloud key, vision-less tier, pinned).
  **Shipped 2026-10-21** (branch `feat/tier-resolver`): the schema is `expect_min_tier`,
  `expect_tier`, `expect_action` (`send`|`offer`, default `send`), `expect_fallback_tier`,
  per-case `availability` (tier → `ok`|`down`|`absent`|`no_web`|`no_vision`, applied to a
  standard profile: on-device ctx 2 000 / self-hosted 32 000 / cloud 1 000 000, self-hosted
  and cloud vision+web; **on-device vision = the case's `localSupportsImage`** — that fact is
  the on-device tier's capability under v3) and per-case `policy` (`ceiling`/`pin`/
  `offerAllCloud`). Corpus is now 34 cases: the original 30 labelled with
  `(expect_min_tier, expect_tier)` — sensitive-domain labels follow D3 — plus `av-01…04`
  exercising the matrix (absent tier ⇒ offer, D3 server-down ⇒ offer, no-web ⇒ offer, pin).
  Parity dumps `decisions-v3-{android,ios}.txt`, line = `id minTier action tier fallback`,
  compared by both suites; any divergence is a hard failure.
- Generalise the judge question from "was local good enough?" to **"was the cheapest
  available tier good enough?"**, judged pairwise along the tier order. Still development-time
  only.
- Metrics: headline becomes **datacenter-avoidance rate** (on-device + self-hosted share),
  with on-device retention reported alongside. Keep false-cloud weighted at least as heavily
  as false-local. Add a 3×3 confusion matrix. Cross-platform divergence stays a hard failure,
  now over `(minTier, tier)` pairs.
- The §2 holdout split and Gemini-judge labelling are still owed from the current harness;
  do them first — they're prerequisites for trusting any three-tier number.

### Rollout safety

Old app builds route unknown decision strings to on-device (§1). So:

- New Remote Config key (e.g. `router_rules_v3`) read only by builds that understand it;
  `router_rules` stays two-tier for old builds. Pushing three-tier JSON to the existing key
  would quietly send old clients' size-based rules to on-device.
- Bundled default rules ship byte-identical on iOS and Android, as now.

---

## 7. Open decisions

Options, costs and recommendations for each are in
[ROUTING_THREE_TIER_DECISIONS.md](ROUTING_THREE_TIER_DECISIONS.md), which also tracks status.

1. Reverse the two standing decisions in §0, or keep Remote manual?
2. Local desktop: add a router at all? (No router, no cloud, no Needle desktop engine today.)
3. `sensitive_domain`: self-hosted, cloud, or on-device-only?
4. Escalation to cloud: automatic within the user's ceiling, or always an offer?
5. Cloud tier in Local: Gemini only, or configurable (and should it get search grounding so
   `current_events` actually works)?
6. Third badge colour — and whether Remote's green-for-self-hosted changes to match.
7. Remote semantic facts: none, server-side embedding, or Needle (breaks premise)?

## 8. Suggested order

1. Record decisions (§0, §7) in both repos' docs.
2. Spec + pure code: rules v3 schema, `TierResolver`, corpus fields, parity test — Android JVM
   and iOS test targets, no UI. Finish the owed holdout/judge work alongside.
3. Local mobile: `SelfHostedService`, settings, badges, retry, history generalisation.
4. Remote desktop + Android: opt-in auto mode over the resolver.
5. Needle real-device network-silence gate — blocking any release that ships the engine.
   (No latency gate — D8.)
6. Local desktop, if decided.
