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
