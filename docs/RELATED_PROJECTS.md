# Related Projects

Several things carry the EcoInference name. They are **separate products in separate
repositories**, and conflating them causes real wasted work — most often by proposing that a
feature from one be ported into another.

This page exists to draw the boundaries.

---

## What's in *this* repo

**EcoInference** — on-device AI. Three independent native clients (iOS, Android, Electron
desktop) that share a Firebase backend and a B2/Cloudflare model CDN. Inference runs on the
user's own hardware; a cloud tier exists only as an explicit fallback the user can see and
override.

The three clients mirror each other's features deliberately but share no code. See
[PRIOR_ART.md](PRIOR_ART.md) for why that's the architecture.

---

## EcoInference Remote — separate repo

A **pure API client. No local model ever runs.** Two OpenAI-compatible backends behind one
code path (different base URL, key and model name): a self-hosted vLLM server, and Qwen 3.8
MAX via Alibaba's API. Three clients of its own — Electron desktop, Kotlin/Compose Android,
and a SwiftUI iPad app. Single-user, no auth.

From a user's point of view it resembles what this app does. The plumbing is entirely
different: no model downloads, no bundled inference binary, no llama.cpp or LiteRT-LM.

> Its own `STATUS.md` is the source of truth for its feature state, and `API-NOTES.md`
> records what its API actually does as opposed to what its docs claim. Read those there;
> don't infer its behaviour from this repo.

### The standing rule: features do not flow between them

**Do not port an EcoInference Remote feature into the iOS, Android or desktop apps here, and
do not treat a feature's absence in Remote as a gap to close.** This was stated explicitly on
2026-08-11.

The reason is that they have different premises — one runs inference on the device, the other
never does. Treating them as a family that must stay in parity would generate a lot of
pointless work and would drag on-device-irrelevant features (server configuration, provider
switching, cloud retry) into apps with no use for them.

**The cross-platform parity rule in [CONTRIBUTING.md](../CONTRIBUTING.md) governs iOS ↔
Android within this repo only.** It does not reach Remote in either direction.

### What *does* flow: lessons, not code

This repo's history is a catalogue of already-paid-for mistakes, and reading it before
building the equivalent elsewhere is cheap. Two that have already paid off in Remote:

- **"Try with Cloud" shipped a bug where the retry silently dropped the attached image** —
  avoided there by slicing the real message array rather than rebuilding the turn.
- **Badge colours drifted from Apple's systemIndigo `#5E5CE6`** until it was flagged — matched
  deliberately there from the start.

Borrowing a hard-won lesson creates no obligation to push anything back.

---

## ecoinference.ai — separate repo

The public website, and the highest-visibility surface the brand has. Also hosts a white
paper, *The Case for Greener AI*, aimed at a general audience.

Relevant to this repo in one concrete way: **the ™ marking work covered this repository
only.** The site and the App Store / Play Store listing *descriptions* also want ™ (though not
the store app-name field). Neither has been done — see
[LICENSING_RATIONALE.md](LICENSING_RATIONALE.md#trademark-strategy).

---

## Fine-tuned domain models — planned, not started

Bird and homework-helper models trained on separate hardware and delivered *into this repo's*
clients through the existing B2 + Remote Config pipeline. Unlike the projects above, this one
does reach into this codebase — it needs Remote Config schema changes, Models-tab work, and a
new Firestore collection with rules to match.

See [ROADMAP_FINETUNING.md](ROADMAP_FINETUNING.md).

---

## AIFlutter/ — in this working tree, not in the product

A throwaway diagnostic harness that re-tests whether Flutter's LiteRT-LM bindings are viable
today. Untracked, not shipped, and not part of the build. See
[PRIOR_ART.md](PRIOR_ART.md#the-re-check-aiflutter-2026-07-25) for what it found and what's
still untested.
