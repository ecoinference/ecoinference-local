# Code Conventions

Standing decisions in this codebase, and the reasoning behind them. Originally written as
contributor guidance; kept here because **a forker needs them more than a contributor would** —
these are the rules that keep the three clients coherent, and each one is here because
violating it already caused a bug.

Nothing here is enforced. Ignore any of it in your own fork. But read the theming section
before you touch colors, because that one is genuinely easy to get wrong.

**Companions:** [ENGINEERING_NOTES.md](ENGINEERING_NOTES.md) for the SDK constraints ·
[DEVICE_TESTING.md](DEVICE_TESTING.md) for verification mechanics ·
[../FORKING.md](../FORKING.md) to get started.

---

## Ground rules for code

**Match the surrounding code.** Each client follows its platform's idioms — SwiftUI
conventions on iOS, Compose on Android, React on desktop. Don't import one platform's
patterns into another.

**Cross-platform parity matters.** If you change behavior on one mobile platform, port it to
the other or record why it doesn't apply. Silent divergence between iOS and Android is the
single most common source of bugs here — most of [CASE_STUDIES.md](CASE_STUDIES.md) is one
platform having a fix the other didn't.

Scope: this governs **iOS ↔ Android within this repository only**. It never extended to
EcoInference Remote, a separate product with a different premise — see
[RELATED_PROJECTS.md](RELATED_PROJECTS.md).

**Explain non-obvious code in comments.** A lot of this codebase deals with native SDK
quirks that look arbitrary without context — why a conversation is rebuilt a certain way,
why an image is only attached to one turn, why a token limit is what it is. If you worked
something out the hard way, write down what you learned so the next person doesn't have to.

**Don't put technical language in user-facing strings.** Error messages and UI copy should
read plainly to someone who doesn't know how the app works. Save the detail for comments.

**Verify before claiming it works.** Grep the build tool's own literal marker —
`BUILD SUCCESSFUL` / `BUILD SUCCEEDED` — rather than trusting an exit code or a "done"
summary. And note that a Gradle run reporting `BUILD SUCCESSFUL in 1s` right after you edited
a file compiled nothing; it found everything up to date. Both traps have already produced a
"fixed" report against a stale artifact. Details in
[DEVICE_TESTING.md](DEVICE_TESTING.md#verifying-a-build-actually-built).

Test on a real device where the change is device-dependent. Inference behavior in particular
can't be trusted from a simulator — and the simulator has a coordinate-scale trap of its own.

**When something that worked breaks, isolate the change before theorising.** Ask what
actually differs between last-known-good and now, revert that one thing, and rebuild to
confirm or rule it out — one candidate at a time, since that also tells you which one was
responsible. The instinct to reach for a plausible, larger explanation (an SDK upgrade, a
toolchain change, a config rewrite) is usually wrong and always more expensive. There are
several worked examples in [CASE_STUDIES.md](CASE_STUDIES.md).

## Project conventions

Small standing decisions that are easy to violate by accident, each with a reason.

**`default_router_rules.json` must be byte-identical on iOS and Android.** iOS carries it as a
bundle resource, Android in `assets/`. Copy it; don't let the two drift. The same prompt should
route the same way on both platforms, and a diverged rule set produces confusing,
hard-to-attribute differences.

**Send the Gemini API key as an `x-goog-api-key` header, never a URL query parameter.** Query
strings show up in logs, proxies and server-side request records. This applies to any new
Google API integration.

**Badge and brand colors must match across platforms exactly, by hex.** The cloud badge is
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

**`STATUS.md` gets updated as part of finishing work.** This repo is worked from three
machines and it's the only sync mechanism between them. In a fork you may not need it — but
you'll want *something* playing that role if you work across machines.

## Colors and theming (Android)

Both themes are supported, and light mode is easy to break without noticing — the app was
built dark-first, and a color that looks right in dark mode is often invisible in light.
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
or focused border is fine. Those pair it with their own content color, so there's no
contrast problem — only *foreground* uses are.

**Content on a surface that's dark in both themes.** The user chat bubble is
`EcoColors.Green` in both themes, so its `EcoColors.DarkInner` text is correct and must
stay. Swapping that for a theme-aware color would produce dark-on-dark in light mode.

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
smoke suite (inference, Python, cloud routing, vision) on-device. Worth running after anything
that touches inference, tools, or routing.

Two caveats, both learned the hard way:

- **A green run doesn't prove the feature works.** The test screens and the production chat
  path build their inputs separately, and they have drifted before — see
  [CASE_STUDIES.md §2](CASE_STUDIES.md#2-a-passing-test-screen-hiding-a-broken-feature--use-tool).
- **Failures late in a long run may not be your change.** Running many end-to-end tests in one
  pass hits a known native session limit on iOS. The UI says so.

Unit tests live in `AIiOS/AIiOSTests/` and `AIAndroid/app/src/test/kotlin/`.

## Security

The app executes model-generated Python on-device and gives tools network access. Anything
touching `run_python`, tool dispatch, or the untrusted-content wrappers deserves extra
scrutiny — in a fork as much as here. See [../SECURITY.md](../SECURITY.md).

## Things that don't belong in the repo

Kept as guidance for your own fork, since all four have caused real problems somewhere:

- Model weights, or anything else multi-gigabyte. Models are fetched at runtime.
- Credentials, API keys, or `.env` files of any kind — including in test fixtures. This repo
  leaked a token exactly this way once; see [../FUTURE_ENHANCEMENTS.md](../FUTURE_ENHANCEMENTS.md).
- Vendored binaries, unless you've checked the redistribution rights.
- Telemetry that reports user prompts or conversation content anywhere.
