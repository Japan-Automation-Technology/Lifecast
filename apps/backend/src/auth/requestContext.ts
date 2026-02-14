import type { FastifyReply, FastifyRequest } from "fastify";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { dbPool, hasDb } from "../store/db.js";

const uuidSchema = z.string().uuid();

const HEADER_USER_ID = "x-lifecast-user-id";

type AuthSource = "header" | "bearer" | "none";
type SupabaseUserResponse = {
  id?: string;
  email?: string | null;
  user_metadata?: {
    user_name?: string | null;
    username?: string | null;
    preferred_username?: string | null;
    name?: string | null;
    full_name?: string | null;
    display_name?: string | null;
    avatar_url?: string | null;
    picture?: string | null;
  } | null;
};

declare module "fastify" {
  interface FastifyRequest {
    lifecastAuth: {
      userId: string | null;
      source: AuthSource;
    };
  }
}

function sanitizeUsername(input: string | null | undefined) {
  const trimmed = (input ?? "").trim().toLowerCase();
  if (!trimmed) return null;
  const sanitized = trimmed.replace(/[^a-z0-9_.-]/g, "_").slice(0, 40);
  return sanitized.length >= 3 ? sanitized : null;
}

function normalizeDisplayName(input: string | null | undefined) {
  const trimmed = (input ?? "").trim();
  return trimmed.length > 0 ? trimmed.slice(0, 80) : null;
}

function normalizeAvatarUrl(input: string | null | undefined) {
  const trimmed = (input ?? "").trim();
  if (!trimmed) return null;
  return trimmed.length <= 2048 ? trimmed : null;
}

async function ensureUserRow(
  userId: string,
  identity?: {
    email: string | null;
    username: string | null;
    displayName: string | null;
    avatarUrl: string | null;
  },
) {
  if (!hasDb() || !dbPool) return;

  const client = await dbPool.connect();
  try {
    await client.query(
      `
      insert into users (id, email, username, display_name, avatar_url, created_at, updated_at)
      values ($1, $2, $3, $4, $5, now(), now())
      on conflict (id)
      do update
      set
        email = coalesce(excluded.email, users.email),
        username = coalesce(users.username, excluded.username),
        display_name = coalesce(excluded.display_name, users.display_name),
        avatar_url = coalesce(excluded.avatar_url, users.avatar_url),
        updated_at = now()
    `,
      [
        userId,
        identity?.email ?? null,
        identity?.username ?? null,
        identity?.displayName ?? null,
        identity?.avatarUrl ?? null,
      ],
    );
  } finally {
    client.release();
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
    if (!parsed.success) return null;

    const metadata = payload.user_metadata ?? null;
    const username = sanitizeUsername(
      metadata?.preferred_username ??
        metadata?.username ??
        metadata?.user_name ??
        (typeof payload.email === "string" ? payload.email.split("@")[0] : null),
    );
    const displayName = normalizeDisplayName(
      metadata?.display_name ?? metadata?.full_name ?? metadata?.name,
    );
    const avatarUrl = normalizeAvatarUrl(metadata?.avatar_url ?? metadata?.picture);
    const email = typeof payload.email === "string" ? payload.email.trim().toLowerCase() : null;

    await ensureUserRow(parsed.data, {
      email,
      username,
      displayName,
      avatarUrl,
    });

    return parsed.data;
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
      await ensureUserRow(parsed.data);
      return { userId: parsed.data, source: "header" };
    }
  }

  const bearerUserId = await resolveBearerUserId(req);
  if (bearerUserId) {
    return { userId: bearerUserId, source: "bearer" };
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
      message: "Missing authenticated user. Send Authorization bearer token.",
    },
  });
  return null;
}
