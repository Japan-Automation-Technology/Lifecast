import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { requireRequestUserId } from "../auth/requestContext.js";
import { fail, ok } from "../response.js";
import { dbPool, hasDb } from "../store/db.js";

const devSwitchBody = z.object({
  user_id: z.string().uuid(),
});

const usernamePattern = /^[A-Za-z0-9_]+$/;
const passwordHasUppercase = /[A-Z]/;
const passwordHasLowercase = /[a-z]/;
const passwordHasNumber = /[0-9]/;
const passwordHasSymbol = /[^A-Za-z0-9]/;
const passwordHasWhitespace = /\s/;

const emailSignUpBody = z.object({
  email: z.string().email(),
  password: z.string().min(10).max(72),
  username: z.string().min(3).max(40).optional(),
  display_name: z.string().min(1).max(30).optional(),
}).superRefine((value, ctx) => {
  if (passwordHasWhitespace.test(value.password)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["password"],
      message: "password must not contain spaces",
    });
  }
  if (
    !passwordHasUppercase.test(value.password)
    || !passwordHasLowercase.test(value.password)
    || !passwordHasNumber.test(value.password)
    || !passwordHasSymbol.test(value.password)
  ) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["password"],
      message: "password must include uppercase, lowercase, number, and symbol",
    });
  }
  if (value.username !== undefined && !usernamePattern.test(value.username)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["username"],
      message: "username must contain only letters, numbers, and underscore",
    });
  }
});

const emailSignInBody = z.object({
  email: z.string().email(),
  password: z.string().min(1).max(200),
});

const refreshTokenBody = z.object({
  refresh_token: z.string().min(1),
});

const oauthUrlQuery = z.object({
  provider: z.enum(["google", "apple"]),
  redirect_to: z.string().url().optional(),
});

function mustAuthEnv() {
  const supabaseUrl = process.env.LIFECAST_SUPABASE_URL ?? process.env.SUPABASE_URL;
  const supabaseAnonKey = process.env.LIFECAST_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY;
  if (!supabaseUrl || !supabaseAnonKey) return null;
  return { supabaseUrl: supabaseUrl.replace(/\/$/, ""), supabaseAnonKey };
}

async function supabaseAuthRequest(
  path: string,
  input: { method?: "GET" | "POST"; body?: unknown; bearerToken?: string },
) {
  const env = mustAuthEnv();
  if (!env) {
    return { ok: false as const, status: 500, payload: { message: "SUPABASE auth env is not configured" } };
  }

  try {
    const response = await fetch(`${env.supabaseUrl}${path}`, {
      method: input.method ?? "POST",
      headers: {
        apikey: env.supabaseAnonKey,
        ...(input.bearerToken ? { Authorization: `Bearer ${input.bearerToken}` } : {}),
        ...(typeof input.body === "undefined" ? {} : { "Content-Type": "application/json" }),
      },
      body: typeof input.body === "undefined" ? undefined : JSON.stringify(input.body),
    });
    const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    return { ok: response.ok, status: response.status, payload };
  } catch {
    return { ok: false as const, status: 502, payload: { message: "Auth provider request failed" } };
  }
}

function extractSupabaseErrorMessage(payload: Record<string, unknown>, fallback: string) {
  const candidates = [
    payload.message,
    payload.msg,
    payload.error_description,
    payload.error,
  ];
  for (const value of candidates) {
    if (typeof value === "string" && value.trim().length > 0) {
      return value.trim();
    }
  }

  const errorCode = typeof payload.error_code === "string" ? payload.error_code : "";
  if (errorCode === "over_email_send_rate_limit") {
    return "Too many sign-up attempts for this email. Please wait a moment and try again.";
  }
  if (errorCode === "email_exists" || errorCode === "user_already_exists") {
    return "This email is already registered. Please sign in instead.";
  }
  return fallback;
}

export async function registerAuthRoutes(app: FastifyInstance) {
  app.post("/v1/auth/email/sign-up", async (req, reply) => {
    const body = emailSignUpBody.safeParse(req.body);
    if (!body.success) {
      const firstIssue = body.error.issues[0];
      const message = firstIssue?.message ?? "Invalid sign-up payload";
      return reply.code(400).send(fail("VALIDATION_ERROR", message));
    }

    const normalizedUsername = body.data.username?.trim();
    if (normalizedUsername && hasDb() && dbPool) {
      const client = await dbPool.connect();
      try {
        const existing = await client.query<{ exists: boolean }>(
          `
          select exists(
            select 1 from users where lower(username) = lower($1)
            union all
            select 1 from creator_profiles where lower(username) = lower($1)
          ) as exists
        `,
          [normalizedUsername],
        );
        if (existing.rows[0]?.exists) {
          return reply.code(409).send(fail("STATE_CONFLICT", "Username is already taken. Please choose another one."));
        }
      } finally {
        client.release();
      }
    }

    const response = await supabaseAuthRequest("/auth/v1/signup", {
      body: {
        email: body.data.email,
        password: body.data.password,
        data: {
          username: normalizedUsername ?? null,
          display_name: body.data.display_name ?? null,
        },
      },
    });
    if (!response.ok) {
      const message = extractSupabaseErrorMessage(response.payload, "Sign-up failed");
      if (/already registered/i.test(message)) {
        return reply.code(409).send(fail("STATE_CONFLICT", "This email is already registered. Please sign in instead."));
      }
      if (/username|uq_users_username_ci|creator_profiles.*username|duplicate key value/i.test(message)) {
        return reply.code(409).send(fail("STATE_CONFLICT", "Username is already taken. Please choose another one."));
      }
      return reply
        .code(response.status >= 400 && response.status < 500 ? response.status : 400)
        .send(fail("AUTH_FAILED", message));
    }

    return reply.send(
      ok({
        user: response.payload.user ?? null,
        session: response.payload.session ?? null,
      }),
    );
  });

  app.post("/v1/auth/email/sign-in", async (req, reply) => {
    const body = emailSignInBody.safeParse(req.body);
    if (!body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid sign-in payload"));
    }

    const response = await supabaseAuthRequest("/auth/v1/token?grant_type=password", {
      body: {
        email: body.data.email,
        password: body.data.password,
      },
    });
    if (!response.ok) {
      return reply
        .code(response.status >= 400 && response.status < 500 ? response.status : 401)
        .send(fail("AUTH_FAILED", String(response.payload.message ?? "Sign-in failed")));
    }

    return reply.send(
      ok({
        access_token: response.payload.access_token ?? null,
        refresh_token: response.payload.refresh_token ?? null,
        expires_in: response.payload.expires_in ?? null,
        token_type: response.payload.token_type ?? null,
        user: response.payload.user ?? null,
      }),
    );
  });

  app.post("/v1/auth/token/refresh", async (req, reply) => {
    const body = refreshTokenBody.safeParse(req.body);
    if (!body.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid refresh payload"));
    }

    const response = await supabaseAuthRequest("/auth/v1/token?grant_type=refresh_token", {
      body: {
        refresh_token: body.data.refresh_token,
      },
    });
    if (!response.ok) {
      return reply
        .code(response.status >= 400 && response.status < 500 ? response.status : 401)
        .send(fail("AUTH_FAILED", String(response.payload.message ?? "Refresh failed")));
    }

    return reply.send(
      ok({
        access_token: response.payload.access_token ?? null,
        refresh_token: response.payload.refresh_token ?? null,
        expires_in: response.payload.expires_in ?? null,
        token_type: response.payload.token_type ?? null,
        user: response.payload.user ?? null,
      }),
    );
  });

  app.post("/v1/auth/sign-out", async (req, reply) => {
    const rawAuth = req.headers.authorization;
    const bearerToken = typeof rawAuth === "string" && rawAuth.toLowerCase().startsWith("bearer ")
      ? rawAuth.slice(7).trim()
      : "";
    if (!bearerToken) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Authorization bearer token is required"));
    }

    const response = await supabaseAuthRequest("/auth/v1/logout", {
      method: "POST",
      bearerToken,
    });
    if (!response.ok) {
      return reply.code(400).send(fail("AUTH_FAILED", String(response.payload.message ?? "Sign-out failed")));
    }
    return reply.send(ok({ signed_out: true }));
  });

  app.get("/v1/auth/oauth/url", async (req, reply) => {
    const parsed = oauthUrlQuery.safeParse(req.query ?? {});
    if (!parsed.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid oauth query"));
    }
    const env = mustAuthEnv();
    if (!env) {
      return reply.code(500).send(fail("SYSTEM_ERROR", "SUPABASE auth env is not configured"));
    }

    const appRedirect = process.env.LIFECAST_AUTH_REDIRECT_URL ?? "lifecast://auth/callback";
    const redirectTo = parsed.data.redirect_to ?? appRedirect;
    const url = new URL(`${env.supabaseUrl}/auth/v1/authorize`);
    url.searchParams.set("provider", parsed.data.provider);
    url.searchParams.set("redirect_to", redirectTo);
    return reply.send(
      ok({
        provider: parsed.data.provider,
        redirect_to: redirectTo,
        authorize_url: url.toString(),
      }),
    );
  });

  app.get("/v1/auth/me", async (req, reply) => {
    const userId = requireRequestUserId(req, reply);
    if (!userId) return;

    if (!hasDb() || !dbPool) {
      return reply.send(
        ok({
          user_id: userId,
          auth_source: req.lifecastAuth.source,
          profile: null,
        }),
      );
    }

    const client = await dbPool.connect();
    try {
      const profileResult = await client.query<{
        creator_user_id: string;
        username: string;
        display_name: string | null;
        bio: string | null;
        avatar_url: string | null;
      }>(
        `
        select
          u.id as creator_user_id,
          coalesce(cp.username, u.username, 'user_' || left(u.id::text, 8)) as username,
          coalesce(cp.display_name, u.display_name) as display_name,
          coalesce(cp.bio, u.bio) as bio,
          coalesce(cp.avatar_url, u.avatar_url) as avatar_url
        from users u
        left join creator_profiles cp on cp.creator_user_id = u.id
        where u.id = $1
        limit 1
      `,
        [userId],
      );

      return reply.send(
        ok({
          user_id: userId,
          auth_source: req.lifecastAuth.source,
          profile: profileResult.rows[0] ?? null,
        }),
      );
    } finally {
      client.release();
    }
  });

  app.get("/v1/auth/dev/users", async (_req, reply) => {
    if (!hasDb() || !dbPool) {
      return reply.send(ok({ rows: [] }));
    }

    const client = await dbPool.connect();
    try {
      const result = await client.query<{
        user_id: string;
        username: string | null;
        display_name: string | null;
        is_creator: boolean;
      }>(
        `
        select
          u.id as user_id,
          cp.username,
          cp.display_name,
          (cp.creator_user_id is not null) as is_creator
        from users u
        left join creator_profiles cp on cp.creator_user_id = u.id
        order by u.created_at asc
        limit 200
      `,
      );

      return reply.send(
        ok({
          rows: result.rows.map((row) => ({
            user_id: row.user_id,
            username: row.username ?? `user_${row.user_id.slice(0, 8)}`,
            display_name: row.display_name,
            is_creator: row.is_creator,
          })),
        }),
      );
    } finally {
      client.release();
    }
  });

  app.post("/v1/auth/dev/switch", async (req, reply) => {
    const parsed = devSwitchBody.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send(fail("VALIDATION_ERROR", "Invalid switch payload"));
    }

    if (!hasDb() || !dbPool) {
      return reply.send(
        ok({
          user_id: parsed.data.user_id,
          header_name: "x-lifecast-user-id",
          header_value: parsed.data.user_id,
          switched: true,
        }),
      );
    }

    const client = await dbPool.connect();
    try {
      const exists = await client.query<{ exists: boolean }>(
        `select exists(select 1 from users where id = $1) as exists`,
        [parsed.data.user_id],
      );
      if (!exists.rows[0]?.exists) {
        return reply.code(404).send(fail("RESOURCE_NOT_FOUND", "User not found"));
      }

      return reply.send(
        ok({
          user_id: parsed.data.user_id,
          header_name: "x-lifecast-user-id",
          header_value: parsed.data.user_id,
          switched: true,
        }),
      );
    } finally {
      client.release();
    }
  });
}
