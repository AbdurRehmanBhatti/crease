# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Stack

delegated: Flutter (Android first; iOS possible later from the same codebase) + Supabase (Postgres, Auth, Realtime). Chosen because cricket is stats-heavy (SQL fits averages, strike rates, NRR, leaderboards) and Supabase has no per-read billing for live spectators. Every ball is written first to an on-device SQLite event log (source of truth while scoring) and synced to Supabase when online.

## Users

- **Casual / gully / tape-ball players**: a group of friends at a ground or street, one person scoring on their phone between deliveries, often outdoors in strong sunlight, often with weak or no mobile data. Job: start a match in seconds and keep an accurate score without slowing the game.
- **Local club and tournament organisers**: run multi-team tournaments, assign scorers, need standings and NRR that are always correct, and share results with players and followers.
- **Followers / players**: open a shared link or the app to watch a live scorecard and check their own stats.

## Product Purpose

A cricket scoring and tournament app that keeps the score exactly right under real ground conditions, is faster to score with than the incumbents, and produces scorecards and stats worth sharing. Success: a scorer never loses a ball, never has to "fix" a points table by hand, and players actively share their cards.

## Positioning

Crease is built on an append-only ball-by-ball event log stored on the phone first. Every scorecard, stat, standing and NRR is *derived* from that log, never hand-maintained totals, so offline scoring, undo/edit of any ball, multi-device sync and the points table cannot drift out of agreement. Competitors (e.g. Stumps, CricHeroes) are reported to suffer points-table/NRR update failures, offline sync conflicts, confusing scorer roles, and heavy UI for casual games.

## Operating Context

- Scoring happens one-handed, standing, outdoors, between deliveries (a few seconds per ball), often in bright sun and sometimes at dusk/under lights.
- Network is unreliable at grounds; the app must be fully usable offline and sync later.
- Two flows: **Quick Match** (minimal setup, ~3 taps to first ball) and **Tournament** (teams, fixtures, scorers, points table).
- Roles: Owner/Organiser, Scorer (can be several, e.g. a co-scorer), Viewer. Invites via link or QR.
- Results get shared to WhatsApp and social apps as scorecard images/links.

## Capabilities and Constraints

Confirmed for MVP (Phase 1): Quick Match scoring, any-ball undo/edit, full scorecard, offline-first sync, shareable live scorecard link.
Phase 2: tournaments, auto points table and NRR, player profiles and career stats, MVP points.
Phase 3 (undecided detail): live-stream overlays, club pages, notifications, optional monetisation.

### Pre-Production Pending Features (Required Before Launch)
- **Tournament Roles & Permissions (`tournament_members` + RLS + UI gating):**
  - **Organiser (Owner / Co-Admin):** Full tournament control — add/remove teams, edit/remove tournament squad players, unlock knockouts early, invite/revoke scorers, discard matches, delete tournament.
  - **Tournament Scorer (Invited via code/link):** Can start scheduled fixtures, resume live matches (Pass the Baton), score balls, add missing players during a match, and discard unstarted (`0/0`) matches they started — cannot wipe squads, remove teams, or force-unlock knockouts.
  - **Viewer / Player (Read-Only):** Can follow live standings, NRR, fixtures, knockouts, and squads with all mutating controls (FAB, Add/Rename/Remove, Discard, Unlock early) hidden and enforced by Supabase RLS.

### Future Architecture / Known Edge Cases (Post-MVP Roadmap)
- **Local-Only Guest + Just-in-Time Account & Team Profile IDs (Implemented):**
  - Guests open the app and start scoring Quick Matches immediately with **zero anonymous Supabase sessions** (`signInAnonymously` removed). Local matches, teams, and static Match Summary Poster PNG sharing stay 100% on-device.
  - Cloud/social actions (live web share links, Pass the Baton / Join scorer, Create Tournament, Team Invite Codes / Claim Player, and cloud avatar upload) prompt a reusable 1-tap contextual Sign-In sheet (`requireSignedInAccount`), uploading local guest data (with smart duplicate team merge & shared-phone opt-out) upon login.
  - Signed-in clubs automatically receive a unique, human-readable **Team Profile ID** (`profile_code`, e.g. `BX-4K9M`). Quick Match resolves remote Crease opponents by exact Team Profile ID (`lookup_team_by_profile_code`) so random users cannot fabricate matches against unrelated public clubs, and match-only opposition players never mutate that club's official public squad.
- **Same-Name Derbies (`MatchSide` tracking in `CricketEngine`):**
  - **Implemented:** `matches` stores immutable team IDs (`team_a_id`, `team_b_id`) and untouched display-name snapshots (`team_a`, `team_b`) with no `(2)` suffix mutation in Quick Match. `CricketEngine` tracks `battingSide` (`MatchSide.a` | `MatchSide.b`) and `winnerSide`, while `StatsEngine`, team win/loss records, and roster lookups match by `MatchSide` / `teamId` so same-named clubs never collide. In Quick Match, identical names show their location as a subtle subtitle when available, and plain-text result banners append `(A)` / `(B)` only when both team names match case-insensitively.
- **In-Match Super Over (Implemented):**
  - Tied limited-overs matches surface a 1-tap **`Play Super Over`** CTA inside `MatchCompleteSheet` that runs Super Over Innings 1 & 2 as `innings_number` 3 & 4 inside the **same match record** (`1 over`, `2 wickets all-out`, 2nd-innings team batting first per ICC rules), keeps a single unified scorecard with Super Over tabs, excludes Super Over runs/wickets from official career averages per ICC rules, and credits the Super Over winner in team records & tournament standings.
- **Public Live Tab & CQRS Live Summary Projection (Implemented + Scale Path):**
  - **Current Architecture (Launch / Early Growth):** Both matches and tournaments default to `visibility = 'unlisted'` (link-only) and opt into the public **Live** tab via `Show on Live tab` / `Go live` (tournaments cascade visibility to fixtures). `ball_events` remains the single source of truth while `public.match_live_summary` stores a lightweight ~200-byte derived projection per match updated on sync. The **Live** tab uses 15-second foreground-only polling against `get_live_feed` (filtering `balls_count > 0`, 4h/24h anti-zombie freshness for matches, and `team_count >= 2` + 14-day/active-window freshness for tournaments), while `ScorecardScreen` uses Supabase Realtime `postgres_changes` applying incoming `ball_events` `INSERT` payloads directly in memory (`0` extra DB reads per ball).
  - **High-Concurrency Scale Path (500–1,000+ simultaneous viewers per match):** Migrate `ScorecardScreen` (and public `TournamentDetailScreen`) from `postgres_changes` to **Supabase Realtime Broadcast** (e.g. Postgres `realtime.broadcast_changes` trigger publishing to `match:<matchId>`) so fan-out runs purely in memory on the Realtime cluster with **0 per-subscriber RLS checks** on Postgres.
  - **Background / Lock-Screen Notifications (Phase 3):** Trigger a **Supabase Database Webhook → Edge Function → FCM** from `match_live_summary` changes (match start, wickets, innings break, final result) for users not currently in the app.
  - **Live Viewer Count (Optional):** Add `"X watching"` on `ScorecardScreen` via **Supabase Realtime Presence** on the existing `scorecard-<matchId>` channel (zero DB writes).

Constraints: must run smoothly on low-end Android phones; charts (wagon wheel, worm, manhattan) must stay light.
Terminology: standard cricket terms (over, extras, wide, no-ball, bye, leg-bye, wicket types, NRR, strike rate, economy).
Undecided: business model beyond "free, no intrusive ads"; logo and final name confirmation (Crease is the working name).

## Brand Commitments

- Working name: **Crease**.
- Free to use with no intrusive ads (user priority).
- No use of Stumps or any competitor's name, branding or assets.
- **Standing visual preference (user, 2026-11-21):** familiar and clean, not gimmicky or themed. Light, airy, minimal and sharp, with glassy, layered depth. Craft bar to sit alongside: Apple Sports, Linear, Nike Run Club (proposed by the agent; the user gave no references). Rejected: themed or skeuomorphic worlds (pitch, scorebook, split-flap) and the generic dark navy + neon-green sports look.

## Evidence on Hand

No real users, testimonials, ratings, download counts, partner clubs or press exist yet. Do not fabricate any. Demo match data in designs must be clearly synthetic.

## Product Principles

1. **The score is sacred.** No ball is ever lost, double-counted or silently changed; every number is derived from the ball log.
2. **Speed at the crease.** The common delivery (dot, 1–6, wide, wicket) takes one tap; undo is always one tap away.
3. **Works where cricket is played.** Offline, sunlight, one hand, cheap phones.
4. **Casual by default, depth on demand.** Quick Match stays simple; tournament depth never clutters it.
5. **Worth sharing.** Scorecards and stats are designed to be shown off.

## Accessibility & Inclusion

English first; Urdu (RTL) planned next, so layouts must support RTL. Large touch targets (48dp+) and high outdoor-legible contrast; respect system font scale and Remove-animations setting.

