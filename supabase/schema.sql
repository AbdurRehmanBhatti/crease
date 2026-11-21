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
