# Domain Model (MVP)

Core entities:
- User
- CreatorProfile
- Project
- ProjectPlan
- VideoPost
- VideoUploadSession
- SupportTransaction
- RefundRecord
- LedgerAccount
- JournalEntry
- JournalLine
- DisputeCase
- Comment
- Follow
- SupporterBadgeState
- ModerationReport
- ModerationAction
- AppealCase

Relationships (high-level):
- User can support many projects via SupportTransaction.
- Project has many ProjectPlans and VideoPosts.
- VideoUploadSession links creator upload attempts to finalized VideoPost artifacts.
- SupportTransaction links User, Project, and selected ProjectPlan.
- JournalEntry and JournalLine represent immutable accounting truth for support, payout, refund, and dispute states.
- DisputeCase references SupportTransaction and drives journaled recovery/loss outcomes.
- ModerationAction may target Project or User and may create AppealCase.

Last updated: 2026-02-12
