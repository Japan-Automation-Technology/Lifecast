# iOS App (Native)

Planned native Swift client for LifeCast.

Immediate build order:
1. Auth/session shell.
2. Feed + support CTA flow.
3. Checkout return handling + canonical support polling.
4. Upload state machine UX.

Contract dependencies:
- `packages/contracts/openapi/openapi.yaml`
- `packages/contracts/events/event-contract-v1.md`

Implemented starter:
- `LifeCastAPIClient.swift`
  - `prepareSupport`
  - `confirmSupport`
  - `getSupport`
  - `createUploadSession`
- `SupportFlowDemoView.swift`
  - Demo UI for prepare/confirm/status polling against local backend
