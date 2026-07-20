import { initializeApp } from "firebase-admin/app";
import { getRemoteConfig } from "firebase-admin/remote-config";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { S3Client, PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

initializeApp();

const modelsKeyId  = defineSecret("B2_MODELS_KEY_ID");
const modelsAppKey = defineSecret("B2_MODELS_APP_KEY");
const mediaKeyId   = defineSecret("B2_MEDIA_KEY_ID");
const mediaAppKey  = defineSecret("B2_MEDIA_APP_KEY");

const B2_ENDPOINT   = "https://s3.us-east-005.backblazeb2.com";
const MODELS_BUCKET = "ecoinference-models";
const MEDIA_BUCKET  = "ecoinference-media";

function makeS3Client(keyId: string, appKey: string): S3Client {
  return new S3Client({
    endpoint: B2_ENDPOINT,
    region: "us-east-005",
    credentials: { accessKeyId: keyId, secretAccessKey: appKey },
    forcePathStyle: true,
  });
}

// ── getModelDownloadUrl ───────────────────────────────────────────────────────
// Returns a presigned GET URL for a model variant.
// TTL: 1 hour for mobile, 4 hours for desktop (large GGUF files on slow connections).

export const getModelDownloadUrl = onCall(
  { secrets: [modelsKeyId, modelsAppKey], cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");

    const { modelId, filename, platform } = request.data as {
      modelId: string;
      filename: string;
      platform: "mobile" | "desktop";
    };

    if (!modelId || !filename || !platform) {
      throw new HttpsError("invalid-argument", "modelId, filename, and platform are required.");
    }

    // Validate modelId + filename against Remote Config allowlist
    const rc       = getRemoteConfig();
    const template = await rc.getTemplate();
    const param    = template.parameters["available_models"];
    const rawValue = param?.defaultValue && "value" in param.defaultValue
      ? param.defaultValue.value
      : "[]";

    const models = JSON.parse(rawValue) as Array<{
      id: string;
      variants: Array<{ filename: string }>;
    }>;

    const model   = models.find((m) => m.id === modelId);
    const variant = model?.variants.find((v) => v.filename === filename);

    if (!model || !variant) {
      throw new HttpsError("not-found", `Model ${modelId} / ${filename} not in allowlist.`);
    }

    const key    = `models/${modelId}/${filename}`;
    const ttlSec = platform === "desktop" ? 4 * 3600 : 3600;
    const s3     = makeS3Client(modelsKeyId.value(), modelsAppKey.value());
    const url    = await getSignedUrl(
      s3,
      new GetObjectCommand({ Bucket: MODELS_BUCKET, Key: key }),
      { expiresIn: ttlSec }
    );

    return { url };
  }
);

// ── getAvatarUploadUrl ────────────────────────────────────────────────────────
// Returns a presigned PUT URL scoped to the calling user's avatar key.
// TTL: 15 minutes.

export const getAvatarUploadUrl = onCall(
  { secrets: [mediaKeyId, mediaAppKey], cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");

    const uid         = request.auth.uid;
    const contentType = (request.data?.contentType as string) ?? "image/jpeg";
    const key         = `avatars/${uid}.jpg`;
    const s3          = makeS3Client(mediaKeyId.value(), mediaAppKey.value());

    const url = await getSignedUrl(
      s3,
      new PutObjectCommand({ Bucket: MEDIA_BUCKET, Key: key, ContentType: contentType }),
      { expiresIn: 900 }
    );

    return { url, key };
  }
);
