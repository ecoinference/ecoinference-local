import { firebaseAuth } from './firebase'

const CDN_BASE = 'https://cdn.ecoinference.ai/file/ecoinference-models'

export class B2Error extends Error {
  constructor(message: string) { super(message) }
}

// Model files are served publicly through the Cloudflare-fronted CDN (see
// project notes on the B2 + Cloudflare setup) — no presigned URL needed.
// The sign-in check is kept for UX consistency (only signed-in users trigger
// multi-GB downloads through the app), not as an access-control boundary.
export async function getModelDownloadUrl(modelId: string, filename: string): Promise<string> {
  const user = firebaseAuth().currentUser
  if (!user) throw new B2Error('You must be signed in to download models.')

  return `${CDN_BASE}/models/${modelId}/${filename}`
}
