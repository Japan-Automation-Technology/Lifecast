# iOS App (Native)

Planned native Swift client for Lifecast.

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

Auth setup (Email/Password + Google + Apple via Supabase):
- Backend env required:
  - `LIFECAST_SUPABASE_URL`
  - `LIFECAST_SUPABASE_ANON_KEY`
  - `LIFECAST_AUTH_REDIRECT_URL=lifecast://auth/callback`
- iOS URL scheme:
  - `lifecast` is registered in project build settings.
- OAuth flow:
  - iOS opens `/v1/auth/oauth/url?provider=google|apple`.
  - Supabase redirects back to `lifecast://auth/callback#access_token=...&refresh_token=...`.
  - `LifeCastApp` handles callback and persists tokens in `UserDefaults`.

Local typecheck command used:
- `xcrun swiftc -typecheck LifeCast/LifeCast/LifeCastAPIClient.swift LifeCast/LifeCast/SupportFlowDemoView.swift`

Appium smoke command policy:
- Use for profile/feed UI checks:
  - `pnpm -C /Users/takeshi/Desktop/lifecast smoke:ios:upload-profile`
  - `pnpm -C /Users/takeshi/Desktop/lifecast smoke:ios:posted-feed`
- Do not use `smoke:ios:appium` for normal UI verification.
- If and only if you intentionally validate the Create tab upload-start flow, run:
  - `pnpm -C /Users/takeshi/Desktop/lifecast smoke:ios:create-upload`

App Store naming notes:
- App icon/home-screen name is controlled by `PRODUCT_NAME` and `CFBundleDisplayName` (now `Lifecast`).
- Bundle ID is now set to `jp.lifecast.lifecast`. Make sure the matching App ID/provisioning profile exists in Apple Developer.
- The App Store listing name itself is managed in App Store Connect and must be updated there separately if still shown as `LifeCast`.
