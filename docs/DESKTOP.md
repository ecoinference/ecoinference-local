# Desktop (Electron)

`AIDesktop/`. A different runtime, a different model format, and a different set of problems
from the mobile clients — findings do not transfer in either direction.

**Companions:** [INFRASTRUCTURE.md](INFRASTRUCTURE.md) for the CDN and update channel ·
[CASE_STUDIES.md §7](CASE_STUDIES.md) for how two releases shipped broken.

---

## Stack

- **Electron 35 + electron-vite**, React 18 + TypeScript
- **Inference:** a `llama-server` sidecar (llama.cpp), OpenAI-compatible HTTP on port **8765**
- **Auth:** Firebase JS SDK, email/password only
- **Models directory:** Electron `userData` — on macOS,
  `~/Library/Application Support/aidesktop/models/`
- **Downloads:** direct public CDN URLs, no Firebase Function
- **Updates:** `electron-updater` against `releases.ecoinference.ai`, generic provider

On Windows ARM64 the inference path is different again: the app shells out to a
user-installed `geniex` on `PATH` for the NPU models. Nothing from Qualcomm is bundled — see
the README's note before changing that.

## Catalog

| ID | Display | File | Size | Vision |
|---|---|---|---|---|
| `gemma4-e4b-it` | Gemma 4 E4B | `gemma-4-E4B-it-Q4_K_M.gguf` | 4.98 GB | No — no `mmproj` exists in the source repo |
| `gemma4-12b-it` | Gemma 4 12B | `gemma-4-12B-it-qat-UD-Q4_K_XL.gguf` | 6.72 GB | No — an `mmproj` exists upstream, wiring deferred |

Sources: `unsloth/gemma-4-E4B-it-GGUF` and `unsloth/gemma-4-12B-it-qat-GGUF` (QAT quant).
Windows ARM64 additionally carries Qwen3 8B and Qwen3-VL 4B via GenieX.

Both ids must match Remote Config's `available_models` exactly — see
[INFRASTRUCTURE.md](INFRASTRUCTURE.md#remote-config-available_models) for the silent-failure
mode when they don't.

**Throughput on an M-series Mac (Metal):** 12B ≈ 12.7 tok/s, E4B ≈ 25.6 tok/s — roughly half,
as expected for a ~3× larger model. Note that 12B emits a `reasoning_content` scratchpad
before its answer (thinking-style template), so a low `max_tokens` can exhaust the budget on
reasoning before any visible output appears. Not a bug; it just needs headroom.

## Structure

| File | Purpose |
|---|---|
| `src/main/index.ts` | IPC for fs/llama/theme/updater/appInfo, single-instance lock, quit lifecycle, orphan cleanup |
| `src/main/llamaServer.ts` | Subprocess manager — start/stop/status/killSync, health-based readiness, `ensureClean()` |
| `src/main/autoUpdate.ts` | `electron-updater` wiring, 4-hourly checks, status forwarded to renderer |
| `src/main/versionTracker.ts` | Compares running version against `last-version.json` in `userData` for the "just updated" banner |
| `src/preload/index.ts` | `window.fsOps` / `llama` / `theme` / `updater` / `appInfo` bridges |
| `src/renderer/src/services/firebase.ts` | Firebase init — see the offline-auth note below |
| `src/renderer/src/services/b2Service.ts` | Constructs the public CDN URL directly |
| `src/renderer/src/services/remoteConfigService.ts` | Remote Config → allowlist (id-only, not variant-aware) |
| `src/renderer/src/models/ModelInfo.ts` | Catalog |
| `src/renderer/src/context/AppContext.tsx` | Auth, per-model download/load state, chat streaming |
| `src/renderer/src/screens/` | `AuthScreen`, `ModelsScreen`, `ChatScreen`, `AboutScreen` |
| `src/renderer/src/components/Sidebar.tsx` | Nav, sign-out, update-status banner |

---

## Traps, each of which has already bitten

**Never reference bare Node globals in `src/renderer/**`.** `nodeIntegration: false`, so a
bare `process.platform` in `Sidebar.tsx` crashed the sandboxed renderer into a blank white
screen. Use `window.electron.process.platform`, or IPC for anything fs-related.

To see renderer errors in a terminal without opening DevTools, forward them:
`webContents.on('console-message', …)` → main-process stdout. That is the only practical way.

**Readiness must poll `GET /health`, not grep stdout.** The original check looked for a log
line that the `--log-disable` flag suppressed, producing "startup timed out" while the server
was running fine.

**Kill orphaned servers at startup.** `ensureClean()` in `llamaServer.ts` checks `/health` and
kills whatever is bound to the port (via `lsof` / `taskkill`) before assuming a clean slate.

**Quit means quit.** This is a single-window utility, not a document app, so
`window-all-closed` always calls `app.quit()` — dropping the macOS stay-in-dock convention
deliberately. `before-quit` guarantees `llamaServer.stop()` completes; `process.on('exit')`
calls a synchronous `killSync()` as a last resort for SIGINT/SIGTERM.

**Single instance.** `app.requestSingleInstanceLock()`; a second launch focuses the existing
window via `second-instance`.

**Per-model state, not global booleans.** Loading state and download errors are both tracked
by model id (`loadingModelId`, `downloadErrorModelId`). See
[CASE_STUDIES.md §8](CASE_STUDIES.md#8-the-same-bug-independently-on-three-platforms) — this
bug class has recurred on all three platforms.

**Offline auth: `file://` defeats Firebase persistence detection.** The packaged app loads its
renderer via `loadFile()`, so the origin is `file://`, and `getAuth()` silently falls back to
**in-memory** persistence when it can't confirm a storage backend — throwing the session away
on every quit. Online that's an annoyance; offline it's fatal, since signing in needs the
network. `npm run dev` hides it completely (Vite's `http://` origin persists fine). Fixed by
calling `initializeAuth()` with an explicit persistence chain. **Still unverified on Windows.**

---

## Getting a `llama-server` binary

**`AIDesktop/resources/bin/` is empty and gitignored.** The binaries used to be committed —
~130 MB of them across macOS and two Windows architectures — which is most of the reason the
repo was 310 MB. They were purged on 2026-08-20. `extraResources` in `package.json` bundles
whatever is sitting in that directory when you package; it does not fetch or build anything.

On Windows, take the prebuilt binaries from a [llama.cpp
release](https://github.com/ggml-org/llama.cpp/releases). On macOS, build a static one:

### Static `llama-server` build (macOS arm64)

The Homebrew binary dynamically links eight libraries, several via absolute
`/opt/homebrew/opt/…` paths — it only works on machines with the identical formulae installed,
which defeats the point of distributing to arbitrary users. Build statically:

```bash
git clone --depth 1 https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
cmake -B build -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=ON
cmake --build build --config Release --target llama-server -j$(sysctl -n hw.ncpu)
```

`-DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=ON` matters — otherwise it auto-detects Homebrew's
OpenSSL and you're back to a dynamic dependency.

Verify with `otool -L build/bin/llama-server`: every dependency should be under
`/System/Library` or `/usr/lib`, nothing under `/opt/homebrew`. Result is ~15 MB. Copy to
`AIDesktop/resources/bin/llama-server` and `chmod +x`.

Built from llama.cpp commit `571d0d5`. Measured *faster* than the Homebrew build — ~32.6 vs
~25.6 tok/s on E4B — likely better CPU feature detection (`dotprod`, `i8mm`, `sme`) in a
from-source build.

**arm64 only.** `mac.target.arch` was deliberately narrowed from `["arm64", "x64"]` to
`["arm64"]`, because bundling an arm64 binary into an x64 build ships a non-functional Intel
package and there is no reverse Rosetta. Cross-compiling
(`-DCMAKE_OSX_ARCHITECTURES=x86_64`) is deferred, not attempted. Do that before re-enabling
x64.

Windows needs the same treatment for `llama-server.exe`, with the same lesson: don't trust a
dynamically-linked equivalent.

---

## Release process

```bash
npm run package:mac -- --publish never
```

`package:mac` and `package:win` now run `electron-vite build` first — that was the bug that
shipped two empty releases. `--publish never` stops electron-builder erroring out trying to
auto-upload, since B2 isn't a recognized publish provider.

`extraResources` bundles whatever is already at `resources/bin/llama-server`. **It does not
build it for you** — run the recipe above first.

**Before uploading anywhere**, launch the actual packaged binary:

```bash
./dist/mac-arm64/EcoInference.app/Contents/MacOS/EcoInference
```

Confirm the sign-in screen renders and that Load and Chat genuinely work. This step was
skipped for the first two releases and both shipped broken. `npm run dev` working is not
sufficient evidence — see [CASE_STUDIES.md §7](CASE_STUDIES.md#7-two-releases-shipped-broken-because-npm-run-dev-worked).

Then manually upload `dist/EcoInference-*.dmg`, `dist/*.blockmap` and `dist/latest-mac.yml` to
the `ecoinference-releases` bucket root.

The publish config in `package.json`:

```json
"publish": {
  "provider": "generic",
  "url": "https://releases.ecoinference.ai/file/ecoinference-releases/",
  "channel": "latest"
}
```

Updates are checked 10 s after launch, then every 4 hours, and only in production builds
(`!is.dev` guard).

> **v0.1.0 in B2 is still the original broken upload.** Harmless while `latest-mac.yml` points
> at 0.1.1, but don't treat it as installable. v0.1.1 was rebuilt correctly and re-uploaded.

**Code signing** (macOS notarization + Windows Authenticode) is deferred. Without it,
`electron-updater` can detect and download updates, but installing them may be blocked by OS
gatekeeping — especially on macOS.
