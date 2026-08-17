# Contributing to EcoInference

Thanks for considering it. This project exists to make useful AI run on hardware people
already own — private by default, and without the energy and water cost of sending every
question to a datacenter. Contributions that push in that direction are very welcome.

## Before you start

**Open an issue first** for anything beyond a small fix. The three clients (iOS, Android,
desktop) are independent native implementations that deliberately mirror each other, so a
feature usually means coordinated work in more than one place. It's worth agreeing on the
approach before anyone writes code.

## Contributor License Agreement

We ask contributors to sign a **CLA** before their first contribution is merged. A bot will
prompt you on your first pull request; it takes about a minute and is remembered thereafter.

**What it means, plainly:**

- You keep the copyright to your work. You are not assigning it away.
- You grant the project a licence to use your contribution, including the right to
  distribute it under a different licence in future.
- You confirm you actually have the right to contribute the code — that it's yours, or
  that your employer has signed off.

**Why we ask.** Without a CLA, changing the licence later would require tracking down and
getting agreement from every past contributor, which in practice means it can never change.
The CLA keeps a door open: if the project ever needs to respond to being commercially
exploited without reciprocity, or to offer a commercial licence, it can. It is not a
prelude to closing the source — the code released under MPL 2.0 stays under MPL 2.0 forever,
and nothing can retroactively un-release it.

If your employer owns your work output, please get their sign-off before contributing.

## Licence of contributions

The project is licensed under the **Mozilla Public License 2.0** — see [LICENSE](LICENSE).
Contributions are accepted under the same terms.

MPL 2.0 is *file-level* copyleft: if you modify a file that's part of this project, those
modifications stay open. It does **not** reach into new files you write alongside it, and it
does not stop anyone building a commercial product around the code. That balance is
deliberate.

Every new source file should carry the standard MPL header:

```
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */
```

## Ground rules for code

**Match the surrounding code.** Each client follows its platform's idioms — SwiftUI
conventions on iOS, Compose on Android, React on desktop. Don't import one platform's
patterns into another.

**Cross-platform parity matters.** If you change behaviour on one mobile platform, either
port it to the other or say explicitly in the PR why it doesn't apply. Silent divergence
between iOS and Android is the single most common source of bugs here.

**Explain non-obvious code in comments.** A lot of this codebase deals with native SDK
quirks that look arbitrary without context — why a conversation is rebuilt a certain way,
why an image is only attached to one turn, why a token limit is what it is. If you worked
something out the hard way, write down what you learned so the next person doesn't have to.

**Don't put technical language in user-facing strings.** Error messages and UI copy should
read plainly to someone who doesn't know how the app works. Save the detail for comments.

**Verify before claiming it works.** Check the actual build output, and test on a real
device where the change is device-dependent. Inference behaviour in particular often can't
be trusted from a simulator.

## Project conventions

Small standing decisions that are easy to violate by accident, each with a reason.

**`default_router_rules.json` must be byte-identical on iOS and Android.** iOS carries it as a
bundle resource, Android in `assets/`. Copy it; don't let the two drift. The same prompt should
route the same way on both platforms, and a diverged rule set produces confusing,
hard-to-attribute differences.

**Send the Gemini API key as an `x-goog-api-key` header, never a URL query parameter.** Query
strings show up in logs, proxies and server-side request records. This applies to any new
Google API integration.

**Badge and brand colours must match across platforms exactly, by hex.** The cloud badge is
`#5E5CE6` — Apple's systemIndigo dark variant, which SwiftUI's `Color.indigo` resolves to. Not
Tailwind indigo (`#6366F1`); the near-miss was noticed. The local badge is `EcoColors.Green`.
When adding any element that appears on both platforms, compare hex values rather than using
rough equivalents.

**Don't re-add a HuggingFace token.** Models are served from this project's own
B2/Cloudflare infrastructure, not HuggingFace. `DownloadService` keeps an unused
`authToken: String? = null` parameter as a seam if server auth is ever needed — wire through
that rather than reintroducing user-facing token config.

**Auth stays email/password only.** Adding Google or Apple sign-in triggers additional App
Store review requirements. Usernames are `^[a-z0-9_]{4,16}$`.

**Android builds need an explicit `JAVA_HOME`.** There's no system JDK on the primary dev
machine — only Android Studio's bundled JBR:

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
```

**Tags follow `v{semver}-{feature-slug}`**, e.g. `v1.9-auth-gemini-router`. Commit, push and
tag are treated as one step when tagging a checkpoint.

**`STATUS.md` gets updated as part of finishing work**, not as a separate favour. This repo is
worked from three machines and it's the only sync mechanism between them.

## Colours and theming (Android)

Both themes are supported, and light mode is easy to break without noticing — the app was
built dark-first, and a colour that looks right in dark mode is often invisible in light.
Every one of these has happened:

- Text hardcoded to `EcoColors.NearWhite` — correct in dark, where `onSurface` *is*
  NearWhite; near-white on near-white in light.
- Labels hardcoded to `EcoColors.DimGreen` — a pale accent meant for near-black surfaces;
  about 1.5:1 on the light theme's pale-green ones.
- `EcoColors.Green` used as text or an icon tint — about 2.2:1 in light, under the 4.5:1
  WCAG AA wants for text and the 3:1 for UI components.

### The rule

**Anything drawn on a theme-coloured surface must resolve per-theme.** Reach for, in order:

| Need | Use |
|---|---|
| Body text, icons | `MaterialTheme.colorScheme.onSurface` (`.copy(alpha=…)` to mute) |
| Secondary accent (section labels, chips) | `ecoAccent` — DimGreen in dark, DeepGreen in light |
| Brand green foreground (links, stats, active icons) | `ecoBrand` — Green in dark, DeepGreen in light |
| Card / sheet background | `MaterialTheme.colorScheme.surface` |
| Page background | `MaterialTheme.colorScheme.background` |
| Dividers, borders | `MaterialTheme.colorScheme.outline` |

`ecoAccent` and `ecoBrand` live in `ui/theme/EcoTheme.kt`. Both schemes are filled in
slot-for-slot, so `colorScheme.surface` already gives `EcoColors.CardDark` in dark and
`EcoColors.LightInner` in light — you rarely need a raw palette constant.

### When a raw `EcoColors.*` constant *is* correct

Two cases, and they're worth understanding rather than pattern-matching:

**Fills.** `EcoColors.Green` as a button `containerColor`, slider thumb/track, switch track,
or focused border is fine. Those pair it with their own content colour, so there's no
contrast problem — only *foreground* uses are.

**Content on a surface that's dark in both themes.** The user chat bubble is
`EcoColors.Green` in both themes, so its `EcoColors.DarkInner` text is correct and must
stay. Swapping that for a theme-aware colour would produce dark-on-dark in light mode.

This is why a blanket find-and-replace is the wrong instinct here. **Background and
foreground have to move together** — converting a card to a themed surface without
converting its text turns "looks slightly off" into "unreadable", and vice versa.

### Check both themes before you push

```
adb shell cmd uimode night no    # light
adb shell cmd uimode night yes   # dark
adb shell cmd uimode night auto  # restore
```

Screenshot both. Dark mode is the one that already worked, so it's the one a careless
theming change silently regresses.

## Testing

Both mobile apps have a **Settings → Developer → Inference Tests** screen that runs the
smoke suite (inference, Python, cloud routing, vision) on-device. Run it before submitting
anything that touches inference, tools, or routing.

Note that running many end-to-end tests in one pass can produce failures late in the run
for reasons unrelated to your change — a known native session limitation, surfaced in the
UI. Failures partway through a long run aren't automatically a regression.

Unit tests live in `AIiOS/AIiOSTests/` and `AIAndroid/app/src/test/kotlin/`.

## Security

**Please don't open a public issue for a security problem.** See [SECURITY.md](SECURITY.md).

This is worth taking seriously here: the app executes model-generated Python on-device and
gives tools network access. Anything touching `run_python`, tool dispatch, or the untrusted
content wrappers deserves extra scrutiny.

## Things that won't be merged

- Model weights, or anything else multi-gigabyte. Models are fetched at runtime.
- Credentials, API keys, or `.env` files of any kind — including in test fixtures.
- Vendored binaries, unless there's a discussion first about redistribution rights.
- Telemetry or analytics that report user prompts or conversation content anywhere.
