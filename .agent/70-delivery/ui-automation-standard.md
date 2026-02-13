# UI Automation Standard (Appium First)

Purpose:
- Prevent regressions where UI-affecting changes are reported complete without simulator-level verification.
- Make Appium-based UI checks the default execution gate for iOS/Android work.

## Mandatory rule

For any task that changes mobile UI behavior, navigation, or user-visible state:
1. Run Appium-based UI verification before reporting completion.
2. Attach evidence:
   - executed command(s)
   - pass/fail checkpoints
   - at least one screenshot path
3. If Appium cannot run, stop and report blocked status with concrete reason.
   - Fallback checks (e.g., `simctl` screenshot only) are allowed only with explicit block note.

## Scope that requires Appium verification

- New screens or tab changes
- State machine UX changes (upload/payment/checkout/result)
- Navigation path changes
- Button/gesture/interaction changes
- Error-message and retry UX changes

## Minimum iOS checklist (per UI-affecting task)

1. Confirm capability/runtime match before session start.
   - `LIFECAST_CAPABILITIES_CONFIG` points to current target (example: iPhone 17 Pro / iOS 26.2).
   - `xcrun simctl list devices` includes the capability `appium:udid`.
2. Launch simulator and app.
3. Execute target user flow end-to-end (the changed path) via script when available.
   - `pnpm -C /Users/takeshi/Desktop/lifecast smoke:ios:appium`
   - `node /Users/takeshi/Desktop/lifecast/scripts/appium/ios-upload-reset-screens.mjs`
4. Verify at least 3 key assertions from spec.
5. Capture screenshot(s) of final/critical states.
6. Record outcome in task summary.

Evidence format (example):
- `Appium flow`: pass
- `Assertions`: Create tab shown, Start Upload tap works, state reaches Processing
- `Screenshot`: `/Users/takeshi/Desktop/lifecast/.tmp/ios-create-processing.png`

## Operational command baseline

- Backend:
  - `pnpm -C /Users/takeshi/Desktop/lifecast dev:backend`
- Video worker (when upload flow is tested):
  - `pnpm -C /Users/takeshi/Desktop/lifecast dev:backend:worker:video-processing`
- Appium MCP server relies on:
  - `LIFECAST_CAPABILITIES_CONFIG`
  - `~/.codex/config.toml` `[mcp_servers.appium-mcp]`
- Fallback/portable Appium client command (no MCP tool wiring required):
  - `pnpm -C /Users/takeshi/Desktop/lifecast smoke:ios:appium`
  - script: `/Users/takeshi/Desktop/lifecast/scripts/appium/ios-smoke.mjs`
  - requires Appium server up at `http://127.0.0.1:4723`:
    - `appium server -p 4723` (or equivalent)

## Definition of done addendum (UI tasks)

A UI task is **not done** unless Appium verification evidence is present.

## Notes for future agents

- Do not rely only on unit tests/typechecks for UI changes.
- Do not claim simulator behavior unless you actually validated it.
- If environment is unstable (e.g., appium cache/runtime issue), report the blocker and the exact command/log.
- If Appium session used old capability/runtime, treat results as invalid and rerun after capability fix.

Last updated: 2026-02-13
