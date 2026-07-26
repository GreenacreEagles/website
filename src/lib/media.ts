export type R2Bucket = {
  put(key: string, value: ArrayBuffer | ArrayBufferView | Blob | ReadableStream, options?: unknown): Promise<unknown>;
  delete(key: string | string[]): Promise<void>;
};

type RuntimeContext = { locals?: any };

export const getRuntimeEnv = (context: RuntimeContext, key: string) =>
  context.locals?.runtime?.env?.[key] ?? import.meta.env[key];

export const getPublicMediaUrl = (objectKey: string | null | undefined, context?: RuntimeContext) => {
  if (!objectKey) return null;
  const base = String(getRuntimeEnv(context ?? {}, "PUBLIC_MEDIA_BASE_URL") ?? "").trim().replace(/\/+$/, "");
  return base ? `${base}/${objectKey.split("/").map(encodeURIComponent).join("/")}` : null;
};

export const getPublicMediaBucket = (context: RuntimeContext): R2Bucket | null => {
  const env = context.locals?.runtime?.env ?? {};
  const bindingName = String(getRuntimeEnv(context, "R2_PUBLIC_BUCKET_BINDING") ?? "PUBLIC_MEDIA_BUCKET");
  const bucket = env[bindingName] ?? env.PUBLIC_MEDIA_BUCKET;
  return bucket && typeof (bucket as R2Bucket).put === "function" ? (bucket as R2Bucket) : null;
};

export const PLAYER_PHOTO_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/avif"]);
export const playerPhotoMaxBytes = (context: RuntimeContext) =>
  Number(getRuntimeEnv(context, "PUBLIC_MEDIA_MAX_FILE_SIZE") ?? 10_485_760);

export const playerPhotoObjectKey = (playerId: string, mimeType: string) => {
  const extension = mimeType === "image/jpeg" ? "jpg" : mimeType.split("/")[1];
  return `players/${playerId}/profile/${crypto.randomUUID()}.${extension}`;
};

export const socialPostImageObjectKey = (postId: string, mimeType: string) => {
  const extension = mimeType === "image/jpeg" ? "jpg" : mimeType.split("/")[1];
  return `social-posts/${postId}/${crypto.randomUUID()}.${extension}`;
};
export const sponsorLogoObjectKey = (sponsorId: string, mimeType: string) => {
  const extension = mimeType === "image/jpeg" ? "jpg" : mimeType.split("/")[1];
  return `sponsors/${sponsorId}/${crypto.randomUUID()}.${extension}`;
};
export const eventImageObjectKey=(eventId:string,mimeType:string)=>{
  const extension=mimeType==="image/jpeg"?"jpg":mimeType.split("/")[1];
  return `events/${eventId}/hero/${crypto.randomUUID()}.${extension}`;
};
