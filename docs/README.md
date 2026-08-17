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
| [LICENSING_RATIONALE.md](LICENSING_RATIONALE.md) | Why MPL, why a CLA, third-party licence findings, trademark strategy | Before revisiting the licence, or acting on trademark |

Elsewhere in the repo:

- [../STATUS.md](../STATUS.md) — what happened, when, and by which commit. The cross-machine
  status board.
- [../FUTURE_ENHANCEMENTS.md](../FUTURE_ENHANCEMENTS.md) — open items, parity gaps, deferred
  work, and known limitations that are not bugs.
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — process, CLA, project conventions, Android theming
  rules.

## A note on how these are written

Where a conclusion was reached the hard way, the write-up keeps the evidence and the wrong
turns rather than only the answer. That's deliberate: several of these findings look arbitrary
or over-cautious without knowing what was tried first, and the wrong turns are usually the part
that generalizes.

Where something is unverified, unfinished, or a judgement call that could reasonably go the
other way, it says so. Treat unqualified claims as verified and qualified ones as leads.
