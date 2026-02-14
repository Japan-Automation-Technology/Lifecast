import type { FastifyReply, FastifyRequest } from "fastify";
import { randomUUID } from "node:crypto";
import { z } from "zod";

const uuidSchema = z.string().uuid();

const HEADER_USER_ID = "x-lifecast-user-id";

type AuthSource = "header" | "bearer" | "default" | "legacy_dev" | "none";
type SupabaseUserResponse = { id?: string };

declare module "fastify" {
  interface FastifyRequest {
    lifecastAuth: {
      userId: string | null;
      source: AuthSource;
    };
  }
}

async function resolveBearerUserId(req: FastifyRequest): Promise<string | null> {
  const rawAuth = req.headers.authorization;
  if (!rawAuth || typeof rawAuth !== "string") return null;
  const [scheme, token] = rawAuth.split(" ");
  if (!scheme || !token || scheme.toLowerCase() !== "bearer") return null;

  const supabaseUrl = process.env.LIFECAST_SUPABASE_URL ?? process.env.SUPABASE_URL;
  const supabaseAnonKey = process.env.LIFECAST_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY;
  if (!supabaseUrl || !supabaseAnonKey) return null;

  try {
    const response = await fetch(`${supabaseUrl.replace(/\/$/, "")}/auth/v1/user`, {
      headers: {
        apikey: supabaseAnonKey,
        Authorization: `Bearer ${token}`,
      },
    });
    if (!response.ok) return null;
    const payload = (await response.json()) as SupabaseUserResponse;
    const parsed = uuidSchema.safeParse(payload?.id);
    return parsed.success ? parsed.data : null;
  } catch {
    return null;
  }
}

export async function resolveRequestUserId(req: FastifyRequest): Promise<{ userId: string | null; source: AuthSource }> {
  const headerValue = req.headers[HEADER_USER_ID];
  const rawHeaderUserId = Array.isArray(headerValue) ? headerValue[0] : headerValue;
  if (typeof rawHeaderUserId === "string") {
    const parsed = uuidSchema.safeParse(rawHeaderUserId.trim());
    if (parsed.success) {
      return { userId: parsed.data, source: "header" };
    }
  }

  const bearerUserId = await resolveBearerUserId(req);
  if (bearerUserId) {
    return { userId: bearerUserId, source: "bearer" };
  }

  const defaultUserId = process.env.LIFECAST_DEFAULT_USER_ID;
  if (defaultUserId) {
    const parsed = uuidSchema.safeParse(defaultUserId.trim());
    if (parsed.success) {
      return { userId: parsed.data, source: "default" };
    }
  }

  const legacyDevUserId =
    process.env.LIFECAST_DEV_CREATOR_USER_ID ??
    process.env.LIFECAST_DEV_VIEWER_USER_ID ??
    process.env.LIFECAST_DEV_SUPPORTER_USER_ID ??
    null;
  if (legacyDevUserId) {
    const parsed = uuidSchema.safeParse(legacyDevUserId.trim());
    if (parsed.success) {
      return { userId: parsed.data, source: "legacy_dev" };
    }
  }

  return { userId: null, source: "none" };
}

export function requireRequestUserId(req: FastifyRequest, reply: FastifyReply) {
  if (req.lifecastAuth.userId) return req.lifecastAuth.userId;
  reply.code(401).send({
    request_id: randomUUID(),
    server_time: new Date().toISOString(),
    error: {
      code: "UNAUTHORIZED",
      message: "Missing authenticated user. Send Authorization bearer token or x-lifecast-user-id header.",
    },
  });
  return null;
}
