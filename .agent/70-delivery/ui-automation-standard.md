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

1. Launch simulator and app.
2. Execute target user flow end-to-end (the changed path).
3. Verify at least 3 key assertions from spec.
4. Capture screenshot(s) of final/critical states.
5. Record outcome in task summary.

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

## Definition of done addendum (UI tasks)

A UI task is **not done** unless Appium verification evidence is present.

## Notes for future agents

- Do not rely only on unit tests/typechecks for UI changes.
- Do not claim simulator behavior unless you actually validated it.
- If environment is unstable (e.g., appium cache/runtime issue), report the blocker and the exact command/log.

Last updated: 2026-02-13
