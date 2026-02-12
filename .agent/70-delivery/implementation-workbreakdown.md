# Implementation Work Breakdown (Native iOS + Native Android)

Purpose:
- Define concrete ownership and delivery order for separate iOS/Android apps with one shared backend contract.

Execution model:
- Two native clients built independently.
- One backend contract source of truth.
- Shared release gate is contract and flow parity, not code parity.

## Team lanes

### iOS lane (Swift)
- App shell, auth, onboarding, and session handling.
- Vertical video feed player and interaction UI.
- Support flow UI:
  - support tap
  - confirmation card
  - plan selection
  - checkout handoff and return handling
- Creator flow UI:
  - project creation
  - plan creation (max 3)
  - upload workflow with resumable state UX
- Social UI:
  - follow
  - comment
  - like
  - share
  - supporter badge display
- Notification handling and deep links.
- Error mapping UI for payment and upload failures.

### Android lane (Kotlin)
- Same feature parity as iOS lane with platform-native architecture.
- Background upload reliability behavior using platform job constraints.
- Checkout handoff and resume parity with iOS behavior.
- Event emission parity with backend contract.

### Backend lane
- Auth, profile, creator verification, and project lifecycle APIs.
- Plan, support, refund, and settlement orchestration.
- Payment webhook reconciliation and idempotent finalization.
- Accounting journal write path and derived balance/project views.
- Dispute lifecycle handling and recovery workflow.
- Moderation/report/stop/appeal APIs and audit logging.
- Analytics ingestion validation and event quality controls.

### Data and analytics lane
- Event contract governance.
- Funnel tables and KPI materialization.
- Monitoring for event drops, schema drift, and delayed ingestion.

## Delivery sequence (implementation order)
1. Contract freeze:
   - API request/response schemas
   - Error code taxonomy
   - Analytics event schema
2. Thin vertical slice:
   - video watch -> support tap -> checkout reach -> payment success callback
3. Settlement and accounting:
   - all-or-nothing state transition
   - refund path
   - payout eligibility state
4. Trust and operations:
   - project stop
   - 72-hour appeal path
   - moderation evidence logging
5. Upload robustness:
   - resumable uploads
   - processing timeout fallback
   - retry UX
6. Hardening:
   - idempotency tests
   - reconciliation checks
   - monitoring and alert thresholds

## Cross-platform parity checklist
- Same field validation rules for project and plan forms.
- Same support flow steps and blocking conditions.
- Same event names and required payload keys.
- Same error code to user-message mapping.
- Same policy copy for refund and cancellation windows.

## Release gates
- Gate A (Alpha): end-to-end support success from feed in both clients.
- Gate B (Ops): stop/appeal and dispute logging operational.
- Gate C (Beta): funnel and settlement metrics stable for 7 consecutive days.

Last updated: 2026-02-12
