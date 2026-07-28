export type R2ObjectBody = {
  body: ReadableStream;
  httpMetadata?: { contentType?: string };
  writeHttpMetadata?(headers: Headers): void;
};

export type R2Bucket = {
  put(key: string, value: ArrayBuffer | ArrayBufferView | Blob | ReadableStream, options?: unknown): Promise<unknown>;
  get(key: string): Promise<R2ObjectBody | null>;
  head(key: string): Promise<unknown | null>;
  delete(key: string | string[]): Promise<void>;
};

export type UploadedFile = {
  name?: string;
  size: number;
  type: string;
  arrayBuffer(): Promise<ArrayBuffer>;
};

const publicImageExtensions: Record<string, string[]> = {
  "image/jpeg": ["jpg", "jpeg"],
  "image/png": ["png"],
  "image/webp": ["webp"],
  "image/avif": ["avif"]
};

export const isR2Bucket = (value: unknown): value is R2Bucket => {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<R2Bucket>;
  return typeof candidate.put === "function"
    && typeof candidate.get === "function"
    && typeof candidate.head === "function"
    && typeof candidate.delete === "function";
};

export const resolveMediaBindings = (runtimeEnv: Record<string, unknown> | null | undefined) => ({
  publicBucket: isR2Bucket(runtimeEnv?.PUBLIC_MEDIA_BUCKET) ? runtimeEnv.PUBLIC_MEDIA_BUCKET : null,
  privateBucket: isR2Bucket(runtimeEnv?.PRIVATE_MEDIA_BUCKET) ? runtimeEnv.PRIVATE_MEDIA_BUCKET : null
});

export const getUploadedFile = (value: FormDataEntryValue | null): UploadedFile | null => {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Partial<UploadedFile>;
  if (typeof candidate.size !== "number" || candidate.size <= 0) return null;
  if (typeof candidate.type !== "string" || typeof candidate.arrayBuffer !== "function") return null;
  return candidate as UploadedFile;
};

export const validatePublicImageInput = (file: UploadedFile, maxBytes: number) => {
  const allowedExtensions = publicImageExtensions[file.type];
  if (!allowedExtensions) {
    return { ok: false as const, error: "Choose a JPEG, PNG, WebP or AVIF image." };
  }

  const name = String(file.name ?? "").trim().toLowerCase();
  if (name.includes(".") && !allowedExtensions.includes(name.split(".").pop() ?? "")) {
    return { ok: false as const, error: "The file extension does not match the selected image type." };
  }

  if (file.size <= 0 || file.size > maxBytes) {
    return { ok: false as const, error: `Choose an image smaller than ${Math.floor(maxBytes / 1_048_576)} MB.` };
  }

  return { ok: true as const };
};

export const normaliseObjectKey = (value: string | null | undefined) => {
  const key = String(value ?? "").trim();
  if (!key || key.length > 900 || key.startsWith("/") || key.includes("\\") || key.includes("\0")) return null;
  const segments = key.split("/");
  if (segments.some((segment) => !segment || segment === "." || segment === "..")) return null;
  return segments.join("/");
};

export const buildPublicMediaUrl = (baseUrl: string, objectKey: string | null | undefined) => {
  const key = normaliseObjectKey(objectKey);
  if (!key) return null;
  return `${baseUrl.replace(/\/+$/, "")}/${key.split("/").map(encodeURIComponent).join("/")}`;
};

export const putPublicMediaObject = async (
  bucket: R2Bucket,
  objectKey: string,
  bytes: ArrayBuffer | ArrayBufferView,
  contentType: string
) => {
  const key = normaliseObjectKey(objectKey);
  if (!key) throw new Error("Invalid public media object key.");
  if (!publicImageExtensions[contentType]) throw new Error("Unsupported public media content type.");

  await bucket.put(key, bytes, {
    httpMetadata: {
      contentType,
      cacheControl: "public, max-age=31536000, immutable"
    }
  });
  return key;
};
