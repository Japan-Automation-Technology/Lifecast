import { createHmac } from "node:crypto";
import {
  DEV_PLAN_BASIC_ID,
  DEV_PROJECT_ID,
} from "../db/constants.js";
import { loadEnv } from "../env.js";

loadEnv();

const API_BASE_URL = process.env.LIFECAST_API_BASE_URL ?? "http://localhost:8080";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function makeStripeSignature(payload: Record<string, unknown>, secret: string, timestamp = `${Math.floor(Date.now() / 1000)}`) {
  const signedPayload = `${timestamp}.${JSON.stringify(payload)}`;
  const digest = createHmac("sha256", secret).update(signedPayload, "utf8").digest("hex");
  return `t=${timestamp},v1=${digest}`;
}

async function postJson(path: string, body: Record<string, unknown>, headers: Record<string, string> = {}) {
  const res = await fetch(`${API_BASE_URL}${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify(body),
  });
  const json = (await res.json()) as Record<string, unknown>;
  return { status: res.status, body: json };
}

async function getJson(path: string) {
  const res = await fetch(`${API_BASE_URL}${path}`);
  const json = (await res.json()) as Record<string, unknown>;
  return { status: res.status, body: json };
}

async function main() {
  const secret = process.env.LIFECAST_STRIPE_WEBHOOK_SECRET;
  assert(secret && secret.startsWith("whsec_"), "LIFECAST_STRIPE_WEBHOOK_SECRET is required");

  const prepare = await postJson(`/v1/projects/${DEV_PROJECT_ID}/supports/prepare`, {
    plan_id: DEV_PLAN_BASIC_ID,
    quantity: 1,
  }, { "idempotency-key": `smoke-prepare-${Date.now()}` });
  assert(prepare.status === 200, `prepare failed: ${prepare.status}`);

  const prepareResult = (prepare.body.result as Record<string, unknown> | undefined) ?? {};
  const supportId = prepareResult.support_id as string | undefined;
  assert(supportId, "prepare result missing support_id");

  const confirm = await postJson(`/v1/supports/${supportId}/confirm`, {
    provider: "stripe",
    provider_session_id: `smoke-session-${Date.now()}`,
    return_status: "success",
  }, { "idempotency-key": `smoke-confirm-${Date.now()}` });
  assert(confirm.status === 200, `confirm failed: ${confirm.status}`);

  const webhookPayload = {
    id: `evt_smoke_${Date.now()}`,
    type: "checkout.session.completed",
    support_id: supportId,
  };
  const webhook = await postJson("/v1/payments/webhooks/stripe", webhookPayload, {
    "stripe-signature": makeStripeSignature(webhookPayload, secret),
  });
  assert(webhook.status === 200, `webhook failed: ${webhook.status}`);

  const support = await getJson(`/v1/supports/${supportId}`);
  assert(support.status === 200, `get support failed: ${support.status}`);
  const supportStatus = ((support.body.result as Record<string, unknown> | undefined) ?? {}).support_status;
  assert(supportStatus === "succeeded", `expected succeeded, got ${String(supportStatus)}`);

  const journal = await getJson(`/v1/journal/entries?support_id=${supportId}`);
  assert(journal.status === 200, `get journal failed: ${journal.status}`);
  const entries = (((journal.body.result as Record<string, unknown> | undefined) ?? {}).entries as unknown[] | undefined) ?? [];
  const hasSupportHold = entries.some((entry) => (entry as Record<string, unknown>).entry_type === "support_hold");
  assert(hasSupportHold, "missing support_hold journal entry");

  console.log("[smoke] payment flow passed", { supportId, supportStatus, entries: entries.length });
}

main().catch((error) => {
  console.error("[smoke] payment flow failed", error);
  process.exit(1);
});
