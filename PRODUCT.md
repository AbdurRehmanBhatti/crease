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

