# Roadmap: Fine-Tuned Domain Models

A planned line of work, **not started**. Recorded here because it reaches into this repo's
Remote Config schema, Models tab and Firestore — so anyone changing those should know what
they're expected to carry later.

Two domain models, delivered on-device through the existing B2 + Remote Config pipeline. The
bird model is the priority; the homework helper is a stretch goal that should not begin until
the bird model has shipped and been validated on a real device.

> **Staleness warning.** This plan was written in June 2026 and specifies `.task` files as the
> mobile artifact. **The apps now use `.litertlm`.** Treat every format and conversion detail
> below as needing re-verification against the current runtime before anyone acts on it. The
> *shape* of the plan — dataset, LoRA config, delivery path, feedback loop — is what's worth
> keeping.

---

## Training setup

Fine-tuning happens on a separate machine (an ASUS Ascent GX10 — NVIDIA GB10 Grace Blackwell,
6,144 CUDA cores, 5th-gen Tensor Cores with FP4, 128 GB unified LPDDR5x at 273 GB/s). Nothing
about this repo depends on that box; it's noted only because the method below assumes its
memory budget.

- **Tool:** Unsloth Studio — verify it supports SM121 Blackwell before starting.
- **Base model:** Gemma 4 4B.
- **Method:** LoRA, **not** QLoRA — 128 GB allows BF16 precision.
- **LoRA rank:** r=16 or r=32. **Target modules:** attention layers (q, k, v, o projections).
- **~3 epochs, LR 2e-4.**

Bandwidth (273 GB/s), not compute, is the constraint on that hardware — which affects
inference speed more than training time.

## Conversion pipeline

1. Fine-tune in Unsloth → merged HuggingFace safetensors
2. Merge LoRA into base weights
3. Quantize to INT4 via `ai_edge_torch` or `llama.cpp` → GGUF
4. Convert to LiteRT using `ai_edge_torch.generative` tools
5. Package as the mobile artifact *(see the staleness warning — this said `.task`)*
6. **Dry-run the whole pipeline with unmodified Gemma 4 4B before fine-tuning anything.**

Step 6 is the one to not skip. Validating the conversion path on a known-good model separates
"the fine-tune is bad" from "the conversion is bad."

---

## Model 1 — Birds of Iowa + California (priority)

**Target user:** non-expert but knowledgeable birders — knows the common species, wants deeper
contextual guidance.

**Primary use case:** *"best season and time of day to see &lt;species&gt; near me"* —
phenology, daily activity, habitat, local site knowledge.

**Integration philosophy: complement eBird, don't compete with it.** eBird already answers
*what is being seen*; this model answers *why, when and how*, in readable narrative. That's
also why the training data is natural-language text rather than structured observation data.

Capabilities the model needs:

- Phenology — arrival, departure and peak timing, **for each state separately**
- Daily activity patterns — dawn chorus, midday behavior, roost timing
- Habitat specificity — microhabitat within a region, not just statewide
- Behavioural cues — what makes a species visible versus cryptic by season
- Local site knowledge — key Iowa and California birding locations, by season

### Data sources (crawl targets)

*Species accounts (the backbone):* Cornell All About Birds (`allaboutbirds.org` — free,
accessible, exactly the target reading level), Audubon field guide, Iowa Ornithologists' Union
(`iowabirds.org`), Audubon California, California Bird Records Committee, Xeno-canto species
pages (vocalization and behavior text).

*Phenology and seasonal text:* Iowa DNR Wildlife Diversity Program reports, USGS Breeding Bird
Survey narratives, IOU quarterly seasonal field reports (the highest-value Iowa source).

*Local site knowledge:* Iowa birding trail and site guides, Audubon California chapter site
guides, public eBird trip-report hotspot narratives.

*Conversational text:* BirdForum species discussions, Reddit r/birding and r/whatsthisbird.

> Check each source's terms and robots policy before crawling. Several of these are
> non-commercial or attribution-conditioned, and the resulting model is intended for
> distribution.

### Dataset

~5,000–8,000 examples (raised from an original 3,000–5,000 when the scope went dual-state).
Crawl → extract clean text → synthesize instruction pairs via the Claude API. Q&A pairs of
256–512 tokens each, sized for a mobile target. English only. No safety pass needed for this
model.

---

## Model 2 — Homework Helper, grades 6–12 (stretch goal)

Subject mix: math 30%, science 25%, English/writing 20%, history/social studies 15%, study
skills 10%. Grades 6–12 with age-appropriate explanation depth. English plus Spanish (~35%
more examples than English-only).

Tone: patient, step-by-step, showing reasoning rather than just answers.

**Requires a safety pass** — roughly 300 refusal examples covering cheating requests,
dangerous content, and sensitive teen disclosures. This is the substantive difference from the
bird model and the main reason it's sequenced second.

Dataset ~5,000–8,000 English examples plus ~1,500–2,500 Spanish, generated via the Claude API,
with Spanish produced by translation plus native spot-review.

---

## What this needs from *this* repo

### Remote Config

`available_models` gains per-model metadata the current schema doesn't carry — note
`version` and `feedback_enabled`, neither of which appears in the live entries today (see
[INFRASTRUCTURE.md](INFRASTRUCTURE.md#remote-config-available_models)):

```json
{
  "id": "birds-iowa-ca-v1",
  "display_name": "Birds of Iowa + California",
  "version": "1.0.0",
  "feedback_enabled": true,
  "variants": [
    { "platform": "mobile",  "model_size": "4B",  "filename": "birds-iowa-ca-v1-mobile.task",   "size_bytes": 2400000000 },
    { "platform": "desktop", "model_size": "4B",  "filename": "birds-iowa-ca-v1-4b-q4.gguf",  "min_ram_gb": 6,  "size_bytes": 2600000000 },
    { "platform": "desktop", "model_size": "12B", "filename": "birds-iowa-ca-v1-12b-q4.gguf", "min_ram_gb": 10, "size_bytes": 7800000000 }
  ]
}
```

`feedback_enabled` controls whether the in-app feedback UI appears on that model's responses —
toggleable without an app update.

**Relevant existing gap:** desktop's `remoteConfigService.ts` matches on top-level `id` only
and ignores `variants[].platform`. A model with mobile-only variants would still show as
enabled on desktop. That works by coincidence today and would stop working here.

### Feedback loop (homework model only)

Firestore `feedback/{feedbackId}`: `userId`, `question`, `modelResponse`, `modelId`,
`rating` (`positive`/`negative`), optional `correction`, `subject`, `gradeLevel`,
`reviewerRole` (`user`/`teacher`), `language` (`en`/`es`), `timestamp`, `status`
(`pending`/`accepted`/`rejected`).

Rolls out in three stages: **v1** in-app thumbs up/down plus an optional correction field;
**v2** Teacher Mode behind an invite code with an expanded correction UI; **v3** a web
dashboard and a Firebase Function threshold webhook.

The training loop closes as: Firestore (`status=accepted`) → an `exportFeedbackDataset`
Function → JSONL to B2 → the next Unsloth run.

> This collection does not exist yet, and **security rules would need writing before it does**
> — `firestore.rules` is default-deny, and this schema holds user-submitted questions.
> See [ENGINEERING_NOTES.md §7](ENGINEERING_NOTES.md).

---

## Sequence

1. Validate the LiteRT conversion pipeline with base Gemma 4 4B
2. Generate the birds dataset (Claude API batch, ~1–2 days)
3. Fine-tune in Unsloth Studio
4. Validate quality by manual spot-check
5. Convert, upload to B2, add to Remote Config
6. Wire the iOS + Android Models tab download and the in-app feedback UI
7. *(Stretch)* repeat for the homework model, with the safety pass and Spanish data
