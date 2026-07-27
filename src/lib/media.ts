export type R2Bucket = {
  put(key: string, value: ArrayBuffer | ArrayBufferView | Blob | ReadableStream, options?: unknown): Promise<unknown>;
  delete(key: string | string[]): Promise<void>;
};

export type UploadedFile = {
  size: number;
  type: string;
  arrayBuffer(): Promise<ArrayBuffer>;
};

export const getUploadedFile = (value: FormDataEntryValue | null): UploadedFile | null => {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Partial<UploadedFile>;
  if (typeof candidate.size !== "number" || candidate.size <= 0) return null;
  if (typeof candidate.type !== "string" || typeof candidate.arrayBuffer !== "function") return null;
  return candidate as UploadedFile;
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

export const getPrivateMediaBucket = (context: RuntimeContext): R2Bucket | null => {
  const env = context.locals?.runtime?.env ?? {};
  const bindingName = String(getRuntimeEnv(context, "R2_PRIVATE_BUCKET_BINDING") ?? "PRIVATE_MEDIA_BUCKET");
  const bucket = env[bindingName] ?? env.PRIVATE_MEDIA_BUCKET;
  return bucket && typeof (bucket as R2Bucket).put === "function" ? (bucket as R2Bucket) : null;
};

export const PLAYER_PHOTO_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/avif"]);
export const playerPhotoMaxBytes = (context: RuntimeContext) =>
  Number(getRuntimeEnv(context, "PUBLIC_MEDIA_MAX_FILE_SIZE") ?? 10_485_760);

const readUint24LE = (bytes: Uint8Array, offset: number) =>
  bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);

const imageDimensions = (bytes: Uint8Array, mimeType: string) => {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (mimeType === "image/png" && bytes.length >= 24) {
    return { width: view.getUint32(16), height: view.getUint32(20) };
  }
  if (mimeType === "image/jpeg") {
    let offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] !== 0xff) break;
      const marker = bytes[offset + 1];
      const length = view.getUint16(offset + 2);
      if (marker >= 0xc0 && marker <= 0xc3) {
        return { height: view.getUint16(offset + 5), width: view.getUint16(offset + 7) };
      }
      if (length < 2) break;
      offset += length + 2;
    }
  }
  if (mimeType === "image/webp" && bytes.length >= 30) {
    const chunk = String.fromCharCode(...bytes.slice(12, 16));
    if (chunk === "VP8X") {
      return { width: readUint24LE(bytes, 24) + 1, height: readUint24LE(bytes, 27) + 1 };
    }
  }
  if (mimeType === "image/avif") {
    for (let offset = 4; offset + 16 <= bytes.length; offset += 1) {
      if (String.fromCharCode(...bytes.slice(offset, offset + 4)) === "ispe") {
        return { width: view.getUint32(offset + 8), height: view.getUint32(offset + 12) };
      }
    }
  }
  return null;
};

const matchesMagicBytes = (bytes: Uint8Array, mimeType: string) => {
  if (mimeType === "image/jpeg") return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (mimeType === "image/png") {
    return [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((value, index) => bytes[index] === value);
  }
  if (mimeType === "image/webp") {
    return String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" && String.fromCharCode(...bytes.slice(8, 12)) === "WEBP";
  }
  if (mimeType === "image/avif") {
    const brand = String.fromCharCode(...bytes.slice(4, 32));
    return brand.includes("ftyp") && (brand.includes("avif") || brand.includes("avis"));
  }
  return false;
};

export const validatePublicImage = async (file: UploadedFile, context: RuntimeContext) => {
  if (!PLAYER_PHOTO_TYPES.has(file.type)) return { ok: false as const, error: "Choose a JPEG, PNG, WebP or AVIF image." };
  if (file.size <= 0 || file.size > playerPhotoMaxBytes(context)) {
    return { ok: false as const, error: "Choose an image within the configured upload limit." };
  }

  const bytes = new Uint8Array(await file.arrayBuffer());
  if (!matchesMagicBytes(bytes, file.type)) {
    return { ok: false as const, error: "The file content does not match its image type." };
  }

  const dimensions = imageDimensions(bytes, file.type);
  const maxWidth = Number(getRuntimeEnv(context, "MEDIA_MAX_IMAGE_WIDTH") ?? 2560);
  const maxHeight = Number(getRuntimeEnv(context, "MEDIA_MAX_IMAGE_HEIGHT") ?? 2560);
  if (!dimensions || dimensions.width <= 0 || dimensions.height <= 0) {
    return { ok: false as const, error: "The image dimensions could not be verified." };
  }
  if (dimensions.width > maxWidth || dimensions.height > maxHeight) {
    return { ok: false as const, error: `Image dimensions must not exceed ${maxWidth} × ${maxHeight} pixels.` };
  }

  return { ok: true as const, bytes, dimensions };
};

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
