# Proposal: Broader `mentionsSensitiveDomain` Exemplars

**Status:** proposal, 2026-10-20. **Not in the shipped config.** `default_router_exemplars.json`
and Remote Config `router_exemplars` are unchanged; nothing here has been embedded or measured.

**Why:** decision D3 ([ROUTING_THREE_TIER_DECISIONS.md](ROUTING_THREE_TIER_DECISIONS.md))
changes what this fact means. It was "needs a better model for professional advice"; under D3
it is "private — keep it on the user's hardware". The 14 bundled exemplars all *ask for
advice* (medication, diagnosis, lawsuits, taxes, retirement). Prompts that *disclose* a private
situation — *"I have liver cancer, should I tell my employer?"* — aren't represented.

---

## 1. The cost asymmetry flips under D3

| Mistake | Before D3 (sensitive → cloud) | Under D3 (sensitive → user-owned hardware) |
|---|---|---|
| False positive (not sensitive, flagged) | Prompt sent to cloud needlessly — privacy and energy harm | Stays local; user sees an unneeded notice |
| False negative (sensitive, missed) | Stays local — fine | **Private prompt can go to cloud** if another rule escalates it |

So the fact should now lean toward **recall**: a miss can leak, a false alarm costs a notice.
The limit is notice fatigue — if the notice shows on ordinary questions, people learn to tap
past it. That is the reason to keep near-miss negatives in the corpus (§4), not to keep the
threshold high.

---

## 2. Proposed exemplars

Keep all 14 existing exemplars, and add the following. Same style as the bundled set: short,
first-person, prompt-shaped. **None duplicates a corpus prompt or the D3 worked example** — the
liver-cancer prompt is a test case and must stay out of the exemplars, or it can't measure
anything.

### Health (physical, mental, reproductive)

- just got diagnosed with a serious illness and I don't know who to tell
- my test results came back positive, what does that mean for me
- I've been struggling with depression and haven't told anyone
- I'm pregnant and haven't told my partner or family yet
- my doctor found something on my scan and I'm scared
- I'm in recovery from addiction and worried people will find out

### Employment

- should I tell my boss about my medical condition
- my employer is treating me differently since I disclosed my disability
- I think I was fired illegally after I reported a problem
- how do I report harassment by my supervisor without retaliation
- I'm interviewing for other jobs and my manager doesn't know

### Immigration

- my visa expired and I'm still living here
- I'm undocumented, can I still see a doctor or go to the police
- will applying for public benefits hurt my green card application
- I have an asylum hearing coming up and I'm afraid of what happens

### Debt and money trouble

- I'm behind on rent and can't pay my credit cards
- debt collectors keep calling me at work
- should I file for bankruptcy, I can't keep up with payments
- I owe back taxes I can't afford to pay
- my car is about to be repossessed

### Legal trouble

- I was arrested last night, what should I do now
- I got a DUI, am I going to lose my license
- I was just served with court papers
- the police want to question me, do I have to talk to them
- my ex is threatening to take the kids away from me

### Non-English (the bundled set already carries es / fr / de)

- mi visa venció y sigo viviendo aquí
- tengo deudas que no puedo pagar y me llaman los cobradores
- j'ai été arrêté hier soir, que dois-je faire
- je suis enceinte et je ne l'ai dit à personne
- ich habe Schulden und kann die Miete nicht mehr zahlen
- mein Arbeitgeber behandelt mich anders seit meiner Diagnose

That is 31 new exemplars, 45 in the category. Scoring is max-cosine, so each one widens what
matches; that is the intent here, and §4 is the check on it.

---

## 3. Deliberately left out

- **Crisis, self-harm, abuse and domestic violence** — decided 2026-10-20 (D9): these get their
  own fact, `mentionsCrisis`, and a resource card instead of the D3 notice. They do not belong
  in `mentionsSensitiveDomain`; its exemplars should be drafted separately.
- **Identity categories** (sexual orientation, gender identity, religion, political views when
  disclosed personally). Plausibly private under D3's meaning, not in the five areas asked for.
  Still needs a decision.

---

## 4. How to measure before shipping

Same pipeline that produced the §4 GO in [ROUTING.md](ROUTING.md): normalize whitespace,
embed with Needle, center by the config's fixed mean, max-cosine against the category,
strict `>` threshold.

1. **Re-sweep the `mentionsSensitiveDomain` threshold** (currently 0.200) with the new set, on
   the holdout split [ROUTING.md](ROUTING.md) §2 still owes — not on the full corpus.
2. **Regressions to watch:** `sd-02` ("Can I sue for some peace and quiet?") and `sd-04`
   ("Should I take my dog to the vet about his limp?") must stay unflagged.
3. **Add near-miss negatives to the corpus**, so notice fatigue is measured, not guessed.
   Candidates:
   - "my character in the novel was just diagnosed with cancer"
   - "explain how the US immigration system works"
   - "what's the history of bankruptcy law"
   - "how does a credit score get calculated"
   - "write a courtroom scene where the defendant is arrested"
   - "my boss's jokes are so bad lol"
4. **Add positives the exemplars don't contain**, including the D3 worked example, so recall is
   measured on prompts the config has never seen.
5. **Corpus schema first:** these cases need the three-tier fields (`expect_min_tier`, expected
   notice). Under today's schema every sensitive case is labeled `cloud`, which D3 reverses.
6. **Centering mean:** the shipped mean was derived from the original measurement batch.
   Check whether it needs recomputing with 31 more exemplar vectors before trusting any
   threshold.

Shipping is then a version bump of `router_exemplars` in Remote Config plus the bundled
default, byte-identical on iOS and Android — no app release.
