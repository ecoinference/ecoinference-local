# Forking This Project

**Please do.** That's what it's here for.

This project doesn't accept pull requests — see [Why no PRs](#why-no-pull-requests) below. It
is maintained by one person who would rather the code be useful to you than spend evenings
reviewing patches. The MIT licence means you owe nothing: fork it, strip it, rebrand it,
ship it commercially, never mention this project again. All fine.

What follows is the practical part — everything hardcoded to *this* deployment that you'll
need to point at your own. It's a short list, and it's the whole list.

---

## What you get

Three independent native clients that run a language model on the user's own device:

- **iOS** — Swift/SwiftUI, LiteRT-LM, embedded Python 3.10
- **Android** — Kotlin/Compose, LiteRT-LM via JNI, Chaquopy Python
- **Desktop** — Electron/React, llama.cpp (plus an NPU path on Snapdragon)

Plus ~18 device and compute tools the model can call on its own, a local/cloud routing engine,
on-device Python execution, and a model download/catalog system.

You can take any one of these in isolation. They share no code — see
[docs/PRIOR_ART.md](docs/PRIOR_ART.md) for why.

## Before you start: read these two

- **[docs/ENGINEERING_NOTES.md](docs/ENGINEERING_NOTES.md)** — the native SDK constraints this
  code works around. Several things look arbitrary until you know what they're avoiding.
- **[docs/CASE_STUDIES.md](docs/CASE_STUDIES.md)** — ten bugs that were expensive to find,
  written up with the wrong turns included. If you build on this, you will hit some of them.

Half the value of this repo is in those two files. They're the part you can't get from reading
the source.

---

## Making it yours

### 1. Rename it

The code is MIT; **the name and logo are not** — see [TRADEMARK.md](TRADEMARK.md). Short
version: call your fork something else. This isn't a restriction on your freedom to fork, it's
so users can tell whose software they're actually running — which matters for an app that holds
an API key, executes code on-device, and can reach location and messaging.

Change the display name, the app icon, and the ™ markings (iOS Settings About header and
sign-in title; Android Settings About header; desktop sidebar logo, About title and auth logo).

Bundle and package identifiers live in:

- `AIiOS/AIiOS/GoogleService-Info.plist`
- `AIAndroid/app/build.gradle.kts` and `AIAndroid/app/google-services.json`

Note that Android's **namespace** (`ai.ecoinference.app`) and **applicationId**
(`ai.ecoinference.eiapp`) are different strings and both appear in build config and launch
intents. Changing one without the other produces confusing failures.

### 2. Point Firebase at your own project

Create your own Firebase project (Auth + Firestore + Storage + Remote Config + Functions),
then replace:

| File | What's in it |
|---|---|
| `AIiOS/AIiOS/GoogleService-Info.plist` | iOS Firebase config |
| `AIAndroid/app/google-services.json` | Android Firebase config |
| `AIDesktop/src/renderer/src/services/firebase.ts` | Desktop web config |
| `AIiOS/AIiOS/Services/B2Service.swift` | Function URL (project id in the host) |
| `AIAndroid/.../services/B2Service.kt` | Function URL (project id in the host) |

`firestore.rules` and `storage.rules` deploy as-is and are a reasonable starting point —
default-deny, owner-only profiles. Deploy them **before** you have real users:

```bash
firebase deploy --only firestore:rules --project <your-project>
firebase deploy --only storage --project <your-project>
```

> Storage has no `:rules` sub-target. `--only storage:rules` fails; plain `--only storage`
> works. This is undocumented and will waste your time otherwise.

Auth is email/password only, deliberately — social sign-in triggers extra App Store review.
Change it if you don't care about that.

### 3. Point model downloads at your own storage

Model weights are **not** in this repo, and the ones this deployment serves are on
infrastructure you won't have access to. You'll need somewhere to host `.litertlm` (mobile)
and `.gguf` (desktop) files.

| File | What to change |
|---|---|
| `AIDesktop/src/renderer/src/services/b2Service.ts` | CDN host and bucket name |
| `AIDesktop/package.json`, `AIDesktop/src/main/autoUpdate.ts` | Update-channel host (or remove auto-update) |
| `functions/src/index.ts` | Bucket names for presigned URLs and avatar uploads |

The simplest path is a public bucket plus a CDN and direct URLs, which is what desktop already
does. Mobile still goes through a presigned-URL Function — more moving parts, and you can drop
it in favour of the direct pattern.

[docs/INFRASTRUCTURE.md](docs/INFRASTRUCTURE.md) documents the whole setup, including a
Cloudflare/B2 gotcha that costs a day if you hit it cold: **CNAME to B2's path-based endpoint,
not the S3 virtual-hosted hostname**, because Cloudflare's free plan can't rewrite the Host
header.

You'll also need to populate Remote Config's `available_models` — schema and the known
imprecision in it are in the same file.

### 4. Platform-specific setup

**iOS** — run `AIiOS/download_frameworks.sh` to fetch the LiteRT-LM xcframeworks (~91 MB, not
tracked). Copy `AIiOS/Local.xcconfig.sample` to `Local.xcconfig` and fill in your team ID.
Embedded-Python artifacts are built by `setup.sh`. **Simulator builds will fail** — the vendored
frameworks ship device slices only.

**Android** — API 30+ required (`.litertlm` won't load the native library below that). Gradle
needs an explicit `JAVA_HOME`; Android Studio's bundled JBR works.

**Desktop** — you need a `llama-server` binary bundled per platform.
[docs/DESKTOP.md](docs/DESKTOP.md) has a verified static-build recipe, and explains why the
Homebrew binary won't do.

**Desktop on Windows ARM64** — additionally requires GenieX installed separately, for the NPU
models.

### 5. Check the licence table

`README.md` has a per-component table. The one that matters: **Gemma weights are not open
source.** They carry the Gemma Terms of Use, including a prohibited-use policy, and
redistributing them means providing those terms and a notice file. Same for Llama 3.2 on the
NPU path.

MIT covers the code you're forking. It does not cover what the app downloads and runs.

---

## Why no pull requests

Not hostility, just honesty about capacity. Reviewing patches well takes real time — reading
the change, testing it on hardware, checking cross-platform parity, thinking about the
maintenance burden it creates. Doing that badly is worse than not doing it: it leaves
contributors waiting and ships code nobody has genuinely vetted.

So this repository is published as a **finished artefact you can take**, rather than a project
you can join. Issues and PRs are closed.

**What this means for you, practically:** your fork is yours immediately. No CLA to sign, no
maintainer to convince, no waiting on review, no risk your work is rejected after you've done
it. If you want to take this somewhere, you don't need permission and you don't need me.

If you build something with it, I'd genuinely enjoy hearing about it — **info@ecoinference.ai**
— but that's an invitation, not an obligation, and it isn't a support channel.

**Security issues are the exception.** Please report those privately rather than publicly —
see [SECURITY.md](SECURITY.md). This app executes model-generated Python with network access,
so that's worth taking seriously even in a fork-only project.

## If you're picking up where this left off

[FUTURE_ENHANCEMENTS.md](FUTURE_ENHANCEMENTS.md) is an honest list of what's incomplete,
what's deferred, and what's a known limitation rather than a bug. Some highlights, so you can
judge before you invest:

- iOS has vision disabled on the larger model; Android doesn't. Not fixed.
- iOS text-only conversations can't truly reset — a native session limit, mitigated rather
  than solved.
- Profile sync and avatar upload have never been exercised end-to-end.
- Mobile downloads still use an older, costlier path than desktop.

None of these are hidden landmines — they're documented, with evidence, and in most cases the
next step is written down too.
