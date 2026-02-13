# M1 iOS UI Verification

## Preconditions
- Backend running on `http://localhost:8080`
- Video worker running for upload completion:
  - `pnpm -C /Users/takeshi/Desktop/lifecast dev:backend:worker:video-processing`
- At least one sample project/plan exists in backend seed

## 1) Code-level sanity check
Run:
```bash
cd /Users/takeshi/Desktop/lifecast/apps/ios
xcrun swiftc -typecheck LifeCastAPIClient.swift SupportFlowDemoView.swift
```
Expected:
- No errors

## 2) UI behavior checks (Xcode preview or app root)
Use `SupportFlowDemoView` as the root view and verify these points.

### Feed / navigation
- Bottom tabs are exactly: `Home`, `Discover`, `Create`, `Me`
- `Home` opens with `For You` selected
- Vertical swipe (drag up/down) moves to next/previous project card

### Feed actions
- Right rail shows `Support`, `Like`, `Comment`, `Share`
- `Support` opens flow: `Plan Select -> Confirm -> Checkout -> Result`
- If card is already supported, button label is `Supported`

### Funding display
- Bottom block shows: `remaining days`, `min plan price`, `progress bar`, and `% + amount pair`
- Over 100% project keeps bar full and uses exceeded color

### Comment / share
- Comment opens bottom sheet
- Supporter comments are listed first with `SUPPORTER` badge
- Share sheet has only `Export video` and `Copy link`

### Profile / project
- Tapping `@username` opens creator profile
- Profile shows support relationship marker (`Supported`)
- `Me` tab has `Posted`, `Liked`, `Project`
- `Project` tab has info/progress/milestones and `Support` button

### Create / upload (iOS-003 baseline)
- Open `Create` tab
- Tap `Start Upload`
- Confirm state transitions:
  - `CREATED`
  - `UPLOADING`
  - `PROCESSING`
  - `READY` or `FAILED`
- Confirm upload session id is shown during flow

## 3) Payment flow API check from UI
- In support flow, press `Complete payment`
- Expected result status eventually becomes canonical `succeeded` or `refunded`
- If backend is unavailable, result should show `failed` with error text
