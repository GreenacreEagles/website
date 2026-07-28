import test from "node:test";
import assert from "node:assert/strict";
import {
  buildPublicMediaUrl,
  getUploadedFile,
  putPublicMediaObject,
  resolveMediaBindings,
  validatePublicImageInput
} from "../src/lib/media-core.ts";

const createBucket = (overrides = {}) => ({
  put: async () => ({}),
  get: async () => null,
  head: async () => null,
  delete: async () => {},
  ...overrides
});

const createFile = ({
  name = "club-logo.png",
  size = 128,
  type = "image/png"
} = {}) => ({
  name,
  size,
  type,
  arrayBuffer: async () => new ArrayBuffer(size)
});

test("public R2 binding resolves as a native bucket object", () => {
  const publicBucket = createBucket();
  const result = resolveMediaBindings({ PUBLIC_MEDIA_BUCKET: publicBucket });
  assert.equal(result.publicBucket, publicBucket);
});

test("missing public R2 binding returns null", () => {
  const result = resolveMediaBindings({
    PUBLIC_MEDIA_BUCKET: "greenacre-eagles-public-media"
  });
  assert.equal(result.publicBucket, null);
});

test("private R2 binding resolves consistently", () => {
  const privateBucket = createBucket();
  const result = resolveMediaBindings({ PRIVATE_MEDIA_BUCKET: privateBucket });
  assert.equal(result.privateBucket, privateBucket);
});

test("valid structural upload is accepted and written with immutable cache metadata", async () => {
  let written;
  const bucket = createBucket({
    put: async (key, bytes, options) => {
      written = { key, bytes, options };
      return {};
    }
  });
  const file = getUploadedFile(createFile());
  assert.ok(file);
  assert.deepEqual(validatePublicImageInput(file, 1_048_576), { ok: true });

  const key = await putPublicMediaObject(bucket, "sponsors/club/logo.png", new Uint8Array([1, 2, 3]), file.type);
  assert.equal(key, "sponsors/club/logo.png");
  assert.equal(written.key, key);
  assert.equal(written.options.httpMetadata.contentType, "image/png");
  assert.equal(written.options.httpMetadata.cacheControl, "public, max-age=31536000, immutable");
});

test("oversized image is rejected before R2 put", () => {
  const file = createFile({ size: 2_000_000 });
  const result = validatePublicImageInput(file, 1_000_000);
  assert.equal(result.ok, false);
  assert.match(result.error, /smaller/i);
});

test("unsupported image type is rejected", () => {
  const file = createFile({ name: "payload.svg", type: "image/svg+xml" });
  const result = validatePublicImageInput(file, 1_000_000);
  assert.equal(result.ok, false);
  assert.match(result.error, /JPEG, PNG, WebP or AVIF/);
});

test("failed R2 put is propagated to the route error handler", async () => {
  const bucket = createBucket({
    put: async () => {
      throw new Error("simulated R2 failure");
    }
  });
  await assert.rejects(
    putPublicMediaObject(bucket, "events/event/image.jpg", new Uint8Array([1]), "image/jpeg"),
    /simulated R2 failure/
  );
});

test("successful public object URL is safely generated", () => {
  assert.equal(
    buildPublicMediaUrl("https://media.greenacreeaglesfc.com/", "social-posts/post/card image.webp"),
    "https://media.greenacreeaglesfc.com/social-posts/post/card%20image.webp"
  );
  assert.equal(buildPublicMediaUrl("https://media.greenacreeaglesfc.com", "../secret"), null);
});
