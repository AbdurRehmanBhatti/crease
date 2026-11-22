-- Crease Phase 1 MVP — Supabase Postgres Schema (matches migration init_crease_mvp)
-- Append-only ball-by-ball event log with RLS + Realtime enabled.

create table if not exists public.matches (
  id text primary key,
  owner_id uuid references auth.users(id) on delete set null default auth.uid(),
  team_a text not null,
  team_b text not null,
  overs_limit integer not null check (overs_limit > 0),
  players_per_side integer not null default 11 check (players_per_side between 2 and 15),
  format_label text not null,
  batting_first_team text not null,
  opening_striker_1 text not null,
  opening_non_striker_1 text not null,
  opening_bowler_1 text not null,
  opening_striker_2 text not null default 'Opener 1',
  opening_non_striker_2 text not null default 'Opener 2',
  opening_bowler_2 text not null default 'Bowler 1',
  team_a_players jsonb not null default '[]'::jsonb,
  team_b_players jsonb not null default '[]'::jsonb,
  first_innings_target_override integer,
  is_demo boolean not null default false,
  created_at bigint not null
);

create table if not exists public.ball_events (
  id text primary key,
  match_id text not null references public.matches(id) on delete cascade,
  owner_id uuid references auth.users(id) on delete set null default auth.uid(),
  innings_number integer not null check (innings_number in (1, 2)),
  sequence_number integer not null check (sequence_number > 0),
  striker text not null,
  non_striker text not null,
  bowler text not null,
  runs_off_bat integer not null default 0 check (runs_off_bat >= 0),
  extra_type text not null default 'none',
  extra_runs integer not null default 0 check (extra_runs >= 0),
  is_wicket boolean not null default false,
  wicket_type text,
  dismissed_batter text,
  fielder text,
  next_batter text,
  voided boolean not null default false,
  created_at bigint not null
);

create index if not exists idx_matches_owner_id
  on public.matches (owner_id);

create index if not exists idx_ball_events_match_seq
  on public.ball_events (match_id, innings_number, sequence_number);

create index if not exists idx_ball_events_owner_id
  on public.ball_events (owner_id);

alter table public.matches enable row level security;
alter table public.ball_events enable row level security;

grant select on public.matches, public.ball_events to anon;
grant select, insert, update, delete on public.matches, public.ball_events to authenticated;

create policy "matches_select_public"
  on public.matches for select
  to anon, authenticated
  using (true);

create policy "matches_insert_own"
  on public.matches for insert
  to authenticated
  with check ((select auth.uid()) = owner_id);

create policy "matches_update_own"
  on public.matches for update
  to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

create policy "matches_delete_own"
  on public.matches for delete
  to authenticated
  using ((select auth.uid()) = owner_id);

create policy "ball_events_select_public"
  on public.ball_events for select
  to anon, authenticated
  using (true);

create policy "ball_events_insert_own"
  on public.ball_events for insert
  to authenticated
  with check ((select auth.uid()) = owner_id);

create policy "ball_events_update_own"
  on public.ball_events for update
  to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

create policy "ball_events_delete_own"
  on public.ball_events for delete
  to authenticated
  using ((select auth.uid()) = owner_id);

alter publication supabase_realtime add table public.matches;
alter publication supabase_realtime add table public.ball_events;

-- Phase 2A: Tournaments & Auto-Derived Points Table / NRR (migration add_tournaments)
create table if not exists public.tournaments (
  id text primary key,
  owner_id uuid references auth.users(id) on delete set null default auth.uid(),
  name text not null,
  overs_limit integer not null check (overs_limit > 0),
  players_per_side integer not null default 11 check (players_per_side between 2 and 15),
  format_label text not null,
  team_rosters jsonb not null default '{}'::jsonb,
  points_for_win integer not null default 2,
  points_for_tie integer not null default 1,
  created_at bigint not null
);

alter table public.matches
  add column if not exists tournament_id text references public.tournaments(id) on delete set null;

create index if not exists idx_tournaments_owner_id on public.tournaments (owner_id);
create index if not exists idx_matches_tournament_id on public.matches (tournament_id);

alter table public.tournaments enable row level security;
grant select on public.tournaments to anon;
grant select, insert, update, delete on public.tournaments to authenticated;

create policy "tournaments_select_public" on public.tournaments for select to anon, authenticated using (true);
create policy "tournaments_insert_own" on public.tournaments for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy "tournaments_update_own" on public.tournaments for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy "tournaments_delete_own" on public.tournaments for delete to authenticated using ((select auth.uid()) = owner_id);

alter publication supabase_realtime add table public.tournaments;

-- Test / Multi-day 4-innings match support (migration add_test_match_support)
alter table public.matches drop constraint if exists matches_overs_limit_check;
alter table public.matches add constraint matches_overs_limit_check check (overs_limit >= 0);
alter table public.matches
  add column if not exists is_test_match boolean not null default false,
  add column if not exists declared_innings jsonb not null default '[]'::jsonb,
  add column if not exists follow_on_enforced boolean not null default false;

alter table public.ball_events drop constraint if exists ball_events_innings_number_check;
alter table public.ball_events add constraint ball_events_innings_number_check check (innings_number between 1 and 4);

-- Standalone Teams directory & rosters (migration add_teams)
create table if not exists public.teams (
  id text primary key,
  owner_id uuid references auth.users(id) on delete set null default auth.uid(),
  name text not null,
  is_my_team boolean not null default false,
  players jsonb not null default '[]'::jsonb,
  created_at bigint not null
);

create index if not exists idx_teams_owner_id on public.teams (owner_id);
alter table public.teams enable row level security;
grant select on public.teams to anon;
grant select, insert, update, delete on public.teams to authenticated;

create policy "teams_select_public" on public.teams for select to anon, authenticated using (true);
create policy "teams_insert_own" on public.teams for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy "teams_update_own" on public.teams for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy "teams_delete_own" on public.teams for delete to authenticated using ((select auth.uid()) = owner_id);

alter publication supabase_realtime add table public.teams;


-- Scorer Handover ("Pass the Baton") (migration add_scorer_handover)
alter table public.matches
  add column if not exists active_scorer_id uuid references auth.users(id) on delete set null,
  add column if not exists scorer_join_code text;

create unique index if not exists idx_matches_scorer_join_code
  on public.matches (scorer_join_code)
  where scorer_join_code is not null;

create table if not exists public.match_scorers (
  match_id text not null references public.matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'scorer' check (role in ('owner', 'scorer')),
  joined_at bigint not null,
  primary key (match_id, user_id)
);

create index if not exists idx_match_scorers_user_id on public.match_scorers (user_id);
alter table public.match_scorers enable row level security;
grant select on public.match_scorers to authenticated;


-- Team Invite Codes & Player Claiming (migration add_team_invites_and_claims)
alter table public.teams
  add column if not exists join_code text;

create unique index if not exists idx_teams_join_code
  on public.teams (join_code)
  where join_code is not null;

create table if not exists public.team_members (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams(id) on delete cascade,
  player_name text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'player' check (role in ('captain', 'player')),
  joined_at bigint not null,
  unique (team_id, user_id)
);

create unique index if not exists idx_team_members_team_player_lower
  on public.team_members (team_id, lower(player_name));


-- Per-player cricket roles & designations (migration add_team_player_roles)
alter table public.teams
  add column if not exists player_meta jsonb not null default '{}'::jsonb;
