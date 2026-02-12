# Frozen Decisions

These are current fixed decisions and should be treated as constraints unless explicitly changed.

## Market and positioning
- Initial domain: toC creative process-economy projects.
- Priority categories: game and hardware development.
- Supporter mindset priority: "cheering" first.

## Funding model
- Product type: purchase-style crowdfunding (not investment product).
- MVP support type: return-based support only.
- Future option: no-return support and supporter-only content.
- Store policy boundary for MVP: support is limited to physical return/reward outcomes.
- Funding mode: all-or-nothing only.
- Payout model: creator receives funds in one lump sum after success conditions.

## Fees and payment
- Platform fee (temporary fixed): 15%.
- Payment processing fee burden: creator.
- Refund policy baseline:
  - If goal not reached: automatic full refund to supporter principal.
  - Platform fee is not refunded.
  - Payment processor actual cost may be non-refundable.
  - Allow cancellation request window: 48 hours after support completion.
  - After window: no cancellation by default, with explicit project-level exceptions.
- Checkout strategy (MVP): external payment flow with Apple Pay support to reduce friction.
- Payout timing default (MVP):
  - next-business-day payout execution after successful campaign close
  - target settlement within 2 business days
  - no rolling reserve in MVP

## Trust and compliance
- KYC and anti-social checks required in full model.
- MVP minimum: simplified identity verification before project publication.
- Public policy stance: strict, explicit, and log-driven operations.
- High-trust report auto-review trigger default:
  - trust-weighted score >= 5.0 within 24 hours and at least 3 unique reporters

## Accounting and settlement
- Ledger implementation: append-only accounting journal with derived balance views.
- Do not use full event sourcing as accounting source of truth for MVP.
- Dispute and chargeback flows must be journaled from day one, including:
  - dispute opened
  - dispute won/lost
  - post-payout recovery failure and loss allocation

## Video platform and reliability
- Initial video infrastructure: managed video platform (Cloudflare Stream baseline).
- Upload flow uses resumable/chunked sessions with idempotent retries.
- Upload/session state machine is required:
  - created -> uploading -> processing -> ready | failed
- Duplicate ingest prevention uses session identity plus content hash.

## Project and feed UX
- Project page required basics: goal amount, deadline, minimum plan summary.
- Video card visible metadata: days left and progress bar.
- Support flow:
  - Video -> Support button -> Confirm card (goal, estimated delivery, prototype status)
  - Plan selection -> Payment
- No mandatory episodic structure in MVP.

## Ranking and analytics
- Primary ranking business objective:
  - support conversion rate x average support amount x repeat support rate.
- Primary metric: support conversion based on payment success event only.
- Funnel event sequence (must log):
  - video_watch_completed
  - support_button_tapped
  - plan_selected
  - checkout_page_reached
  - payment_succeeded
- Event governance default:
  - backend/data lead owns contract and semantic versioning flow

## MVP must-have
- Vertical short-video feed.
- Project creation.
- Plan creation (max 3 for MVP).
- Support checkout (external payment + Apple Pay).
- All-or-nothing auto-refund logic.
- Likes, comments, shares.
- Account creation, follow.
- Supporter badge.
- Supported projects list on supporter profile.
- Email/phone verification.
- Creator ID document upload.
- Project stop capability.
- Project progress display updates.
- Basic notifications.
- User activity and conversion logging.
- Upload recovery UX for network interruption and processing failure.
- Payment failure messaging mapped to processor error categories.

## Explicitly out of MVP
- Long-form video.
- Live streaming.
- Direct messaging.
- Polling/voting features.
- Supporter-only exclusive content.
- Advanced analytics dashboard.
- Early bird / limited quantity mechanics.
- Highly optimized recommendation system.

Last updated: 2026-02-12
