# Changelog

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
