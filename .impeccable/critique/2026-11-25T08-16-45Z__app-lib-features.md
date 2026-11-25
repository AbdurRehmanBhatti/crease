---
target: our UI and UX especially
total_score: 26
max_score: 40
na_heuristics: 
p0_count: 2
p1_count: 3
target_identity: "file:C:\\Users\\AbdurRehman\\.gemini\\antigravity\\scratch\\crease\\app\\lib\\features"
timestamp: 2026-11-25T08-16-45Z
slug: app-lib-features
---
Method: dual-agent (A: aedecc8b-165e-4e52-8b1e-a42203eb2938 · B: 61cf43c6-6045-4e41-8644-0f8e7a94f1cf)

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3/4 | No offline/sync indicator inside `ScoringScreen`; green dot on Home profile avatar reads like an unread notification instead of guest status. |
| 2 | Match System / Real World | 3/4 | `showExtrasRunsSheet` asks `"Wide (+1 penalty): additional runs?"` with `+0..+4` (mental math); `"Join scorer"` reads awkwardly. |
| 3 | User Control and Freedom | 2/4 | No **Redo** after accidental Undo; `showEditBallSheet` cannot fix a ball into a Wide/No-ball/Wicket; `Remove player` deletes immediately with no confirmation or Undo. |
| 4 | Consistency and Standards | 2/4 | Half of bottom sheets use `CreaseSheetHeader` (`×`), half hand-roll a drag pill; match delete is hidden behind `onLongPress`; primary CTA alternates between `inkPrimary` and `pitchGreen`. |
| 5 | Error Prevention | 2/4 | `Wicket`, `Run out`, and `Undo` sit flush on one row with no Redo; `showNextBowlerSheet` silently injects `"Bowler 2"` if confirmed empty. |
| 6 | Recognition Rather Than Recall | 3/4 | Three core scoring gestures have zero visual cue: tap batter to swap strike, tap bowler to change bowler, tap `OverTimeline` circles to edit a ball. |
| 7 | Flexibility and Efficiency | 3/4 | Every routine 1-run `Wide` forces a 2-tap modal; Home's `+ New match` CTA sits in the top-right corner (`38dp`) instead of the thumb zone. |
| 8 | Aesthetic and Minimalist Design | 3/4 | `TeamDetailScreen` and `PlayerProfileScreen` duplicate the title in AppBar + Hero Card; `MatchCompleteSheet` repeats `FINAL` directly below `Final`. |
| 9 | Error Recovery | 2/4 | `ProfileScreen` leaks raw Google Cloud Console SHA-1 instructions to end users; `_signOut()` silently swallows offline failures and leaves the user signed in. |
| 10 | Help and Documentation | 3/4 | Good MVP formula sheet and NRR footnote, but zero first-run cue for invisible scoring gestures. |
| **Total** | | **26/40** | **Acceptable** |

## Design Specificity Verdict

- **LLM assessment:** The core live-scoring canvas (`ScoringScreen`, `GlassScoringSheet`, `LiveCreaseCard`, `OverTimeline`) feels genuinely authored for outdoor cricket — `60sp`/`46sp` tabular `Barlow` numerals, crisp cool-stone daylight ground, disciplined 2-accent semantics, and fast tactile keys. Outside `ScoringScreen`, however, the surrounding shell (`HomeScreen`, `TeamsTabView`, `SearchScreen`, `ProfileScreen`) flattens into a generic SaaS card-list template, even reusing `CreaseTeamBadge` verbatim for clubs, tournaments, and human players.
- **Deterministic scan:** Ran `impeccable detect --json` across `app/lib/features`, `app/lib/widgets` (`0` findings — `.dart` files are not parsed by the HTML/CSS detector), and `docs/index.html` (**3 findings**: 1 error, 2 warnings):
  - `low-contrast` (`warning`): `#ffffff` on `#19a96b` (`3.0:1`, needs `4.5:1`) — **confirmed as a real dark-mode WCAG AA bug in 40+ Flutter widgets** where `Colors.white` is hardcoded over `c.pitchGreen` (`#19A96B`), plus `Colors.white` over `c.wicketRed` (`#EC5463`, `3.49:1`).
  - `pulsing-dot` (`error`): `.live-dot` — **false positive** in Flutter (`CreaseLiveDot` is strictly semantic for live matches and honors `disableAnimationsOf`).
  - `overused-font` (`warning`): `Plus Jakarta Sans` — **intentional** (pinned in `DESIGN.md` alongside tabular `Barlow`).
  - Static Flutter/Android audit additionally caught **sub-48dp touch targets** (down to `16×16dp`), **5 `IconButton`s missing `tooltip`**, **edge-to-edge `SafeArea` gaps**, **font-scale `1.3x+` clipping**, and **1 dead UI file** (`app/lib/features/stats/stats_tab_view.dart`).
- **Visual overlays:** Not applicable — Crease is a native Flutter Android app (no browser DOM/CSS injection).

## Overall Impression
Crease's live scoring engine and daylight scoreboard are already ahead of most mobile cricket scorers, and the new 3-tab shell + 4-tab Team Profile + in-match Super Over give the product strong structural clarity. The biggest gap is **execution polish at the edges**: one-handed reachability & touch-target sizing, dark-mode button contrast (`3.03:1`), invisible scoring gestures, and unprotected destructive actions.

## What's Working
1. **Outdoor-First Scoring Canvas:** `60sp`/`46sp` tabular `Barlow` score numerals, solid high-contrast surfaces (no laggy `BackdropFilter`), strict 2-accent restraint, and differentiated haptics make ball-by-ball entry fast in direct sun.
2. **Cricket-Aware Guardrails:** Back-to-back bowler prevention, dismissed-batter score pills, live Pass-the-Baton handover, ICC NRR standings, and in-match Super Over inside the same match record.
3. **Reduced-Motion & Offline-First Architecture:** Respecting `MediaQuery.disableAnimationsOf(context)` across animated widgets and deriving every stat/scorecard from the local SQLite event log.

## Priority Issues

### 1. [P0] One-Handed Ergonomics, Sub-48dp Touch Targets & 2-Tap Wides
- **What:** Home's `+ New match` / `+ Team` / `+ Tournament` CTA sits in the top-right corner at `38dp` height beside `40×40dp` Search/Profile buttons (`home_screen.dart:395-477`). Interactive controls drop below Android's `48dp` minimum across the app: `16×16dp` unpadded date-clear `GestureDetector` (`create_tournament_sheet.dart:548`, `tournament_detail_screen.dart:312`), `32×32dp` `CreaseMenuButton(compact: true)` (`crease_ui.dart:762`), `34×34dp` `_BallCircle` (`scoring_header_widgets.dart:439`), and `36×36dp` `CreaseSheetHeader` close icon (`crease_ui.dart:433`). Every plain 1-run `Wide` forces a 2-tap modal (`scoring_keypad_sheet.dart:426`).
- **Why it matters:** Breaks `PRODUCT.md`'s one-handed outdoor scoring and `48dp+` touch-target commitments; invites mis-taps in bright sun.
- **Fix:** Move Home primary creation to a bottom thumb-zone FAB; pad all icon controls to `>=48×48dp` hit areas; make plain `Wide` 1-tap (with quick `+runs` / long-press for extras).
- **Suggested command:** `/impeccable harden` + `/impeccable adapt`

### 2. [P0] Invisible Scoring Affordances & Unprotected Destructive Actions
- **What:** Tapping batter rows to swap strike (`live_crease_card.dart:73`), tapping bowler row to change bowler (`live_crease_card.dart:113`), and tapping `OverTimeline` circles to edit balls (`scoring_header_widgets.dart:439`) have zero visual cue. `_undoLastBall` has no **Redo**; `Remove player` (`teams_tab_view.dart:1074`) and `Remove this ball` (`scoring_action_sheets.dart:789`) mutate immediately without confirmation or Undo; match delete is hidden behind `onLongPress` (`home_screen.dart:616`).
- **Why it matters:** Violates "The score is sacred" — users miss core shortcuts while a single slip can delete a player or void a ball without recovery.
- **Fix:** Add subtle swap/edit cues on `LiveCreaseCard`, add `Redo` to Undo snackbar, add Undo snackbar / confirmation to destructive removes, and expose match delete via `CreaseMenuButton`.
- **Suggested command:** `/impeccable polish`

### 3. [P1] Dark-Mode WCAG AA Contrast Failures (`3.03:1`) Across 40+ Widgets
- **What:** `Colors.white` is hardcoded over `c.pitchGreen` (`#19A96B` in dark mode = **3.03:1**, fails WCAG AA `4.5:1`) in 40+ places, and over `c.wicketRed` (`#EC5463` in dark mode = **3.49:1**). Only `tournament_detail_screen.dart:634` uses dark ink `#07120D` (**6.29:1**).
- **Why it matters:** White text on bright mint-green buttons washes out on OLED screens under floodlights / night matches.
- **Fix:** Add `onPitchGreen` (`#FFFFFF` light / `#07120D` dark) and `onWicketRed` tokens to `CreaseThemeExtension` and replace hardcoded `Colors.white` on filled accent controls.
- **Suggested command:** `/impeccable colorize` + `/impeccable audit`

### 4. [P1] Developer Error Leakage & Silent Offline Sign-Out Failure
- **What:** `ProfileScreen` shows raw Google Cloud Console SHA-1 instructions (`profile_screen.dart:422,486`). `_signOut()` (`profile_screen.dart:902-922`) catches all errors silently — signing out offline flashes a skeleton and leaves the user signed in with zero explanation.
- **Why it matters:** Erodes user trust and fails in Crease's core low-connectivity ground context.
- **Fix:** Replace OAuth developer copy with plain user guidance and show an explicit offline warning/action on sign-out failure.
- **Suggested command:** `/impeccable clarify` + `/impeccable harden`

### 5. [P1] Cognitive Overload in `showRecordWicketSheet` & `showMatchOptionsSheet`
- **What:** `showRecordWicketSheet` (`scoring_action_sheets.dart:331-541`) renders up to 19+ chips simultaneously (8 wicket types + 11 fielders + delivery + runs). `showMatchOptionsSheet` (`match_options_sheets.dart:117-194`) mixes ball-level events (`5 runs`, `+5 Penalty`) with match-admin actions (`End innings`, `Hand over`, `Abandon`) in one flat grid.
- **Why it matters:** Wickets are the highest-pressure moment in live scoring; scanning a wall of chips slows the match.
- **Fix:** Show the 4 primary dismissals (`Caught`, `Bowled`, `LBW`, `Run out`) with a `More ▾` disclosure; replace the 11-chip fielder wall with a compact picker; split `showMatchOptionsSheet` into **Scoring Events** and **Match Controls**.
- **Suggested command:** `/impeccable distill`

## Persona Red Flags
- **Casey (One-Handed Outdoor Scorer):** Top-right `38dp` `+ New match` and `40×40dp` top icons force two hands; every `Wide` takes 2 taps; `34×34dp` ball circles are hard to tap in glare; accidental `Undo` next to `Run out` has no Redo; confirming empty `showNextBowlerSheet` silently injects `"Bowler 2"`.
- **Jordan (First-Timer):** Green dot on Home Profile icon looks like an unread notification; invisible strike-swap / edit-ball / long-press-delete gestures; `"Wide (+1 penalty): additional runs?"` (`+0`) requires mental subtraction; `"Join scorer"` is awkward.
- **Riley (Stress Tester):** `Remove player` and `Remove this ball` delete with no confirmation/Undo; offline `Sign out` silently fails; `1.3x–1.5x` Android font scale clips `ProfileScreen` 2×2 stat grid, `MatchOptionsSheet` grid, `PlayerProfileScreen` `36dp` form rows, and `34×34dp` ball circles; `search_screen.dart` and `player_profile_screen.dart` lack bottom `SafeArea`.

## Minor Observations
- **Dead file cleanup:** `app/lib/features/stats/stats_tab_view.dart` has 0 references after removing the bottom Stats tab and can be deleted.
- **Entity distinction:** Give human players circular avatars and tournaments a distinct trophy mark instead of reusing `CreaseTeamBadge` everywhere.
- **Accessibility & RTL:** Add `tooltip` to the 5 unlabeled `IconButton`s (`profile_screen.dart:679`, `quick_match_sheet.dart:343`, `search_screen.dart:317`, `teams_tab_view.dart:441`, `tournament_sheets.dart:444`) and migrate physical `EdgeInsets.only(left/right)` in `ScoringScreen` / `LiveCreaseCard` to `EdgeInsetsDirectional` ahead of Urdu RTL.
- **Controller cleanup:** Dispose `TextEditingController`s in `showNextBowlerSheet`, `showRecordWicketSheet`, and `showNextBatterSheet`.

## Questions to Consider
1. If 90% of wides in local cricket are plain 1-run wides, why does Crease force a modal sheet and mental subtraction (`+0 additional runs`) on every single wide?
2. Why does the *only* screen where a scorer spends 3 continuous hours (`ScoringScreen`) hide offline/sync status while `HomeScreen` cards show it?
3. Outside `ScoringScreen`, if you swapped cricket words for "Workouts" or "Invoices," what in the component hierarchy would still unmistakably say *Crease*?
