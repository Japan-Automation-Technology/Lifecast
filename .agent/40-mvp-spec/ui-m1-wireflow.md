# M1 UI Wireflow (Frozen)

Purpose:
- Fix M1 mobile UI behavior before implementation so feed/support UX does not drift.

## Global nav
- Bottom tabs are 4 items in M1:
  - `Home`
  - `Discover`
  - `Create`
  - `Me`
- No DM/Inbox tab in M1.

## Feed screen (TikTok-style)
- Top toggle:
  - `For You`
  - `Following`
- Initial tab is `For You`.
- Main interaction is vertical swipe.

Right action column order:
1. `Support` button (replaces profile-image slot style in TikTok layout)
2. `Like`
3. `Comment`
4. `Share`

Bottom metadata block:
- `@username` (tappable -> User page)
- Caption text
- Remaining days
- Progress bar
- Minimum plan price

Progress rules:
- Show percentage and amount pair: `42% (JPY 420,000 / JPY 1,000,000)`.
- Bar fill maxes at 100%.
- If funding > 100%, keep bar full and switch bar color to "goal exceeded" state.

## Support flow
- Entry points:
  - Feed `Support` button
  - Project page `Support` button
- Shared sequence:
  1. `Plan Select`
  2. `Confirm Card`
  3. `Checkout`
  4. `Result`

Return behavior:
- If support starts from feed:
  - Result close returns to same feed context (continue watching).
- If support starts from project page:
  - Result close returns to project page.

State label rules:
- If current user already supported a creator/project:
  - Show `Supported` state instead of `Support`.
- On creator/user pages, show support relationship marker similar to follow/following affordance.

## Comment sheet
- Opens as bottom sheet from feed.
- List order:
  1. Supporters first (with supporter badge)
  2. Then ranked by likes and recency
- Each comment can be liked.
- Composer is always available at bottom.

## Share sheet (M1)
- Only two actions:
  - Export video
  - Copy link
- Other share targets/actions are out of scope in M1.

## User page (Profile)
- Tabs:
  - Posted videos
  - Liked videos
  - Project page (only visible if user is a creator with project)
- Project page includes:
  - Project information
  - Progress
  - Support button

## Profile edit / settings
- Keep TikTok-like baseline structure for M1.
- No custom privacy model expansion in M1.

## Explicitly out of scope (M1 UI)
- DM/Inbox
- Live
- Long-form video UI
- Advanced sharing destinations
- Private liked-videos toggle

Last updated: 2026-02-13
