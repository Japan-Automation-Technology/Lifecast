import { createHash } from "node:crypto";
import { dbPool, hasDb } from "./store/db.js";

type JsonObject = Record<string, unknown>;

interface StoredResponse {
  statusCode: number;
  payload: JsonObject;
}

const memoryStore = new Map<string, { fingerprint: string; response: StoredResponse }>();

function keyFor(routeKey: string, idempotencyKey: string) {
  return `${routeKey}:${idempotencyKey}`;
}

export function requestFingerprint(method: string, routeKey: string, body: unknown) {
  return createHash("sha256")
    .update(`${method}:${routeKey}:${JSON.stringify(body ?? {})}`)
    .digest("hex");
}

export async function getStoredIdempotentResponse(routeKey: string, idempotencyKey: string) {
  const cacheKey = keyFor(routeKey, idempotencyKey);

  if (!hasDb() || !dbPool) {
    return memoryStore.get(cacheKey) ?? null;
  }

  const result = await dbPool.query<{
    request_fingerprint: string;
    response_status: number;
    response_body: JsonObject;
  }>(
    `
      select request_fingerprint, response_status, response_body
      from api_idempotency_keys
      where route_key = $1 and idempotency_key = $2 and expires_at > now()
    `,
    [routeKey, idempotencyKey],
  );

  if (!result.rowCount) {
    return null;
  }

  const row = result.rows[0];
  return {
    fingerprint: row.request_fingerprint,
    response: {
      statusCode: Number(row.response_status),
      payload: row.response_body ?? {},
    },
  };
}

export async function storeIdempotentResponse(input: {
  routeKey: string;
  idempotencyKey: string;
  fingerprint: string;
  statusCode: number;
  payload: JsonObject;
}) {
  const cacheKey = keyFor(input.routeKey, input.idempotencyKey);

  if (!hasDb() || !dbPool) {
    memoryStore.set(cacheKey, {
      fingerprint: input.fingerprint,
      response: { statusCode: input.statusCode, payload: input.payload },
    });
    return;
  }

  await dbPool.query(
    `
      insert into api_idempotency_keys (
        route_key, idempotency_key, request_fingerprint, response_status, response_body
      )
      values ($1, $2, $3, $4, $5::jsonb)
      on conflict (route_key, idempotency_key)
      do update set
        request_fingerprint = excluded.request_fingerprint,
        response_status = excluded.response_status,
        response_body = excluded.response_body
    `,
    [
      input.routeKey,
      input.idempotencyKey,
      input.fingerprint,
      input.statusCode,
      JSON.stringify(input.payload),
    ],
  );
}
