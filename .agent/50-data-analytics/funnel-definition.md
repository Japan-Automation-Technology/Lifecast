# Funnel Definition

Canonical conversion:
- Support conversion is defined strictly as `payment_succeeded`.

MVP funnel steps:
1. `video_watch_completed`
2. `support_button_tapped`
3. `plan_selected`
4. `checkout_page_reached`
5. `payment_succeeded`

Interpretation rules:
- Clicks and plan selections are intent signals, not conversion.
- Payment success is the only revenue-valid conversion event.
- Funnel drop-off between steps is required for optimization and ranking improvement.

Last updated: 2026-02-12
