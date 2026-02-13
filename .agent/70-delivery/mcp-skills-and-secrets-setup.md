# MCP, Skills, and Secrets Setup

Purpose:
- Prepare local environment so coding agents can execute faster with consistent context and up-to-date tool integrations.

Current local status (observed):
- MCP resource servers are not currently connected in this session (`list_mcp_resources` returned empty).
- Codex config includes a Playwright MCP server entry in `~/.codex/config.toml`.
- Only system skills are installed locally right now.

## Recommended MCP baseline

1. Keep `playwright` MCP enabled (already configured).
2. Add documentation/PM MCPs only if used by your workflow:
   - Notion MCP (if PRD/ops live in Notion)
   - Figma MCP (if UI is design-led)
   - Linear MCP (if backlog/tickets are in Linear)
3. Keep project-specific MCP servers minimal to avoid unnecessary auth and token surface area.
4. For mobile automation, use official `appium-mcp` package and keep Appium server/drivers preinstalled locally.
5. Treat Appium verification as mandatory for UI-affecting tasks (see `ui-automation-standard.md`).

## Codex MCP setup reference

- Official command path:
  - `codex mcp add <name> -- <command>`
  - then verify with `codex mcp list`
- Config file location:
  - `~/.codex/config.toml`

Current config targets:
- `context7`: `npx -y @upstash/context7-mcp@latest`
- `postgres`: `npx -y @modelcontextprotocol/server-postgres "$LIFECAST_DATABASE_URL"`
- `appium-mcp`: `CAPABILITIES_CONFIG="$LIFECAST_CAPABILITIES_CONFIG" npx -y appium-mcp@latest`
- `supabase`: `npx -y @supabase/mcp-server-supabase@latest --access-token "$LIFECAST_SUPABASE_ACCESS_TOKEN"`

## Supabase MCP setup

Required env var:
- `LIFECAST_SUPABASE_ACCESS_TOKEN`

Recommended token scope:
- Supabase Personal Access Token with minimum required project/database read/write permissions for development.

Verification:
- Ensure `LIFECAST_SUPABASE_ACCESS_TOKEN` is set via `launchctl getenv LIFECAST_SUPABASE_ACCESS_TOKEN`.
- Confirm Codex config has `[mcp_servers.supabase]` entry in `~/.codex/config.toml`.
- Restart Codex after any config change.

## Appium MCP prerequisites (Codex)

Host requirements before `appium-mcp` is usable:
- Node.js LTS (recommend Node 22.x for compatibility).
- Java JDK 17+ (Android automation path).
- Appium installed (`npm i -g appium`) and runnable (`appium --version`).
- Xcode + iOS simulator tools (for iOS automation).
- Android SDK + emulator + `ANDROID_HOME` / `ANDROID_SDK_ROOT` (for Android automation).

Recommended one-time checks:
- `node -v`
- `appium --version`
- `xcrun simctl list devices`
- `adb devices`

Note:
- If `npx appium-mcp@latest` fails with environment/shell errors, first normalize Node runtime to LTS and ensure global `appium` is installed and executable.
- On macOS with multiple Node installs, force PATH precedence (`/opt/homebrew/bin`) when launching MCP to avoid picking an older `/usr/local/bin/node`.
- If npx cache corruption causes `ENOTEMPTY`, run with isolated npm cache (for example `npm_config_cache=/tmp/lifecast-npm-cache`).

## Skills strategy (practical)

Recommended installs for this project:
- `openai-docs` for up-to-date OpenAI/Codex docs lookups.
- `figma` and `figma-implement-design` only if your design source is Figma.
- `security-threat-model` before beta launch hardening.

Notes:
- Skill listing script from `skill-installer` failed in this environment due local SSL certificate validation issue.
- A cached curated skill list exists at `~/.codex/vendor_imports/skills-curated-cache.json`.

## Secrets and API keys to prepare

Core runtime:
- `LIFECAST_DATABASE_URL` (PostgreSQL primary)
- `REDIS_URL` (queue/cache if used)
- `JWT_SIGNING_KEY`

MCP runtime:
- `LIFECAST_SUPABASE_ACCESS_TOKEN`
- `LIFECAST_CAPABILITIES_CONFIG`

Payments (Stripe Connect baseline):
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_CONNECT_CLIENT_ID` (if OAuth onboarding is used)
- `STRIPE_PUBLISHABLE_KEY` (mobile/web checkout initialization)

Video (Cloudflare Stream baseline):
- `CF_ACCOUNT_ID`
- `CF_STREAM_TOKEN` (or scoped API token with Stream permissions)
- `CF_STREAM_SIGNING_KEY` (if signed playback URLs are enabled)

Object storage and CDN (if separate from Stream uploads):
- `S3_BUCKET`
- `S3_REGION`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

Observability:
- `SENTRY_DSN`
- `SENTRY_AUTH_TOKEN` (CI/tooling use)

Communications:
- `SMTP_API_KEY` or provider key (SendGrid/Postmark/etc.)
- SMS/phone verify key (Twilio/etc.) if phone auth is required in MVP

Moderation and operations:
- Admin console auth secret
- Internal audit-log storage credentials

## Security handling rules

- Keep all secrets in a secrets manager (not in `.env` committed files).
- Rotate webhook secrets and API keys on role changes.
- Separate staging and production keys strictly.
- Restrict API token scopes to minimum required endpoints.

## Next actions before coding sprint

1. Finalize which MCP servers you actually use day-to-day.
2. Prepare staged secrets in 1Password/Vault/AWS Secrets Manager.
3. Run a one-time secret validation checklist in CI (presence + format, not raw value logging).

Last updated: 2026-02-12
