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

Implemented:
- `LifeCast/LifeCast/LifeCastAPIClient.swift`
  - `prepareSupport`
  - `confirmSupport`
  - `getSupport`
  - `createUploadSession`
  - `completeUploadSession`
  - `getUploadSession`
- `LifeCast/LifeCast/SupportFlowDemoView.swift`
  - M1 wireflow demo shell:
    - 4 tabs (`Home`, `Discover`, `Create`, `Me`)
    - Feed with `For You` default
    - Vertical swipe gesture to switch feed cards
    - Right rail: `Support`, `Like`, `Comment`, `Share`
    - Support flow modal: `Plan Select -> Confirm -> Checkout -> Result`
    - Creator profile transition from `@username`
    - Comment bottom sheet with supporter-first sorting and badge
    - Share sheet constrained to `Export video` / `Copy link`
    - Me tab with `Posted` / `Liked` / `Project` tabs
    - Project page section with milestones + support CTA
    - Canonical support polling after checkout simulation
    - Create tab upload state machine (`created -> uploading -> processing -> ready|failed`)

Local typecheck command used:
- `xcrun swiftc -typecheck LifeCast/LifeCast/LifeCastAPIClient.swift LifeCast/LifeCast/SupportFlowDemoView.swift`
