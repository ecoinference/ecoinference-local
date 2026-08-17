# Infrastructure

Storage, CDN, and Firebase backend shared by all three clients. Most of this lives outside the
repo — in Backblaze B2, Cloudflare, and the Firebase/GCP console — so it is invisible from the
code and easy to get wrong from first principles.

**Companions:** [ENGINEERING_NOTES.md §7](ENGINEERING_NOTES.md) for the security rules ·
[DESKTOP.md](DESKTOP.md) for the release pipeline that rides on this.

---

## Why B2 + Cloudflare

Backblaze B2 is materially cheaper than S3 and S3-compatible; Cloudflare in front gives free
egress via the Bandwidth Alliance plus real edge caching for small files. Model weights are
multi-gigabyte and downloaded repeatedly, so egress is the dominant cost.

## DNS

`ecoinference.ai` moved from Hetzner nameservers to Cloudflare
(`rosemary.ns.cloudflare.com` / `zeus.ns.cloudflare.com`) specifically to enable CDN caching.
The nameserver change was made at the registrar, which is a separate provider from Hetzner.
Org admin for both Cloudflare and GCP is `info@ecoinference.ai`.

| Record | Value | Proxy |
|---|---|---|
| A `@` | `188.245.79.0` (main site) | **DNS only** — deliberately not proxied, so the live site is unaffected |
| CNAME `cdn` | `f005.backblazeb2.com` | Proxied — models |
| CNAME `releases` | `f005.backblazeb2.com` | Proxied — app installers and update manifests |
| MX `@` | `smtp.google.com` | — |
| TXT `@` | SPF + Google site verification | — |
| TXT `_dmarc`, `google._domainkey` | DMARC policy, DKIM key | — |

### Use B2's path-based endpoint, not the S3 virtual-hosted one

This cost real time, and the failure mode is a bare 404 with no explanation.

CNAME-ing `cdn`/`releases` to the S3-compatible virtual-hosted hostname
(`{bucket}.s3.us-east-005.backblazeb2.com`) **requires the Host header to match the bucket's
vhost name** for B2 to route the request. Cloudflare's free plan has no Host Header rewriting
in Origin Rules, and proxies preserve the client's original Host (`cdn.ecoinference.ai`),
which B2 doesn't recognize.

Use B2's native path-based cluster endpoint instead: **`f005.backblazeb2.com`**, with URLs
shaped as:

```
https://{subdomain}.ecoinference.ai/file/{bucketName}/{key}
```

The bucket name is in the URL **path**, not inferred from Host, so B2's edge serves correctly
regardless of what Host header Cloudflare passes. Verified empirically — `curl` with a
deliberately mismatched `Host:` still returns 200 with correct content.

Any future CDN subdomain pointing at a B2 bucket should use this same pattern. It avoids ever
needing Cloudflare's paid Host-Header-rewrite feature.

### Large files don't edge-cache

Cloudflare's free and pro plans cap cacheable object size well below the model files' size.
Confirmed via response headers: `cf-cache-status: DYNAMIC` (never cacheable) on the multi-GB
models, versus `cf-cache-status: MISS` (cacheable) on a ~127 MB installer.

Large downloads still get the Bandwidth Alliance free-egress benefit — just not
served-from-edge speed. Manifests, installers and any future smaller model variants cache
normally.

## Buckets

| Bucket | Access | Contents |
|---|---|---|
| `ecoinference-models` | Public | `models/{modelId}/{filename}` — `.litertlm` for mobile, `.gguf` for desktop |
| `ecoinference-releases` | Public | Electron installers + `latest-mac.yml` / `latest.yml` auto-update manifests, at bucket root |
| `ecoinference-media` | Public-read | User avatars at `avatars/{uid}.jpg` |

`ecoinference-models` carries a CORS rule for the *dev* renderer's direct `fetch()` calls
(separate from the CDN path): origin `http://localhost:5173`, operations `s3_get` +
`b2_download_file_by_name` + `b2_download_file_by_id`. A packaged Electron app sends
`Origin: null` from its `file://` origin — untested against this rule.

The account-level storage cap was hit twice during the E4B/12B uploads and has since been
removed. It is an **account** cap, not key-scoped, which is not obvious from the error.

## Download paths, per client

| Client | Path | Notes |
|---|---|---|
| Desktop | Direct public CDN URL | `b2Service.ts`'s `getModelDownloadUrl()` just constructs the URL — no network call, no Function. The sign-in check is UX consistency only, not an access boundary, since the bucket is public. |
| iOS / Android | Presigned URL via Firebase Function `getModelDownloadUrl` | The older, costlier path. Still deployed and unchanged. Migrating mobile to the direct pattern is an open item. |

---

## Firebase

Project `ecoinference-28c31`, project number `333037511007`. Shared by all three clients.

- **Apps** — iOS bundle `ai.ecoinference.eiapp`, Android package `ai.ecoinference.eiapp`,
  plus the desktop web app config.
- **Auth** — email/password only. Deliberate: social sign-in triggers additional App Store
  review requirements. Usernames are `^[a-z0-9_]{4,16}$`.
- **Firestore** — `users/{uid}` (UserProfile), `usernames/{username}` (reservation docs
  enforcing uniqueness).
- **Storage** — avatars at `avatars/{uid}.jpg`, 4 MB JPEG cap, enforced in rules as well as in
  `StorageService`.
- **Remote Config** — `router_rules` and `available_models`.
- **Functions** — `getModelDownloadUrl`, `getAvatarUploadUrl`.

> Neither Firestore nor the Storage bucket actually existed until 2026-08-04 — see
> [ENGINEERING_NOTES.md §7](ENGINEERING_NOTES.md). Accounts created before that date have an
> auth user and no `users/{uid}` document.

### Remote Config: `available_models`

The live schema, which differs from the original plan (no `version` or `feedback_enabled`
fields appear in practice):

```json
[
  { "id": "gemma4-e2b-it",
    "variants": [{ "platform": "mobile", "model_size": "E2B", "filename": "gemma-4-E2B-it.litertlm" }] },
  { "id": "gemma4-e4b-it",
    "variants": [
      { "platform": "mobile",  "model_size": "E4B", "filename": "gemma-4-E4B-it.litertlm" },
      { "platform": "desktop", "model_size": "E4B", "filename": "gemma-4-E4B-it-Q4_K_M.gguf", "min_ram_gb": 6 }
    ] },
  { "id": "gemma4-12b-it", "display_name": "Gemma 4 12B",
    "variants": [{ "platform": "desktop", "model_size": "12B", "filename": "gemma-4-12B-it-qat-UD-Q4_K_XL.gguf", "min_ram_gb": 10 }] }
]
```

**Known imprecision:** desktop's `remoteConfigService.ts` reads only the top-level `id` to
build its allowlist — it does **not** filter on `variants[].platform`. So any id present in
Remote Config counts as enabled for desktop regardless of whether a desktop variant exists.
It works today by coincidence. It would break if a mobile-only model were added and expected
to stay hidden on desktop. The per-model `fileName` hardcoded in `ModelInfo.ts` is what
actually decides which file downloads.

**Model IDs must match Remote Config exactly.** A past bug had the desktop catalog using
`gemma4-4b-it` (no "e"), which silently matched nothing and left the Models screen empty with
no error at all.

---

## IAM: this project's state cannot be assumed default

While enabling CORS and public invoker access on the two Functions, **both Cloud Run services
were found to have completely empty IAM policies** — zero bindings, not even the functions'
own service account. That is strong evidence of a past incident where a raw `setIamPolicy`
call wiped bindings.

**Always use additive `gcloud … add-iam-policy-binding`.** Never a raw `setIamPolicy` on this
project.

Recovery took five steps, each blocked by the previous:

1. `roles/run.invoker` for `allUsers` on both Cloud Run services — blocked by org policy
   `constraints/iam.allowedPolicyMemberDomains` (Domain Restricted Sharing).
2. Added a **project-level override** of that constraint for `ecoinference-28c31` only
   (`listPolicy: { allValues: ALLOW }`), leaving the org-wide policy intact for other projects.
3. That still failed: `info@ecoinference.ai` holds `roles/resourcemanager.organizationAdmin`
   but **that role does not include `orgpolicy.policyAdmin`**. Granted additively at org level.
4. Retried the invoker bindings — succeeded after roughly a minute of propagation.
5. The function code then failed on `getRemoteConfig().getTemplate()`: the default Compute
   service account (`333037511007-compute@developer.gserviceaccount.com`) was also missing
   baseline permissions. Granted `roles/serviceusage.serviceUsageConsumer`, then
   `roles/cloudconfig.viewer`.

> That last role name is a trap. "Firebase Remote Config Viewer" is `roles/cloudconfig.viewer`
> — **`roles/firebaseremoteconfig.viewer` does not exist.** Find real role names with:
> ```bash
> gcloud iam roles list --format="value(name,title)" | grep -i remote
> ```

If any Function in this project starts throwing permission errors, check whether its service
account has baseline roles *at all* before debugging the code:

```bash
gcloud projects get-iam-policy ecoinference-28c31 \
  --flatten="bindings[].members" \
  --filter="bindings.members:<service-account>"
```

## Firebase CLI

```bash
firebase deploy --only firestore:rules --project ecoinference-28c31
firebase deploy --only storage --project ecoinference-28c31
```

**Storage has no `:rules` sub-target.** `--only storage:rules` fails; plain `--only storage`
is correct. Firestore does have one. This asymmetry is undocumented and wasted a round of
debugging.
