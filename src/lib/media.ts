import { env } from "cloudflare:workers";
import {
  buildPublicMediaUrl,
  normaliseObjectKey,
  resolveMediaBindings,
  validatePublicImageInput,
  type R2Bucket,
  type UploadedFile
} from "./media-core";

export { getUploadedFile, putPublicMediaObject, type R2Bucket, type UploadedFile } from "./media-core";

type RuntimeContext = {
  locals?: unknown;
  request?: Request;
  url?: URL;
};
type ImageValidationOptions = { maxBytes?: number; maxWidth?: number; maxHeight?: number };

const warned = new Set<string>();
const warnOnce = (key: string, message: string, details?: Record<string, unknown>) => {
  if (warned.has(key)) return;
  warned.add(key);
  console.warn(message, details ?? {});
};

const buildEnv = () => {
  try {
    return ((import.meta as ImportMeta & { env?: Record<string, unknown> }).env ?? {}) as Record<string, unknown>;
  } catch {
    return {};
  }
};

export const getRuntimeEnv = (_context: RuntimeContext, key: string) => {
  const runtimeValue = (env as Record<string, unknown>)[key];
  if (runtimeValue !== undefined) return runtimeValue;
  return buildEnv()[key];
};

const bindingState = (context: RuntimeContext) => {
  const bindings = resolveMediaBindings(env as Record<string, unknown>);
  let requestHostname = "unknown";
  let routeName = "unknown";
  try {
    const url = context.request ? new URL(context.request.url) : context.url;
    requestHostname = url?.hostname ?? requestHostname;
    routeName = url?.pathname ?? routeName;
  } catch {
    // The binding result remains useful even if request metadata is malformed.
  }
  console.info("Cloudflare media binding state", {
    routeName,
    requestHostname,
    publicBindingPresent: Boolean(bindings.publicBucket),
    privateBindingPresent: Boolean(bindings.privateBucket)
  });
  return bindings;
};

export const getPublicMediaBucket = (context: RuntimeContext): R2Bucket | null =>
  bindingState(context).publicBucket;

export const getPrivateMediaBucket = (context: RuntimeContext): R2Bucket | null =>
  bindingState(context).privateBucket;

export const getPublicMediaBaseUrl = (context: RuntimeContext): string | null => {
  const configured = String(getRuntimeEnv(context, "PUBLIC_MEDIA_BASE_URL") ?? "").trim().replace(/\/+$/, "");
  if (!configured) {
    warnOnce("missing-public-media-base", "PUBLIC_MEDIA_BASE_URL is unavailable. Public object uploads may work, but object-key images cannot be displayed.");
    return null;
  }
  try {
    const url = new URL(configured);
    if (url.protocol !== "https:" && !(url.protocol === "http:" && ["localhost","127.0.0.1"].includes(url.hostname))) throw new Error("Public media URL must use HTTPS.");
    return url.toString().replace(/\/+$/, "");
  } catch (cause) {
    warnOnce("invalid-public-media-base", "PUBLIC_MEDIA_BASE_URL is invalid. Public media pages will use their no-image fallback.", { configured, cause });
    return null;
  }
};

export const getMediaCapabilities = (context: RuntimeContext) => {
  const { publicBucket, privateBucket } = bindingState(context);
  const publicBaseUrl = getPublicMediaBaseUrl(context);
  return {
    publicBucket,
    privateBucket,
    publicBaseUrl,
    publicMediaConfigured: Boolean(publicBucket),
    publicMediaDeliveryConfigured: Boolean(publicBaseUrl),
    privateMediaConfigured: Boolean(privateBucket)
  };
};


export const getPublicMediaUrl = (objectKey: string | null | undefined, context: RuntimeContext): string | null => {
  const base = getPublicMediaBaseUrl(context);
  return base ? buildPublicMediaUrl(base, objectKey) : null;
};

export const getSafeExternalImageUrl = (value: string | null | undefined) => {
  if (!value) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" || (url.protocol === "http:" && ["localhost","127.0.0.1"].includes(url.hostname)) ? url.toString() : null;
  } catch {
    return null;
  }
};
export const getManagedPublicObjectKey = (value: string | null | undefined, context: RuntimeContext) => {
  if (!value) return null;
  const base = getPublicMediaBaseUrl(context);
  if (!base) return null;
  try {
    const url = new URL(value);
    const baseUrl = new URL(`${base}/`);
    if (url.origin !== baseUrl.origin || !url.pathname.startsWith(baseUrl.pathname)) return null;
    const encodedKey = url.pathname.slice(baseUrl.pathname.length);
    const decodedKey = encodedKey.split("/").map(decodeURIComponent).join("/");
    return normaliseObjectKey(decodedKey);
  } catch {
    return null;
  }
};


export const PLAYER_PHOTO_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/avif"]);
const IMAGE_EXTENSIONS: Record<string, string[]> = {
  "image/jpeg": ["jpg", "jpeg"],
  "image/png": ["png"],
  "image/webp": ["webp"],
  "image/avif": ["avif"]
};
const PRIVATE_FILE_EXTENSIONS: Record<string, string[]> = {
  ...IMAGE_EXTENSIONS,
  "application/pdf": ["pdf"],
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document": ["docx"]
};

export const playerPhotoMaxBytes = (context: RuntimeContext) =>
  Number(getRuntimeEnv(context, "PUBLIC_MEDIA_MAX_FILE_SIZE") ?? 10_485_760);

const extensionMatches = (file: UploadedFile, allowed: Record<string, string[]>) => {
  const name = String(file.name ?? "").trim().toLowerCase();
  if (!name || !name.includes(".")) return true;
  const extension = name.split(".").pop() ?? "";
  return Boolean(allowed[file.type]?.includes(extension));
};

const readUint24LE = (bytes: Uint8Array, offset: number) =>
  bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);

const imageDimensions = (bytes: Uint8Array, mimeType: string) => {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (mimeType === "image/png" && bytes.length >= 24) return { width: view.getUint32(16), height: view.getUint32(20) };
  if (mimeType === "image/jpeg") {
    let offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] !== 0xff) break;
      const marker = bytes[offset + 1];
      const length = view.getUint16(offset + 2);
      if (marker >= 0xc0 && marker <= 0xc3) return { height: view.getUint16(offset + 5), width: view.getUint16(offset + 7) };
      if (length < 2) break;
      offset += length + 2;
    }
  }
  if (mimeType === "image/webp" && bytes.length >= 30) {
    const chunk = String.fromCharCode(...bytes.slice(12, 16));
    if (chunk === "VP8X") return { width: readUint24LE(bytes, 24) + 1, height: readUint24LE(bytes, 27) + 1 };
  }
  if (mimeType === "image/avif") {
    for (let offset = 4; offset + 16 <= bytes.length; offset += 1) {
      if (String.fromCharCode(...bytes.slice(offset, offset + 4)) === "ispe") return { width: view.getUint32(offset + 8), height: view.getUint32(offset + 12) };
    }
  }
  return null;
};

const matchesMagicBytes = (bytes: Uint8Array, mimeType: string) => {
  if (mimeType === "image/jpeg") return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (mimeType === "image/png") return [0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a].every((value,index) => bytes[index] === value);
  if (mimeType === "image/webp") return String.fromCharCode(...bytes.slice(0,4)) === "RIFF" && String.fromCharCode(...bytes.slice(8,12)) === "WEBP";
  if (mimeType === "image/avif") {
    const brand = String.fromCharCode(...bytes.slice(4,32));
    return brand.includes("ftyp") && (brand.includes("avif") || brand.includes("avis"));
  }
  return false;
};

export const validatePublicImage = async (file: UploadedFile, context: RuntimeContext, options: ImageValidationOptions = {}) => {
  const maxBytes = options.maxBytes ?? playerPhotoMaxBytes(context);
  const inputValidation = validatePublicImageInput(file, maxBytes);
  if (!inputValidation.ok) return inputValidation;
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (bytes.byteLength !== file.size || !matchesMagicBytes(bytes,file.type)) return { ok:false as const, error:"The file content does not match its image type." };
  const dimensions = imageDimensions(bytes,file.type);
  const maxWidth = options.maxWidth ?? Number(getRuntimeEnv(context,"MEDIA_MAX_IMAGE_WIDTH") ?? 2560);
  const maxHeight = options.maxHeight ?? Number(getRuntimeEnv(context,"MEDIA_MAX_IMAGE_HEIGHT") ?? 2560);
  if (!dimensions || dimensions.width <= 0 || dimensions.height <= 0) return { ok:false as const, error:"The image dimensions could not be verified." };
  if (dimensions.width > maxWidth || dimensions.height > maxHeight) return { ok:false as const, error:`Image dimensions must not exceed ${maxWidth} × ${maxHeight} pixels.` };
  return { ok:true as const, bytes, dimensions };
};

export const validatePrivateFile = async (file: UploadedFile, context: RuntimeContext) => {
  if (!Object.hasOwn(PRIVATE_FILE_EXTENSIONS,file.type)) return { ok:false as const, error:"Choose a PDF, DOCX, JPEG, PNG, WebP or AVIF file." };
  if (!extensionMatches(file,PRIVATE_FILE_EXTENSIONS)) return { ok:false as const, error:"The file extension does not match its file type." };
  const maxBytes = Number(getRuntimeEnv(context,"PRIVATE_MEDIA_MAX_FILE_SIZE") ?? 15_728_640);
  if (file.size <= 0 || file.size > maxBytes) return { ok:false as const, error:`Choose a file smaller than ${Math.floor(maxBytes / 1_048_576)} MB.` };
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (bytes.byteLength !== file.size) return { ok:false as const, error:"The uploaded file is incomplete." };
  if (PLAYER_PHOTO_TYPES.has(file.type)) {
    if (!matchesMagicBytes(bytes,file.type)) return { ok:false as const, error:"The file content does not match its image type." };
  } else if (file.type === "application/pdf" && String.fromCharCode(...bytes.slice(0,5)) !== "%PDF-") {
    return { ok:false as const, error:"The selected file is not a valid PDF." };
  } else if (file.type.includes("wordprocessingml") && !(bytes[0] === 0x50 && bytes[1] === 0x4b && bytes[2] === 0x03 && bytes[3] === 0x04)) {
    return { ok:false as const, error:"The selected file is not a valid DOCX document." };
  }
  return { ok:true as const, bytes };
};

const extensionForMime = (mimeType: string) => (mimeType === "image/jpeg" ? "jpg" : PRIVATE_FILE_EXTENSIONS[mimeType]?.[0] ?? "bin");
const generatedKey = (folder: string, id: string, mimeType: string) => `${folder}/${id}/${crypto.randomUUID()}.${extensionForMime(mimeType)}`;

export const playerPhotoObjectKey = (id: string, mimeType: string) => generatedKey("players",id,mimeType);
export const socialPostImageObjectKey = (id: string, mimeType: string) => generatedKey("social-posts",id,mimeType);
export const sponsorLogoObjectKey = (id: string, mimeType: string) => generatedKey("sponsors",id,mimeType);
export const eventImageObjectKey = (id: string, mimeType: string) => generatedKey("events",id,mimeType);
export const articleImageObjectKey = (id: string, mimeType: string) => generatedKey("articles",id,mimeType);
export const merchandiseImageObjectKey = (id: string, mimeType: string) => generatedKey("merchandise",id,mimeType);
export const canteenImageObjectKey = (id: string, mimeType: string) => generatedKey("canteen",id,mimeType);
export const teamImageObjectKey = (id: string, mimeType: string) => generatedKey("teams",id,mimeType);
export const coachingAttachmentObjectKey = (id: string, mimeType: string) => generatedKey("coaching-resources",id,mimeType);
export const wwccDocumentObjectKey = (userId: string, submissionId: string, mimeType: string) =>
  generatedKey("wwcc/"+userId,submissionId,mimeType);

export const deleteR2Object = async (bucket: R2Bucket | null, objectKey: string | null | undefined, label: string) => {
  const key = normaliseObjectKey(objectKey);
  if (!bucket || !key) return false;
  try {
    await bucket.delete(key);
    return true;
  } catch (cause) {
    console.error(`${label} R2 cleanup failed`, { cause, objectKey:key });
    return false;
  }
};
