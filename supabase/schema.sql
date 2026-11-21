-- Crease Phase 1 MVP — Supabase Postgres Schema
-- Append-only ball-by-ball event log (idempotent upsert by UUID).

create table if not exists public.matches (
  id text primary key,
  team_a text not null,
  team_b text not null,
  overs_limit integer not null,
  players_per_side integer not null default 11,
  format_label text not null,
  batting_first_team text not null,
  opening_striker_1 text not null,
  opening_non_striker_1 text not null,
  opening_bowler_1 text not null,
  opening_striker_2 text not null default 'Opener 1',
  opening_non_striker_2 text not null default 'Opener 2',
  opening_bowler_2 text not null default 'Bowler 1',
  first_innings_target_override integer,
  is_demo boolean not null default false,
  created_at bigint not null
);

create table if not exists public.ball_events (
  id text primary key,
  match_id text not null references public.matches(id) on delete cascade,
  innings_number integer not null,
  sequence_number integer not null,
  striker text not null,
  non_striker text not null,
  bowler text not null,
  runs_off_bat integer not null default 0,
  extra_type text not null default 'none',
  extra_runs integer not null default 0,
  is_wicket boolean not null default false,
  wicket_type text,
  dismissed_batter text,
  fielder text,
  next_batter text,
  voided boolean not null default false,
  created_at bigint not null
);

create index if not exists idx_ball_events_match_seq
  on public.ball_events (match_id, innings_number, sequence_number);

-- Enable Realtime on ball_events so live scorecards update instantly
alter publication supabase_realtime add table public.ball_events;

