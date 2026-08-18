# Model Evaluations

Models that were tested and *not* adopted, and why. Kept because "did anyone try X?" is a
recurring question, and a negative result with numbers is worth more than a vague memory that
it didn't work out.

For the models actually shipping, see the README. For the sizing evidence behind the mobile
catalog, see [ENGINEERING_NOTES.md §4](ENGINEERING_NOTES.md#4-model-sizing-and-device-capability)
and [DEVICE_TESTING.md](DEVICE_TESTING.md#performance-reference).

---

## Gemma 4 12B via LiteRT-LM — shelved (June 2026)

Evaluated `litert-community/gemma-4-12B-it-litert-lm` (6.1 GB `.litertlm`) on a 16 GB Apple
Silicon Mac, using the `litert-lm` CLI v0.13.1 (`uv tool install litert-lm --python 3.10`).

**Verdict: too slow to use. Shelved pending a mobile-optimized artifact from Google.**

| Measure | Result |
|---|---|
| Decode | **0.61 tok/s** |
| TTFT | 15 s |
| Init | 80 s |

**Why it's slow:** 16 GB of unified memory can't hold the 12B weights and the Metal GPU
working set at the same time. This is memory pressure, not a compute limit — a 24 GB+ machine
would likely tell a different story.

Other findings worth keeping:

- **The GPU backend is mandatory.** `--backend gpu` (Metal) is required; the model rejects the
  CPU backend outright.
- **Tool calling works correctly and is already compatible.** It emits clean Format A JSON —
  `<tool_call>{...}</tool_call>` — which the existing `AgentLoop` parses on both platforms
  without modification.
- **Quality is strong.** Correct sympy root answers, clean tool-call format, no hallucination
  in spot checks.
- **No native iOS/Android LiteRT for 12B** as of June 2026 — macOS and Linux only.

**When to revisit:** if Google ships a mobile-optimized or QAT `.litertlm` for 12B, the
`AgentLoop` code needs no changes, since the tool-call format already matches. Re-run the
benchmark then.

> **Don't confuse this with desktop's 12B.** The desktop app *does* ship Gemma 4 12B, at
> ~12.7 tok/s — but through **llama.cpp/GGUF**, a completely different runtime. This negative
> result is specific to the LiteRT-LM path. See [DESKTOP.md](DESKTOP.md#catalog).

---

## MLX Swift for iOS vision — explored, not started (July 2026)

Explored [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) and the newer
[mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) (where `MLXLLM`, `MLXVLM` and
`MLXLMCommon` now live) as a **possible second inference backend for iOS vision only** — not a
full engine swap, which would mean a new model format, a new download pipeline, and redoing
tool calling.

**The specific gap it could close:** iOS has vision explicitly disabled on E4B
(`supportsVision: false`, because 162 of 1477 SigLIP ops aren't XNNPack-delegatable in the
current native LiteRT-LM build). Android has no such gap. MLX is Apple's own framework, runs
on Metal rather than the CPU-delegate path, and ships a `ChatSession` API plus
`MLXGuidedGeneration` (schema-constrained output) that both look structurally better than the
raw LiteRT-LM C bridge.

Candidates checked on `mlx-community`, sizes confirmed via the HF API rather than estimated:

| Model | Size | Why it's on the list |
|---|---|---|
| `mlx-community/gemma-4-e4b-it-4bit` | 5.18 GB | **The one that matters** — same base model that's vision-disabled on iOS today. A direct test of whether MLX does what LiteRT-LM can't. |
| `mlx-community/gemma-4-e2b-it-4bit` | 3.58 GB | Control — vision already works here via LiteRT-LM, so it's a known-good quality baseline. |
| `mlx-community/Qwen3-VL-4B-Instruct-4bit` | 3.11 GB | Cross-backend comparison against the desktop NPU catalog. |
| `mlx-community/Qwen3-VL-8B-Instruct-4bit` | 5.78 GB | Larger, likely better, still fits. |
| `mlx-community/LFM2-VL-1.6B-4bit` | 1.47 GB | Tiny — for smoke-testing the MLX pipeline itself first. |

**Target device discussed:** iPad Pro M5, 16 GB. iPadOS's per-app memory ceiling is roughly
60–75% of total RAM (~10–12 GB here), so even the 5.78 GB candidate has real room once
KV-cache and image-encoding buffers are counted. iPad isn't a new device class for this
codebase — see [CASE_STUDIES.md §6](CASE_STUDIES.md#6-a-bug-that-was-structurally-impossible-on-the-test-device--ipad-blank-screen).

**Status: explicitly deferred. No prototype exists.**

If picked back up, the plan discussed was a small standalone MLX Swift spike — mirroring the
throwaway-harness pattern in [PRIOR_ART.md](PRIOR_ART.md#the-re-check-aiflutter-2026-07-25),
not touching the shipped app — that loads `gemma-4-e4b-it-4bit` and runs a real image plus a
real question through it on the iPad. Get a concrete answer on whether MLX closes the vision
gap before considering anything more invasive. **The real cost is carrying a second inference
runtime on one platform only**, which is the thing to weigh, not the prototype effort.
