# docs/

Background knowledge that isn't obvious from the code. Most of this was expensive to
establish and cheap to lose.

| Doc | What's in it | Read it when |
|---|---|---|
| [ENGINEERING_NOTES.md](ENGINEERING_NOTES.md) | Architecture and the constraints the code works around — LiteRT-LM's session limits, tool-calling contracts, model sizing, theming, backend decisions | Before changing inference, tool calling, theming or model loading |
| [DEVICE_TESTING.md](DEVICE_TESTING.md) | Build/install/debug commands per platform, the traps in each, measured performance | Before touching real hardware |
| [CASE_STUDIES.md](CASE_STUDIES.md) | Ten bugs written up as narratives — how they were found, including the wrong turns | When something doesn't add up, or before assuming a familiar-looking symptom is a familiar bug |
| [DESKTOP.md](DESKTOP.md) | Electron stack, the static `llama-server` build recipe, release process | Before any desktop work or release |
| [INFRASTRUCTURE.md](INFRASTRUCTURE.md) | B2, Cloudflare, DNS, Firebase, Remote Config, and the IAM state | Before touching storage, the CDN, or anything in the GCP console |
| [PRIOR_ART.md](PRIOR_ART.md) | Why the clients are separate native implementations; what PocketPal AI taught us | Before proposing a shared codebase, or touching GPU backend selection |
| [LICENSING_RATIONALE.md](LICENSING_RATIONALE.md) | Why MIT, the licenses ruled out and why, third-party license findings, trademark strategy | Before revisiting the license, or acting on trademark |
| [MODEL_EVALUATIONS.md](MODEL_EVALUATIONS.md) | Models tested and *not* adopted, with numbers — 12B via LiteRT-LM, MLX Swift for iOS vision | Before asking "has anyone tried X?" or proposing a new runtime |
| [RELATED_PROJECTS.md](RELATED_PROJECTS.md) | What else carries the EcoInference name, and the standing rule that features don't flow between them | Before porting anything in from another EcoInference product |
| [ROADMAP_FINETUNING.md](ROADMAP_FINETUNING.md) | Planned domain models and what they'll need from this repo's Remote Config, Models tab and Firestore | Before changing the model catalog schema |
| [CODE_CONVENTIONS.md](CODE_CONVENTIONS.md) | Standing decisions — parity, Android theming, verification discipline | Before writing code against this codebase |

Elsewhere in the repo:

- [../STATUS.md](../STATUS.md) — what happened, when, and by which commit. The cross-machine
  status board.
- [../FUTURE_ENHANCEMENTS.md](../FUTURE_ENHANCEMENTS.md) — open items, parity gaps, deferred
  work, and known limitations that are not bugs.
- [../FORKING.md](../FORKING.md) — how to point this at your own infrastructure. The project
  takes no pull requests; forking is the intended path.

## What's deliberately not here

These docs were assembled partly by migrating a machine-local assistant memory store. Some of
what was in there was left out on purpose, and it's worth saying which, so nobody goes looking
for it or re-adds it:

- **Personal working preferences** — how the maintainer likes to be communicated with, when to
  ask before acting, which of his devices are personal daily drivers rather than test rigs.
  That's a working relationship, not project documentation, and this repository is headed for
  publication.
- **Unrelated projects.** The same memory store covers work with no connection to this
  codebase. None of it belongs here.
- **Secret values.** `FUTURE_ENHANCEMENTS.md` names two HuggingFace tokens that remain live in
  git history, by prefix and by commit, so they can be found and revoked. The full values are
  deliberately not written down anywhere in this repo.

## A note on how these are written

Where a conclusion was reached the hard way, the write-up keeps the evidence and the wrong
turns rather than only the answer. That's deliberate: several of these findings look arbitrary
or over-cautious without knowing what was tried first, and the wrong turns are usually the part
that generalizes.

Where something is unverified, unfinished, or a judgement call that could reasonably go the
other way, it says so. Treat unqualified claims as verified and qualified ones as leads.
