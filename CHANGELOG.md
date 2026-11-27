# Changelog

## 1.2.0+4 — 2026-11-27

### Added
- **Public Live Tab**: Added a 4th `Live` navigation tab (`Matches · Live · Teams · Tournaments`) with `All`, `Matches`, `Tournaments`, and `Recent` filters, live tournament strip, broadcast match cards with last-ball pills (`4`, `6`, `W`), quiet-hours recent results fallback, and an ambient live dot on the nav bar.
- **Unlisted-by-Default Go Live Controls**: Added a consistent `Show on Live tab` / `Go live` toggle across Quick Match setup, Scoring Match Options (with `PUBLIC` header pill), Home match cards, Create Tournament, and the Tournament Detail owner visibility bar (cascading visibility to fixtures).
- **CQRS Live Summary Architecture**: Added `public.match_live_summary`, `get_live_feed`, `get_public_live_count`, and `set_tournament_visibility` RPCs with automatic zombie-match freshness gating (4h limited-overs / 24h Test) and tournament quality gating (2+ teams & 14-day/active-window freshness).

### Changed
- **Incremental Live Scorecards**: Upgraded `ScorecardScreen` to apply incoming Supabase Realtime `ball_events` `INSERT` payloads directly in memory (`0` extra database reads per ball), falling back to full bundle fetch on edits/voids or match rule changes.
- **Smoother Tournament Creation**: Kept the New Tournament sheet open with an inline `Creating tournament…` button loader while saving & syncing, updating `My Tournaments` immediately without a pop-in delay.

### Fixed
- Refreshed `get_live_match_bundle` and hardened `pullRemoteMatchToLocal` so pulling a remote match never resets a match's `public` visibility or `venue`.

## 1.1.0+3 — 2026-11-27

### Added
- Live team roster sync via scoped Supabase Realtime on Team Detail, background pull on open and app resume, pull-to-refresh on Overview & Players tabs, and batched roster sync on cold start and Home refresh.
- Multi-team player spot linking in Edit Profile (`Linked team spots`) with per-team pickers so players belonging to multiple squads can link each club independently without name collisions.
- Google Play Flexible In-App Updates (native half-page Play Store update prompt with background download and in-app Restart banner).
- Firebase Crashlytics integration for production crash reporting and automatic R8 symbol mapping upload.

### Fixed
- Prevented routine owner squad syncs from overwriting remote teammate claims (`user_id`, `claimed_at`, `avatar_url`) when local SQLite cache is stale.
- Fixed cross-team unlinking when linking a player spot or updating/removing a profile avatar across multiple teams.

## 1.0.0+2 — 2026-11-26
### Security & Hardening
- Hardened backend invite & scorer handover flows with private RLS-locked tables, CSPRNG 6-digit codes, 30-minute single-use handover TTL, and server-side rate limiting.
- Removed raw user IDs from public discovery payloads and added fail-closed column integrity guards across matches, ball events, players, teams, and tournaments.
- Disabled Android backup (`allowBackup="false"`) and cleartext traffic (`usesCleartextTraffic="false"`), enabled R8 shrinking/obfuscation, and enforced release keystore signing.
- Added strict HTTPS image URL allowlists, canonical UUID validation on deep links & filters, 8-character sign-up password minimum, and pinned SRI + CSP on the live web scorecard.

## 1.0.0+1 — 2026-11-26

### Added
- Offline-first ball-by-ball cricket scoring with 1-tap runs, extras, wickets, and any-ball undo/edit.
- Quick Match setup supporting custom overs, T10, T20, ODI, multi-innings Test matches, and in-match Super Overs.
- Match Center with full batting/bowling scorecards, Worm & Manhattan charts, Match MVP points, and shareable live web links & Match Summary Posters.
- Teams & Squads with custom team logos, Team Profile IDs, Captain/VC/WK designations, and 6-digit teammate invite codes.
- Tournaments (League + Knockout, Knockout, Open) with automatic fixtures, live Points Table, and ICC-compliant Net Run Rate (NRR).
- Local-only Guest Mode with just-in-time Email / Google Sign-In cloud backup, Scorer Handover ("Pass the Baton"), and in-app Account Deletion.
