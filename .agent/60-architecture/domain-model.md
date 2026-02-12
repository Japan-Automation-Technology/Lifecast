# Domain Model (MVP)

Core entities:
- User
- CreatorProfile
- Project
- ProjectPlan
- VideoPost
- SupportTransaction
- RefundRecord
- Comment
- Follow
- SupporterBadgeState
- ModerationReport
- ModerationAction
- AppealCase

Relationships (high-level):
- User can support many projects via SupportTransaction.
- Project has many ProjectPlans and VideoPosts.
- SupportTransaction links User, Project, and selected ProjectPlan.
- ModerationAction may target Project or User and may create AppealCase.

Last updated: 2026-02-12
