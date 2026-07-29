#!/usr/bin/env node
/**
 * Lists every object key, size, and last-modified timestamp in both Cloudflare R2
 * buckets used by this project, via the R2 S3-compatible API. Writes a JSON
 * manifest (and a PII-free summary) under a gitignored local directory.
 *
 * This produces a key/metadata inventory only -- it does NOT copy object bytes.
 * See docs/backup-and-recovery-runbook.md §5.3 for object-copy guidance (rclone,
 * cross-account replication).
 *
 * Required environment variables (never hardcode these):
 *   CLOUDFLARE_ACCOUNT_ID
 *   R2_ACCESS_KEY_ID
 *   R2_SECRET_ACCESS_KEY
 *
 * Optional environment variables:
 *   R2_PUBLIC_BUCKET_NAME     (default: greenacre-eagles-public-media, from wrangler.jsonc)
 *   R2_PRIVATE_BUCKET_NAME    (default: greenacre-eagles-private-media, from wrangler.jsonc)
 *   R2_S3_ENDPOINT            (default: https://<account id>.r2.cloudflarestorage.com)
 *   R2_INVENTORY_OUTPUT_DIR   (default: <repo root>/backups/local)
 *
 * Usage:
 *   node scripts/backup/export-r2-inventory.mjs
 */

import { createHash, createHmac } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REGION = "auto";
const SERVICE = "s3";

const REQUIRED_ENV = ["CLOUDFLARE_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"];

function requireEnv() {
  const missing = REQUIRED_ENV.filter((key) => !process.env[key]);
  if (missing.length > 0) {
    console.error(`error: missing required environment variable(s): ${missing.join(", ")}`);
    console.error("Set these from the club's password manager for this shell session only. Never hardcode them.");
    process.exit(1);
  }
}

const sha256Hex = (data) => createHash("sha256").update(data).digest("hex");
const hmac = (key, data) => createHmac("sha256", key).update(data, "utf8").digest();

function getSigningKey(secretKey, dateStamp, region, service) {
  const kDate = hmac(`AWS4${secretKey}`, dateStamp);
  const kRegion = hmac(kDate, region);
  const kService = hmac(kRegion, service);
  return hmac(kService, "aws4_request");
}

function encodeRfc3986(value) {
  return encodeURIComponent(value).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
}

/**
 * Signs and sends a single S3-compatible GET request using AWS Signature
 * Version 4. Implemented with only Node built-ins so this script has zero
 * extra dependencies.
 */
async function signedGet({ endpoint, accessKeyId, secretAccessKey, bucket, query }) {
  const url = new URL(endpoint);
  const host = url.host;
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "");
  const dateStamp = amzDate.slice(0, 8);

  const canonicalUri = `/${encodeURIComponent(bucket)}`;
  const sortedQueryKeys = Object.keys(query).sort();
  const canonicalQuery = sortedQueryKeys
    .map((key) => `${encodeRfc3986(key)}=${encodeRfc3986(String(query[key]))}`)
    .join("&");

  const payloadHash = sha256Hex("");
  const canonicalHeaders = `host:${host}\nx-amz-content-sha256:${payloadHash}\nx-amz-date:${amzDate}\n`;
  const signedHeaders = "host;x-amz-content-sha256;x-amz-date";

  const canonicalRequest = [
    "GET",
    canonicalUri,
    canonicalQuery,
    canonicalHeaders,
    signedHeaders,
    payloadHash
  ].join("\n");

  const credentialScope = `${dateStamp}/${REGION}/${SERVICE}/aws4_request`;
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    credentialScope,
    sha256Hex(canonicalRequest)
  ].join("\n");

  const signingKey = getSigningKey(secretAccessKey, dateStamp, REGION, SERVICE);
  const signature = createHmac("sha256", signingKey).update(stringToSign, "utf8").digest("hex");

  const authorizationHeader = [
    `AWS4-HMAC-SHA256 Credential=${accessKeyId}/${credentialScope}`,
    `SignedHeaders=${signedHeaders}`,
    `Signature=${signature}`
  ].join(", ");

  const requestUrl = `${url.origin}${canonicalUri}${canonicalQuery ? `?${canonicalQuery}` : ""}`;

  const response = await fetch(requestUrl, {
    method: "GET",
    headers: {
      host,
      "x-amz-content-sha256": payloadHash,
      "x-amz-date": amzDate,
      authorization: authorizationHeader
    }
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`R2 list request failed (${response.status}) for bucket "${bucket}": ${text.slice(0, 500)}`);
  }
  return text;
}

function parseListObjectsV2(xml) {
  const contents = [];
  const contentBlocks = xml.match(/<Contents>[\s\S]*?<\/Contents>/g) ?? [];
  for (const block of contentBlocks) {
    const key = block.match(/<Key>([\s\S]*?)<\/Key>/)?.[1];
    const size = block.match(/<Size>([\s\S]*?)<\/Size>/)?.[1];
    const lastModified = block.match(/<LastModified>([\s\S]*?)<\/LastModified>/)?.[1];
    const etag = block.match(/<ETag>([\s\S]*?)<\/ETag>/)?.[1];
    if (key) {
      contents.push({
        key: decodeXmlEntities(key),
        sizeBytes: size ? Number(size) : null,
        lastModified: lastModified ?? null,
        etag: etag ?? null
      });
    }
  }
  const isTruncated = /<IsTruncated>true<\/IsTruncated>/.test(xml);
  const nextToken = xml.match(/<NextContinuationToken>([\s\S]*?)<\/NextContinuationToken>/)?.[1] ?? null;
  return { contents, isTruncated, nextToken };
}

function decodeXmlEntities(value) {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'");
}

async function listAllObjects({ endpoint, accessKeyId, secretAccessKey, bucket }) {
  const objects = [];
  let continuationToken;
  do {
    const query = { "list-type": "2", "max-keys": "1000" };
    if (continuationToken) query["continuation-token"] = continuationToken;
    const xml = await signedGet({ endpoint, accessKeyId, secretAccessKey, bucket, query });
    const { contents, isTruncated, nextToken } = parseListObjectsV2(xml);
    objects.push(...contents);
    continuationToken = isTruncated ? nextToken : null;
  } while (continuationToken);
  return objects;
}

async function main() {
  requireEnv();

  const accountId = process.env.CLOUDFLARE_ACCOUNT_ID;
  const accessKeyId = process.env.R2_ACCESS_KEY_ID;
  const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY;
  const endpoint = process.env.R2_S3_ENDPOINT || `https://${accountId}.r2.cloudflarestorage.com`;

  const buckets = [
    process.env.R2_PUBLIC_BUCKET_NAME || "greenacre-eagles-public-media",
    process.env.R2_PRIVATE_BUCKET_NAME || "greenacre-eagles-private-media"
  ];

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
  const outputDir = process.env.R2_INVENTORY_OUTPUT_DIR || path.join(repoRoot, "backups", "local");
  await mkdir(outputDir, { recursive: true });

  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const summary = { generatedAt: new Date().toISOString(), endpoint, buckets: [] };

  for (const bucket of buckets) {
    console.log(`Listing objects in bucket: ${bucket} ...`);
    let objects;
    try {
      objects = await listAllObjects({ endpoint, accessKeyId, secretAccessKey, bucket });
    } catch (error) {
      console.error(`error: failed to list bucket "${bucket}": ${error instanceof Error ? error.message : String(error)}`);
      summary.buckets.push({ bucket, error: "list_failed" });
      continue;
    }

    const totalBytes = objects.reduce((sum, obj) => sum + (obj.sizeBytes ?? 0), 0);
    const manifestFile = path.join(outputDir, `r2-inventory-${bucket}-${timestamp}.json`);
    await writeFile(
      manifestFile,
      JSON.stringify({ bucket, generatedAt: new Date().toISOString(), objectCount: objects.length, totalBytes, objects }, null, 2),
      "utf8"
    );

    console.log(`  ${objects.length} objects, ${totalBytes.toLocaleString()} bytes -> ${manifestFile}`);
    summary.buckets.push({ bucket, objectCount: objects.length, totalBytes, manifestFile });
  }

  const summaryFile = path.join(outputDir, `r2-inventory-summary-${timestamp}.json`);
  await writeFile(summaryFile, JSON.stringify(summary, null, 2), "utf8");
  console.log(`\nSummary (safe to share, contains no object keys/PII): ${summaryFile}`);
}

main().catch((error) => {
  console.error("R2 inventory export failed:", error instanceof Error ? error.message : error);
  process.exit(1);
});
