# EcoInference Desktop — Windows Build Handoff

Written 2026-07-19 at the end of a macOS session that got the desktop app fully working
end-to-end on Apple Silicon. This doc is meant to be pasted into a fresh Claude Code session
on the Windows machine to pick up work — primarily **building and testing the Windows target**,
which has never been attempted.

## What's already working (verified on macOS, not yet touched on Windows)

Full pipeline confirmed working on a real **packaged** build (not just `npm run dev`):
sign up → Models screen → Download (real public CDN) → Load → Chat → real streamed response.
Both Gemma 4 E4B and 12B models work. Auto-update detection, an About screen, a loading
status indicator, and a "just updated" banner are all implemented and verified.

**Do not trust `npm run dev` working as evidence anything works in a packaged build.** This
bit us hard on macOS — two packaging bugs (missing renderer, missing llama-server binary)
shipped in two consecutive "releases" before anyone actually launched the packaged `.app`
directly. Always launch the actual built executable and manually verify sign-in → load → chat
before considering a build good.

## Project structure

- Repo: `https://github.com/ecoinference/gemma4-pilot.git`, branch `main`
- Desktop app: `AIDesktop/` — Electron 35 + electron-vite + React 18 + TypeScript
- Sibling projects in the same repo: `AIiOS/` (Swift), `AIAndroid/` (Kotlin), `functions/`
  (Firebase Functions, TypeScript) — not relevant to Windows build work, ignore unless asked

## ⚠️ Nothing in AIDesktop/ is committed to git yet

As of this handoff, **the entire `AIDesktop/` directory is untracked in git** — it's never
been committed. If you `git pull` on Windows, you get an empty (or absent) AIDesktop folder.
Ask the user how they want to get the code onto the Windows machine — likely either:
(a) they push it from the Mac first (needs a `.gitignore` added — `node_modules/`, `dist/`,
`out/` must be excluded before any `git add`, neither currently exists), or
(b) some other transfer method (network share, USB, cloud sync).
**Do not assume the code is there — verify `AIDesktop/src/` actually exists before doing
anything else.**

## The core lesson: static linking, every time

The single most important thing learned this session: **never bundle a dynamically-linked
`llama-server` binary.** The straightforward approach (`brew install llama.cpp`, copy the
binary from `/opt/homebrew/bin/llama-server`) produces a binary that depends on 8 shared
libraries, several via absolute Homebrew paths — it only runs on the exact machine it was
built on. The fix was building `llama-server` from source with static linking, verified via
`otool -L` (macOS) showing only system framework dependencies, nothing under `/opt/homebrew`.

**The Windows equivalent of this problem will exist too** — a `llama-server.exe` built with
a naive `cmake --build` may dynamically link against MSVC runtime DLLs or other libraries not
guaranteed present on an arbitrary user's Windows machine. Options, roughly in order of
likely robustness:
- Static-link the C runtime (`/MT` instead of `/MD` in MSVC, or equivalent CMake flags like
  `-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded`)
- Check dependencies with `dumpbin /dependents llama-server.exe` (MSVC) or `objdump -p` (MinGW)
  — the Windows equivalent of `otool -L`. Only system DLLs (`kernel32.dll`, `user32.dll`,
  `msvcrt.dll` if truly universal, etc.) should show up; nothing pointing at a specific
  toolchain install path.
- If using MinGW-w64 instead of MSVC, static-link libgcc/libstdc++ (`-static-libgcc
  -static-libstdc++ -static`) to avoid needing MinGW's runtime DLLs on the target machine.

**Do not skip verifying this.** Build it, check its dependencies, then actually copy it to a
different location (or ideally a different machine/VM) and confirm it still runs before
trusting it's portable — this is exactly the check that was skipped on macOS initially with
the Homebrew binary, and it silently would have shipped broken to real users.

## macOS static build recipe (for reference — adapt to Windows)

```bash
git clone --depth 1 https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
cmake -B build -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=ON   # avoid auto-detecting Homebrew's OpenSSL
cmake --build build --config Release --target llama-server -j$(sysctl -n hw.ncpu)
```
Windows equivalent will need different GPU-backend flags (there's no Metal on Windows —
likely `-DGGML_CUDA=ON` for NVIDIA GPUs, or `-DGGML_VULKAN=ON` for broader GPU support, or
CPU-only if no GPU backend is set up yet — ask the user what GPU they have on the Windows
machine before picking). `-DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=ON` likely still applies (we
don't need HTTPS support — the server only listens on `127.0.0.1`).

Result goes to: `AIDesktop/resources/bin/llama-server.exe` (note `.exe` — `llamaServer.ts`'s
`binaryPath` getter already branches on `process.platform === 'win32'` for this).

## package.json state

- `"package:win": "electron-vite build && electron-builder --win"` — already fixed to build
  the renderer first (same bug macOS hit). Never remove the `electron-vite build &&` part.
- `extraResources` already configured to bundle `resources/bin/` → `Contents/Resources/bin/`
  (macOS) — for Windows this becomes `resources/bin/` in the installed app; verify the exact
  path `llamaServer.ts` expects at runtime (`process.resourcesPath` + `bin` + binary name)
  matches where NSIS actually installs it.
- `mac.target.arch` was narrowed to `["arm64"]` only (x64/Intel cross-compile was deferred) —
  irrelevant to Windows but don't be confused by it when reading the config.
- Current version: `0.1.1`. `ecoinference-releases` B2 bucket has a verified-working v0.1.1
  macOS build; there is no Windows build there yet.

## Infrastructure you'll need access to (all already set up, just need fresh local auth)

- **Firebase**: project `ecoinference-28c31`. Desktop app's web config is already hardcoded in
  `src/renderer/src/services/firebase.ts` — no setup needed there.
- **B2 + Cloudflare CDN**: fully live. Models served at
  `https://cdn.ecoinference.ai/file/ecoinference-models/models/{modelId}/{filename}`. App
  releases served at `https://releases.ecoinference.ai/file/ecoinference-releases/{filename}`.
  No credentials needed to *read* these — both buckets are public. You'd only need B2 write
  credentials if uploading a new Windows build — ask the user, don't request/handle raw B2
  keys in chat (they'll authorize a local `b2` CLI session themselves if needed).
- **llama-server binary**: needs building fresh on Windows per the static-link section above.

## Known-good model catalog (do not need to re-verify, just reference)

| ID | File | Size | Notes |
|---|---|---|---|
| `gemma4-e4b-it` | `gemma-4-E4B-it-Q4_K_M.gguf` | 4.98 GB | text-only |
| `gemma4-12b-it` | `gemma-4-12B-it-qat-UD-Q4_K_XL.gguf` | 6.72 GB | text-only (vision deferred) |

Both ids must match Remote Config's `available_models` exactly — already correct in
`src/renderer/src/models/ModelInfo.ts`, no changes needed there for a Windows build.

## Suggested first steps on Windows

1. Get the code onto the machine (resolve the git-not-committed issue first, see above).
2. Confirm `npm install` works, `npm run dev` launches and can sign in.
3. Check what GPU is in the Windows machine (NVIDIA → CUDA, otherwise consider Vulkan or
   CPU-only) — this determines the llama.cpp build flags.
4. Install build tools: Visual Studio Build Tools (or MinGW-w64), CMake, Git.
5. Build a static `llama-server.exe`, verify its dependencies with `dumpbin /dependents`.
6. Copy it to `AIDesktop/resources/bin/llama-server.exe`.
7. `npm run package:win`, then **launch the actual installed app** (not `npm run dev`) and
   manually verify sign-in → download → load → chat before trusting it.
8. Only then consider uploading to B2 as a real Windows release.
