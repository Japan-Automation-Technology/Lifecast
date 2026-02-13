import { randomUUID } from "node:crypto";

const REQUIRED_FIELDS = [
  "event_name",
  "event_id",
  "event_time",
  "session_id",
  "client_platform",
  "app_version",
] as const;

const EVENT_ATTRIBUTES: Record<string, string[]> = {
  video_watch_completed: ["video_id", "project_id", "watch_duration_ms", "video_duration_ms"],
  support_button_tapped: ["video_id", "project_id"],
  plan_selected: ["project_id", "plan_id", "plan_price_minor", "currency"],
  checkout_page_reached: ["project_id", "plan_id", "checkout_session_id"],
  payment_succeeded: ["project_id", "plan_id", "support_id", "payment_provider", "amount_minor", "currency"],
};

export interface NormalizedEvent {
  event_name: string;
  event_id: string;
  event_time: string;
  user_id?: string;
  anonymous_id?: string;
  session_id: string;
  client_platform: "ios" | "android" | "server";
  app_version: string;
  attributes: Record<string, unknown>;
}

export interface EventValidationResult {
  ok: boolean;
  normalized?: NormalizedEvent;
  errors: string[];
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function baseAttributes(payload: Record<string, unknown>) {
  const reserved = new Set<string>([
    ...REQUIRED_FIELDS,
    "user_id",
    "anonymous_id",
    "attributes",
  ]);
  const attrs: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(payload)) {
    if (!reserved.has(key)) attrs[key] = value;
  }
  return attrs;
}

export function buildServerEvent(input: {
  eventName: string;
  userId?: string;
  anonymousId?: string;
  sessionId?: string;
  appVersion: string;
  attributes: Record<string, unknown>;
}): Record<string, unknown> {
  return {
    event_name: input.eventName,
    event_id: randomUUID(),
    event_time: new Date().toISOString(),
    user_id: input.userId,
    anonymous_id: input.anonymousId,
    session_id: input.sessionId ?? randomUUID(),
    client_platform: "server",
    app_version: input.appVersion,
    attributes: input.attributes,
  };
}

export function validateEventPayload(input: unknown): EventValidationResult {
  if (!isObject(input)) {
    return { ok: false, errors: ["payload must be an object"] };
  }

  const errors: string[] = [];
  for (const field of REQUIRED_FIELDS) {
    const value = input[field];
    if (typeof value !== "string" || value.length === 0) {
      errors.push(`missing or invalid ${field}`);
    }
  }

  const hasUserId = typeof input.user_id === "string" && input.user_id.length > 0;
  const hasAnonymousId = typeof input.anonymous_id === "string" && input.anonymous_id.length > 0;
  if (!hasUserId && !hasAnonymousId) {
    errors.push("either user_id or anonymous_id is required");
  }

  const platform = input.client_platform;
  if (platform !== "ios" && platform !== "android" && platform !== "server") {
    errors.push("client_platform must be ios/android/server");
  }

  const eventName = typeof input.event_name === "string" ? input.event_name : "";
  const requiredAttrs = EVENT_ATTRIBUTES[eventName];
  const attrsFromPayload =
    isObject(input.attributes) ? (input.attributes as Record<string, unknown>) : baseAttributes(input);

  if (!requiredAttrs) {
    errors.push(`unsupported event_name: ${eventName || "unknown"}`);
  } else {
    for (const key of requiredAttrs) {
      const value = attrsFromPayload[key];
      if (value === undefined || value === null || value === "") {
        errors.push(`missing required attribute: ${key}`);
      }
    }
  }

  if (errors.length > 0) {
    return { ok: false, errors };
  }

  return {
    ok: true,
    errors: [],
    normalized: {
      event_name: eventName,
      event_id: String(input.event_id),
      event_time: String(input.event_time),
      user_id: hasUserId ? String(input.user_id) : undefined,
      anonymous_id: hasAnonymousId ? String(input.anonymous_id) : undefined,
      session_id: String(input.session_id),
      client_platform: input.client_platform as "ios" | "android" | "server",
      app_version: String(input.app_version),
      attributes: attrsFromPayload,
    },
  };
}
