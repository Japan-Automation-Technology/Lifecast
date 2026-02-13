import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";

process.env.LIFECAST_DISABLE_DOTENV = "1";
process.env.LIFECAST_DATABASE_URL = "";
process.env.LIFECAST_STRIPE_WEBHOOK_SECRET = "";

const { buildApp } = await import("./app.js");

function stripeSignature(payload: Record<string, unknown>, secret: string, timestamp = "1700000000") {
  const signed = `${timestamp}.${JSON.stringify(payload)}`;
  const digest = createHmac("sha256", secret).update(signed, "utf8").digest("hex");
  return `t=${timestamp},v1=${digest}`;
}

test("supports prepare -> confirm -> webhook -> succeeded", async () => {
  const app = await buildApp();
  try {
    const projectId = "11111111-1111-1111-1111-111111111111";
    const planId = "22222222-2222-2222-2222-222222222221";

    const prepare = await app.inject({
      method: "POST",
      url: `/v1/projects/${projectId}/supports/prepare`,
      headers: { "idempotency-key": "prepare-1" },
      payload: { plan_id: planId, quantity: 1 },
    });
    assert.equal(prepare.statusCode, 200);
    const prepareBody = prepare.json();
    assert.equal(prepareBody.result.support_status, "prepared");

    const supportId = prepareBody.result.support_id as string;

    const confirm = await app.inject({
      method: "POST",
      url: `/v1/supports/${supportId}/confirm`,
      headers: { "idempotency-key": "confirm-1" },
      payload: {
        provider: "stripe",
        provider_session_id: "sess_123",
        return_status: "success",
      },
    });
    assert.equal(confirm.statusCode, 200);
    assert.equal(confirm.json().result.support_status, "pending_confirmation");

    const webhook = await app.inject({
      method: "POST",
      url: "/v1/payments/webhooks/stripe",
      headers: { "stripe-signature": "t=1,v1=test" },
      payload: {
        id: "evt_1",
        type: "checkout.session.completed",
        support_id: supportId,
      },
    });
    assert.equal(webhook.statusCode, 200);
    assert.equal(webhook.json().result.processed, true);

    const support = await app.inject({
      method: "GET",
      url: `/v1/supports/${supportId}`,
    });
    assert.equal(support.statusCode, 200);
    assert.equal(support.json().result.support_status, "succeeded");
  } finally {
    await app.close();
  }
});

test("idempotency key payload mismatch returns STATE_CONFLICT", async () => {
  const app = await buildApp();
  try {
    const projectId = "11111111-1111-1111-1111-111111111111";
    const planId = "22222222-2222-2222-2222-222222222221";
    const idempotencyKey = "prepare-conflict-key";

    const first = await app.inject({
      method: "POST",
      url: `/v1/projects/${projectId}/supports/prepare`,
      headers: { "idempotency-key": idempotencyKey },
      payload: { plan_id: planId, quantity: 1 },
    });
    assert.equal(first.statusCode, 200);

    const second = await app.inject({
      method: "POST",
      url: `/v1/projects/${projectId}/supports/prepare`,
      headers: { "idempotency-key": idempotencyKey },
      payload: { plan_id: planId, quantity: 2 },
    });
    assert.equal(second.statusCode, 409);
    assert.equal(second.json().error.code, "STATE_CONFLICT");
  } finally {
    await app.close();
  }
});

test("stripe webhook duplicate event is deduped", async () => {
  const app = await buildApp();
  try {
    const payload = {
      id: "evt_duplicate_1",
      type: "checkout.session.completed",
    };
    const first = await app.inject({
      method: "POST",
      url: "/v1/payments/webhooks/stripe",
      headers: { "stripe-signature": "t=1,v1=test" },
      payload,
    });
    assert.equal(first.statusCode, 200);
    assert.equal(first.json().result.deduped, false);

    const second = await app.inject({
      method: "POST",
      url: "/v1/payments/webhooks/stripe",
      headers: { "stripe-signature": "t=1,v1=test" },
      payload,
    });
    assert.equal(second.statusCode, 200);
    assert.equal(second.json().result.deduped, true);
  } finally {
    await app.close();
  }
});

test("stripe webhook rejects invalid signature when secret is configured", async () => {
  const prev = process.env.LIFECAST_STRIPE_WEBHOOK_SECRET;
  process.env.LIFECAST_STRIPE_WEBHOOK_SECRET = "whsec_test_secret";
  const app = await buildApp();
  try {
    const payload = {
      id: "evt_sig_invalid",
      type: "checkout.session.completed",
    };
    const res = await app.inject({
      method: "POST",
      url: "/v1/payments/webhooks/stripe",
      headers: { "stripe-signature": "t=1700000000,v1=invalid" },
      payload,
    });
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error.code, "VALIDATION_ERROR");
  } finally {
    process.env.LIFECAST_STRIPE_WEBHOOK_SECRET = prev;
    await app.close();
  }
});

test("stripe webhook accepts valid signature and processes refund transition", async () => {
  const prev = process.env.LIFECAST_STRIPE_WEBHOOK_SECRET;
  process.env.LIFECAST_STRIPE_WEBHOOK_SECRET = "whsec_test_secret";
  const app = await buildApp();
  try {
    const projectId = "11111111-1111-1111-1111-111111111111";
    const planId = "22222222-2222-2222-2222-222222222221";

    const prepare = await app.inject({
      method: "POST",
      url: `/v1/projects/${projectId}/supports/prepare`,
      headers: { "idempotency-key": "prepare-refund-1" },
      payload: { plan_id: planId, quantity: 1 },
    });
    const supportId = prepare.json().result.support_id as string;

    await app.inject({
      method: "POST",
      url: `/v1/supports/${supportId}/confirm`,
      headers: { "idempotency-key": "confirm-refund-1" },
      payload: { provider: "stripe", provider_session_id: "sess_refund_1", return_status: "success" },
    });

    const successPayload = { id: "evt_refund_pre_success", type: "checkout.session.completed", support_id: supportId };
    await app.inject({
      method: "POST",
      url: "/v1/payments/webhooks/stripe",
      headers: { "stripe-signature": stripeSignature(successPayload, "whsec_test_secret") },
      payload: successPayload,
    });

    const refundPayload = { id: "evt_refund_1", type: "charge.refunded", support_id: supportId };
    const refund = await app.inject({
      method: "POST",
      url: "/v1/payments/webhooks/stripe",
      headers: { "stripe-signature": stripeSignature(refundPayload, "whsec_test_secret") },
      payload: refundPayload,
    });
    assert.equal(refund.statusCode, 200);
    assert.equal(refund.json().result.processed, true);

    const support = await app.inject({
      method: "GET",
      url: `/v1/supports/${supportId}`,
    });
    assert.equal(support.statusCode, 200);
    assert.equal(support.json().result.support_status, "refunded");
  } finally {
    process.env.LIFECAST_STRIPE_WEBHOOK_SECRET = prev;
    await app.close();
  }
});

test("events ingest stores valid events and rejects invalid payload to DLQ path", async () => {
  const app = await buildApp();
  try {
    const validEvent = {
      event_name: "support_button_tapped",
      event_id: "3c2f6585-2b92-4c8b-b2e1-76263a6a7a22",
      event_time: new Date().toISOString(),
      anonymous_id: "anon-1",
      session_id: "sess-1",
      client_platform: "ios",
      app_version: "0.1.0",
      attributes: {
        video_id: "vid-1",
        project_id: "11111111-1111-1111-1111-111111111111",
      },
    };

    const invalidEvent = {
      event_name: "payment_succeeded",
      event_id: "4bb8d08f-1111-4444-9999-df3f842cb8f2",
      event_time: new Date().toISOString(),
      anonymous_id: "anon-2",
      session_id: "sess-2",
      client_platform: "android",
      app_version: "0.1.0",
      attributes: {
        project_id: "11111111-1111-1111-1111-111111111111",
      },
    };

    const res = await app.inject({
      method: "POST",
      url: "/v1/events/ingest",
      payload: { events: [validEvent, invalidEvent] },
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().result.accepted, 1);
    assert.equal(res.json().result.rejected, 1);
  } finally {
    await app.close();
  }
});

test("analytics and ops endpoints return 200 envelopes", async () => {
  const app = await buildApp();
  try {
    const funnel = await app.inject({
      method: "GET",
      url: "/v1/analytics/funnel-daily?limit=10",
    });
    assert.equal(funnel.statusCode, 200);
    assert.ok(Array.isArray(funnel.json().result.rows));

    const kpi = await app.inject({
      method: "GET",
      url: "/v1/analytics/kpi-daily?limit=10",
    });
    assert.equal(kpi.statusCode, 200);
    assert.ok(Array.isArray(kpi.json().result.rows));

    const ops = await app.inject({
      method: "GET",
      url: "/v1/ops/queues",
    });
    assert.equal(ops.statusCode, 200);
    assert.equal(typeof ops.json().result.outbox.pending, "number");
  } finally {
    await app.close();
  }
});
