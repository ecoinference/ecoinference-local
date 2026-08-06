# Security Policy

## Reporting a vulnerability

**Please don't open a public issue.** Email **info@ecoinference.ai** with:

- what the issue is and roughly how severe you think it is
- steps to reproduce, or a proof of concept
- which client (iOS / Android / desktop) and which version
- how you'd like to be credited, if you'd like to be

We'll acknowledge receipt, keep you updated as we look into it, and let you know when a fix
ships. Please give us a reasonable window to release before disclosing publicly.

## Where the interesting attack surface is

Worth knowing if you're looking, because this app does a few things most chat apps don't:

**It executes model-generated Python on the device.** The `run_python` tool and the
`use tool` command both take code the model wrote and run it locally, with network access.
Anything that widens what that code can reach, or that lets untrusted input steer what gets
generated, is high severity.

**Tool results are attacker-influenceable.** A tool can fetch remote content, and that
content goes back into the model's context. Indirect prompt injection is a live concern.
There are existing defences — results are wrapped in nonce-delimited untrusted-content
markers and length-capped — and bypasses of those are very much in scope.

**Images are attacker-supplied.** They're decoded, resized, and passed to a native vision
encoder over a JNI/C bridge.

**Native inference runs over an FFI boundary.** Memory-safety issues in how the app drives
LiteRT-LM (iOS/Android) or llama.cpp (desktop) count, though bugs in those upstream projects
themselves should go to their maintainers.

**Credentials live on the device.** The user's own Gemini API key is stored in app settings,
and Firebase auth tokens are persisted locally. Anything that exfiltrates either, or that
leaks conversation content off-device, is in scope.

## In scope

- Remote code execution, sandbox escape, or privilege escalation
- Prompt injection that leads to tool execution the user didn't intend
- Leaking conversation content, API keys, or auth tokens off the device
- Auth bypass, or accessing another user's account or profile data
- Anything exploitable against the model-download path or its CDN

## Out of scope

- The local model producing wrong, biased, or unsafe *text* — that's a model-quality issue,
  not a vulnerability. Report it as a normal issue.
- Attacks needing physical access to an already-unlocked device
- Vulnerabilities in Gemma, LiteRT-LM, llama.cpp, or Firebase themselves — please report
  those upstream, though do tell us if this app's usage makes one materially worse
- Missing hardening that isn't exploitable on its own

## Not a bug bounty

There's no money behind this — it's a small project. Credit is offered gladly, and reports
are taken seriously regardless.
