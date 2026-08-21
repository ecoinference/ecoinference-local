# Licensing and Trademark — the Reasoning

`LICENSE`, `NOTICE`, `TRADEMARK.md` and `FORKING.md` state the decisions. This file records
*why*, including the options ruled out, so they don't get re-litigated from scratch.

Not legal advice. Research done 2026-07-30 through 2026-08-04; the decision changed
2026-08-20.

---

## The decision: MIT, no pull requests

**Goal: maximize the chance someone actually uses and forks this.** Not to capture value from
forks, not to build a contributor community, not to retain leverage. That single goal settles
most of what follows.

**MIT**, because it is the most recognized permissive licence, imposes exactly one condition
(keep the copyright notice), and requires nothing of the maintainer. A forker owes nothing and
needs no permission.

**No pull requests**, because reviewing patches well takes real time — reading the change,
testing on hardware, checking cross-platform parity, weighing the maintenance burden. Doing it
badly is worse than not doing it. The repo is published as a finished artefact to take, not a
project to join.

### The consequence worth understanding: no CLA is needed

This was previously the plan's biggest piece of unfinished legal work, and it evaporated.

A CLA exists to preserve the ability to relicense later. Without one, relicensing needs
agreement from every past contributor — in practice, never. **But with no pull requests, no
third-party copyright ever enters the codebase.** The copyright holder retains 100% ownership
and can relicense at will, permanently, with no paperwork from anyone.

So "no PRs" bought the exact thing the CLA was for, and removed a legal review, a bot, and a
piece of friction in front of every would-be forker.

### What was given up, honestly

**Reciprocity.** A company can take this, build a product on it, and contribute nothing back.
Under MIT that is entirely legitimate and there is no recourse. That was accepted deliberately
— see the trade-off below, which shows the alternative was never really available.

**Contributions.** Good patches will not land. Someone who fixes a real bug in their fork has
no path to push it here. That is the cost of the capacity decision, and it is a real cost.

---

## Why not the alternatives

### The GPL family was never available

**GPL is unusable for an App Store app.** GPL §6 forbids imposing further restrictions on
recipients; Apple's App Store terms impose exactly that — device limits, DRM, redistribution
rules. They are incompatible, which is why **VLC was pulled from the App Store in 2011**.

So GPLv3 and AGPLv3 are off the table for anything intended to ship on iOS, regardless of how
much copyleft is wanted. Rule this out early rather than evaluating it.

### You cannot block commercial free-riding and stay open source

OSI criterion 6 ("No Discrimination Against Fields of Endeavor") explicitly forbids restricting
commercial use. Any licence that genuinely stops "a company commercializes this without
contributing" — BSL, FSL, SSPL — is *source-available*, not open source. Those repel a slice of
adopters, which is the opposite of the goal here.

There is no licence that is both open source and blocks free-riding. Name the trade-off rather
than hunting for one.

### MPL 2.0 — the previous choice

The project was MPL 2.0 from 2026-07-30 to 2026-08-20. MPL is file-level copyleft: changes to
*these* files stay open, while new files alongside them can be proprietary. App Store safe
(Firefox iOS ships under it).

It was a reasonable choice for a project expecting contributors. Once the decision was made to
accept none, MPL's copyleft only bought a reciprocity obligation nobody would enforce, at the
cost of a licence forkers have to think about. MIT asks less and gets read more.

No public release ever happened under MPL, so the change is clean — no version of this code was
ever distributed under the old terms.

### Apache 2.0 — considered, not chosen

Also permissive, and arguably the better *engineering* choice: an express patent grant with a
retaliation clause, and §6 explicitly reserving trademarks. It also matches LiteRT-LM and Qwen,
both Apache 2.0.

Passed over because it adds conditions (preserve NOTICE, note changed files) that a fork-only
project will never enforce, and because MIT is shorter and more immediately understood. When
the maintainer will not police the terms, extra clauses are theatre.

### 0BSD — considered, not chosen

Genuinely the most permissive — drops even attribution. Passed over as exotic enough that some
corporate legal teams flag it, which would cost more adoption than the attribution requirement
does.

### The ladder, for reference

| Want | Use |
|---|---|
| Maximum adoption, no strings | **MIT** ← chosen |
| Same, plus patent grant and trademark reservation | Apache 2.0 |
| Modifications to *your* files stay open | MPL 2.0 — file-level copyleft, App Store safe |
| Actually block commercial competitors | FSL / BSL — *not* open source |
| No attribution at all | 0BSD / Unlicense / CC0 |

---

## Trademark is what actually protects the name

**Trademark, not licence, protects a consumer app's identity.** Under any licence a forker can
take the code but cannot use the name, icon, or store listing. That is usually the actual fear,
and it is solved entirely outside `LICENSE`.

This matters *more* under MIT than it did under MPL, because MIT says nothing about trademarks
at all. Trademark rights exist independently of any copyright licence, and `TRADEMARK.md` states
the position explicitly — so the practical protection is unchanged. But the licence is no
longer carrying any of it.

The ask on a forker is exactly one thing: **rename it.** Not a restriction on forking; it's
what makes a fork honest, for an app that holds an API key, executes code on-device, and can
reach location and messaging.

## Model weights are a separate layer

The model licence travels with the model regardless of the code's licence. Gemma weights carry
the **Gemma Terms of Use**, which includes a prohibited-use policy and is **not** OSI open
source.

So "the code is MIT" never means "the product is freely usable for anything." The README states
this plainly, with a per-component table. **This is the single most important thing for a
forker to actually read** — it is far more restrictive than the code licence.

---

## Third-party components — all three questions resolved

Each had been recorded as a scary-sounding blocker. None was one. The pattern worth noting:
**all three dissolved on actually reading the terms**, and two of them turned out not to be
redistribution questions at all.

**LiteRT-LM is Apache 2.0.** Confirmed from the upstream LICENSE and the published Android POM.
Binary redistribution is permitted. The real gap was attribution, now in `NOTICE`. Upstream
ships no NOTICE file of its own, so §4(d) doesn't apply.

**QAIRT/Qualcomm isn't redistributed at all.** The Windows ARM64 build ships exactly one binary
(`llama-server.exe`) and shells out to a user-installed `geniex` on `PATH` — the way a tool
might shell out to `ffmpeg`. GenieX then fetches the QAIRT runtime from Qualcomm's own
infrastructure. No redistribution happens here, so QAIRT's terms don't bind this project.

**That changes the moment anyone bundles GenieX or QAIRT into the installer.** Tempting, since
it removes a manual setup step. Confirm rights with Qualcomm first — the terms sit behind a
developer-portal click-through with no published text and could rule the approach out entirely.

**Chaquopy is MIT** — open source since 12.0.1, no licence key needed. It surfaced a wider gap
though: both apps embed CPython plus ~10 Python packages (29 resolved distributions on iOS)
that `NOTICE` didn't mention. All permissive, and the attribution requirement turns out to be
satisfied already — **every bundled distribution ships its own licence in its `.dist-info/`
directory**. `NOTICE` records that fact rather than duplicating ~30 licence texts that would go
stale on every rebuild. If anyone later proposes pasting them all in, that's the reason not to.

---

## Trademark strategy

### The chosen path: free, for now

No paid attorney, no filing yet. Concretely:

**1. Consistent ™ use — done** (`dc2ef29`). Added to the prominent brand display on each
surface: iOS Settings About header and sign-in title, Android Settings About header, desktop
sidebar logo, About title and auth logo.

Deliberately **not** marked, and shouldn't be later:

- Android `strings.xml` `app_name` and Electron `productName` — these drive the launcher label,
  installer name and on-disk paths; a special character risks packaging breakage.
- iOS `Info.plist` permission prompts — reads badly mid-sentence.
- Bundle IDs, package names, URLs.
- Repeat mentions within a single screen — convention is first-or-most-prominent use only.

**Why this matters legally:** common-law ™ rights already exist from real use in commerce.
Registration upgrades them, it doesn't create them. Consistent marking strengthens those rights
and builds the evidentiary record for any later filing. It's free, and it's most of the
practical protection for a small app, since Apple's and Google's store dispute processes act on
common-law rights too.

**2. UIC Law School trademark clinic** is the free registration route when ready —
`law-tmclinicinfo@uic.edu`.

The USPTO Law School Clinic Certification Program has 70+ accredited clinics that file real
trademark applications pro bono (supervised students); you pay only government fees. Badly
underused, and a strong fit for a mission-driven project.

**Critically, most clinics are geographically restricted** — checked 2026-07-30: Northwestern
is Illinois only, DePaul is Chicago metro, Missouri is Missouri only, Nebraska is Nebraska only.
So the nearest law school usually *isn't* the answer. **UIC is the exception: service area "All
United States."** Acceptance is still at the clinic's discretion.

**3. The lawyer friend** is best used for a gut check and a *referral*. Trademark prosecution is
a specialty; a good referral from them may beat them doing it.

### The unresolved risk: descriptiveness

Assessed as **more likely than not to draw a §2(e)(1) refusal**. "Inference" is the literal
technical term for what the app does, and "Eco" names the benefit the project markets.

The counter-argument is genuinely arguable: ordinary consumers of a phone chat app don't say
"inference," so it takes a mental step for the actual relevant audience.

Fallbacks if refused: the Supplemental Register, or §2(f) acquired distinctiveness after five
years of continuous use.

**The strategic point worth remembering: if descriptiveness proves a real problem, the cheapest
fix is a stronger name, not a better lawyer.** A coined mark registers more easily and protects
more broadly. The project is still early enough to rename.

### Clearance search — treat as weak evidence

A search was run and found no obvious blocker, **but the search itself was weak**: USPTO's API
404'd and both Trademarkia and Justia blocked automated access, so it was indexed-search-only,
not the authoritative register.

Treat the result as "no obvious blocker," **not** "clear to file."

Worth a second look: `ECOINVENT` (registered, environmental-science databases) shares the prefix
and an adjacent field. "Eco-" is a crowded prefix generally — ECOINT (cancelled), ECOPLAY,
ECOCENTER. Crowding narrows everyone's scope in both directions.

### Not done

No clinic contacted, no application filed. The ™ work covered **this repo only** — the
`ecoinference.ai` site is a separate project and is likely the highest-visibility public
surface; App Store and Play Store listing *descriptions* also want ™ (though not the app-name
field). Neither has been done.
