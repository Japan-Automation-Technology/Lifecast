# AGENTS.md

This file defines project-specific operating rules for any agent working in `/Users/takeshi/Desktop/lifecast`.

## 1) Source of Truth and Read Order

Always treat `.agent/` as the canonical product+engineering knowledge base.

Minimum required read order before substantial implementation:
1. `.agent/README.md`
2. `.agent/00-executive/one-page-brief.md`
3. `.agent/00-executive/frozen-decisions.md`
4. `.agent/40-mvp-spec/scope-in-out.md`
5. `.agent/60-architecture/api-contract-rules.md`
6. `.agent/50-data-analytics/event-contract-v1.md`
7. `.agent/70-delivery/implementation-workbreakdown.md`
8. `.agent/70-delivery/ui-automation-standard.md`

Then read deeper only for the active task.

## 2) Non-Negotiable Product Constraints

From frozen decisions and MVP scope:
- Product is purchase-style crowdfunding (not investment), all-or-nothing funding.
- MVP support type is return-based support only.
- Must-have MVP scope includes feed, project/plan creation (max 3 plans), support checkout, follow/like/comment/share, supporter badge, supported projects list, basic notifications, and core event logging.
- Out-of-scope MVP items (live, DM, long-form, etc.) must not be introduced silently.

If a task would change these constraints, do not improvise. Explicitly call out the conflict and require decision update.

## 3) Contract and Data Rules

API and event contracts are strict:
- Do not rely on undocumented backend behavior.
- Respect API response envelope and stable error-code handling.
- Use integer minor units for money and ISO-8601 UTC timestamps.
- Treat webhook-confirmed payment state as authoritative.
- Preserve event contract required fields and semantic meaning.

Any breaking contract change requires:
- versioning discipline,
- rollout plan,
- and decision-log update in `.agent/70-delivery/decision-log.md`.

## 4) UI/UX Implementation Rule

Do not gate capabilities by route origin when ownership is available.
- Example principle: destructive/self actions (like delete video) must be decided by ownership (`is my content`) rather than by whether user came from Me tab or another profile surface.

## 5) iOS UI Verification Policy (Important)

Appium evidence is required for UI-affecting tasks, but use the correct scripts:
- Preferred routine UI scripts:
  - `pnpm -C /Users/takeshi/Desktop/lifecast smoke:ios:upload-profile`
  - `pnpm -C /Users/takeshi/Desktop/lifecast smoke:ios:posted-feed`
- `smoke:ios:appium` is deprecated and intentionally fails.
- Create-tab upload-start smoke is explicit-only:
  - `pnpm -C /Users/takeshi/Desktop/lifecast smoke:ios:create-upload`

When reporting UI work, include:
- commands run,
- assertion summary,
- screenshot absolute paths.

## 6) Delivery Hygiene

- Keep changes scoped and minimal.
- Prefer updating existing docs/contracts over introducing parallel sources.
- When a decision or policy changes, reflect it in `.agent/70-delivery/decision-log.md` and relevant spec files.

