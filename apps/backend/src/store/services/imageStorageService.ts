import { Storage } from "@google-cloud/storage";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

type ImageKind = "projects" | "profiles";

const LOCAL_ROOTS: Record<ImageKind, string> = {
  projects: resolve(process.cwd(), ".data/project-images"),
  profiles: resolve(process.cwd(), ".data/profile-images"),
};

let storage: Storage | null = null;

function getGcsBucketName() {
  const raw = process.env.LIFECAST_GCS_BUCKET?.trim();
  return raw && raw.length > 0 ? raw : null;
}

function getGcsPrefix() {
  const raw = process.env.LIFECAST_GCS_IMAGE_PREFIX ?? "images";
  return raw.replace(/^\/+|\/+$/g, "");
}

function getStorageClient() {
  if (!storage) {
    storage = new Storage();
  }
  return storage;
}

function getGcsObjectKey(kind: ImageKind, fileName: string) {
  return `${getGcsPrefix()}/${kind}/${fileName}`;
}

export async function writeImageBinary(input: {
  kind: ImageKind;
  fileName: string;
  contentType: string;
  data: Buffer;
}) {
  const gcsBucket = getGcsBucketName();
  if (gcsBucket) {
    const key = getGcsObjectKey(input.kind, input.fileName);
    const bucket = getStorageClient().bucket(gcsBucket);
    await bucket.file(key).save(input.data, {
      resumable: false,
      contentType: input.contentType,
      metadata: {
        cacheControl: "public, max-age=31536000, immutable",
      },
    });
    return;
  }

  const localRoot = LOCAL_ROOTS[input.kind];
  const localPath = resolve(localRoot, input.fileName);
  await mkdir(localRoot, { recursive: true });
  await writeFile(localPath, input.data);
}

export async function readImageBinary(input: { kind: ImageKind; fileName: string }) {
  const gcsBucket = getGcsBucketName();
  if (gcsBucket) {
    const key = getGcsObjectKey(input.kind, input.fileName);
    try {
      const bucket = getStorageClient().bucket(gcsBucket);
      const [data] = await bucket.file(key).download();
      return data;
    } catch (error) {
      const gcsError = error as { code?: number | string };
      if (gcsError.code !== 404 && gcsError.code !== "404") {
        throw error;
      }
    }
  }

  const localRoot = LOCAL_ROOTS[input.kind];
  const localPath = resolve(localRoot, input.fileName);
  return readFile(localPath);
}
