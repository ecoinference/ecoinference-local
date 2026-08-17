# Licensing and Trademark — the Reasoning

`LICENSE`, `NOTICE`, `TRADEMARK.md` and `CONTRIBUTING.md` state the decisions. This file
records *why*, including the options that were ruled out, so they don't get re-litigated from
scratch.

Not legal advice. Written from research done 2026-07-30 through 2026-08-04.

---

## The constraint that eliminates most of the field

**The GPL family is unusable for an App Store app.** GPL §6 forbids imposing further
restrictions on recipients; Apple's App Store terms impose exactly that — device limits, DRM,
redistribution rules. They are incompatible. This is why **VLC was pulled from the App Store in
2011**.

So GPLv3 and AGPLv3 are off the table for anything intended to ship on iOS, regardless of how
much copyleft is wanted. Rule this out early rather than evaluating it.

MPL 2.0 has no such conflict — Firefox iOS ships under it. Neither do MIT or Apache 2.0.

## The trade-off that can't be avoided

**You cannot block commercial free-riding and remain open source.** OSI criterion 6 ("No
Discrimination Against Fields of Endeavor") explicitly forbids restricting commercial use. Any
licence that genuinely stops "a company commercializes this without contributing" — BSL, FSL,
SSPL — is *source-available*, not open source. Those repel a slice of contributors and can't
honestly be called open source.

Name this trade-off rather than searching for a licence that does both. There isn't one.

## The ladder

| Want | Use |
|---|---|
| Maximum adoption, no strings | MIT |
| Same, plus patent grant and trademark reservation | Apache 2.0 |
| Modifications to *your* files stay open | **MPL 2.0** — file-level copyleft, App Store safe |
| Actually block commercial competitors | FSL / BSL — *not* open source |

**MPL 2.0 was chosen.** File-level copyleft keeps changes to this project's files open without
blocking anyone from building commercial work alongside them, and it carries no App Store
conflict.

## Two things that matter more than the licence

**Trademark, not licence, protects a consumer app's identity.** Under any licence a forker can
take the code but cannot use the name, icon, or store listing. That is usually the actual fear,
and it is solved entirely outside `LICENSE`. Apache 2.0 §6 and MPL §3.3 both explicitly
withhold trademark rights.

**A CLA is the only thing that preserves the ability to change your mind.** Without one,
relicensing requires agreement from every past contributor — in practice, never. With one, the
project can tighten future versions or dual-license if abuse actually materializes.
Already-released code stays under its original licence forever either way.

This is the honest answer to "I want some control without discouraging developers": start
permissive, keep the legal option to respond. See `CONTRIBUTING.md` for how this is put to
contributors.

## Model weights are a separate layer

The model licence travels with the model regardless of the code's licence. Gemma weights carry
the **Gemma Terms of Use**, which includes a prohibited-use policy and is **not** OSI open
source.

So "the code is MPL" never means "the product is freely usable for anything." The README states
this plainly, with a per-component table, so nobody is surprised.

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
