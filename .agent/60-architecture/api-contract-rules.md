# API Contract Rules (v1)

Purpose:
- Prevent divergence between iOS and Android behavior by freezing backend-facing contracts early.

Contract governance:
- Backend owns canonical OpenAPI/JSON schema.
- Client teams must not infer undocumented behavior.
- Any breaking change requires:
  - explicit version bump
  - entry in `../70-delivery/decision-log.md`
  - rollout plan for both clients

## Contract shape requirements
- Every endpoint response includes:
  - `request_id`
  - `server_time`
  - `result` object on success
  - structured `error` object on failure
- Every mutating endpoint accepts idempotency key where retry is plausible.
- Monetary values use integer minor units (for example cents), never floating point.
- Timestamps use ISO-8601 UTC.

## Error taxonomy (minimum)
- `VALIDATION_ERROR`
- `AUTH_REQUIRED`
- `PERMISSION_DENIED`
- `RESOURCE_NOT_FOUND`
- `STATE_CONFLICT`
- `PAYMENT_FAILED`
- `PAYMENT_REQUIRES_ACTION`
- `PROJECT_STOPPED`
- `RATE_LIMITED`
- `INTERNAL_ERROR`

Client behavior rule:
- UI copy maps from stable error code, not raw gateway/provider message.

## Critical support lifecycle APIs
- `POST /supports/prepare`
  - validates project state and plan eligibility
  - returns checkout session metadata
- `POST /supports/confirm`
  - called after payment provider return
  - marks support as pending confirmation, not final success
- `POST /payments/webhooks`
  - final support status decided here through verified webhook events
- `GET /supports/{id}`
  - returns canonical state for client polling/reload

State authority:
- `payment_succeeded` is confirmed by backend webhook reconciliation only.
- Client redirect success must never be treated as final settlement.

## Upload APIs
- `POST /videos/uploads`
  - creates upload session and signed chunk endpoints
- `POST /videos/uploads/{id}/complete`
  - requests processing start
- `GET /videos/uploads/{id}`
  - exposes session status:
    - `created`
    - `uploading`
    - `processing`
    - `ready`
    - `failed`

Duplicate control:
- Upload completion call includes content hash metadata.
- Backend rejects duplicate finalized artifacts by policy.

Last updated: 2026-02-12
