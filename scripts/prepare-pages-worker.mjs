import { cp, copyFile, mkdir, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const clientDir = join(root, "dist", "client");
const serverDir = join(root, "dist", "server");
const serverEntry = join(serverDir, "entry.mjs");
const workerDir = join(clientDir, "_worker.js");
const workerEntry = join(workerDir, "index.js");
const serverChunks = join(serverDir, "chunks");
const workerChunks = join(workerDir, "chunks");
const serverMiddleware = join(serverDir, "virtual_astro_middleware.mjs");
const workerMiddleware = join(workerDir, "virtual_astro_middleware.mjs");

if (!existsSync(serverEntry)) {
  throw new Error("Astro server entry was not found. Run this after astro build.");
}

await mkdir(clientDir, { recursive: true });
await rm(workerDir, { recursive: true, force: true });
await mkdir(workerDir, { recursive: true });
await copyFile(serverEntry, workerEntry);

await rm(workerChunks, { recursive: true, force: true });
await cp(serverChunks, workerChunks, { recursive: true });

if (existsSync(serverMiddleware)) {
  await copyFile(serverMiddleware, workerMiddleware);
}

console.log("Prepared Cloudflare Pages advanced-mode Worker directory in dist/client.");
