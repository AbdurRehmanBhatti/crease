-- Crease v2 — Strict 3NF Schema (Fresh Start, Native UUIDs, Hardened RLS)
-- Run this in Supabase SQL Editor (all v1 tables are empty).

-- 1. Drop legacy v1 RPCs & empty v1 tables
drop function if exists public.claim_guest_data(uuid, text[], text[], text[]);
drop function if exists public.claim_scorer_baton(text);
drop function if exists public.claim_team_player(text, text);
drop function if exists public.create_scorer_handover_code(text);
drop function if exists public.create_team_invite_code(text);
drop function if exists public.lookup_team_by_profile_code(text);
drop function if exists public.preview_team_by_code(text);
drop function if exists public.reclaim_scorer_baton(text);
drop function if exists public.reset_team_invite_code(text);
drop function if exists public.search_public_matches(text, integer);
drop function if exists public.search_public_players(text, integer);
drop function if exists public.search_public_teams(text, integer);
drop function if exists public.search_public_tournaments(text, integer);

drop table if exists public.ball_events cascade;
drop table if exists public.match_scorers cascade;
drop table if exists public.matches cascade;
drop table if exists public.tournament_teams cascade;
drop table if exists public.tournaments cascade;
drop table if exists public.team_members cascade;
drop table if exists public.players cascade;
drop table if exists public.teams cascade;

-- 2. Teams
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete set null default auth.uid(),
  name text not null check (length(trim(name)) > 0),
  location text,
  profile_code text,
  logo_url text,
  join_code text,
  is_my_team boolean not null default false,
  created_at bigint not null
);

create index idx_teams_owner_id on public.teams (owner_id);
create unique index idx_teams_profile_code_lower
  on public.teams (lower(profile_code))
  where profile_code is not null;
create unique index idx_teams_join_code
  on public.teams (join_code)
  where join_code is not null;

-- 3. Players (replaces teams.players, teams.player_meta, and team_members)
create table public.players (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  owner_id uuid references auth.users(id) on delete set null default auth.uid(),
  user_id uuid references auth.users(id) on delete set null,
  display_name text not null check (length(trim(display_name)) > 0),
  role text not null default ''
    check (role in ('', 'Batter', 'Bowler', 'All-rounder', 'Wicket-keeper')),
  designation text
    check (designation is null or designation in ('C', 'VC', 'WK')),
  member_role text not null default 'player'
    check (member_role in ('captain', 'player')),
  avatar_url text,
  claimed_at bigint,
  archived boolean not null default false,
  created_at bigint not null,
  updated_at bigint not null
);

create index idx_players_team_active on public.players (team_id, archived);
create index idx_players_owner_id on public.players (owner_id);
create index idx_players_user_id on public.players (user_id) where user_id is not null;
create unique index idx_players_team_user_unique
  on public.players (team_id, user_id)
  where user_id is not null;
create unique index idx_players_team_designation_active
  on public.players (team_id, designation)
  where designation is not null and archived = false;

-- 4. Tournaments & Tournament Teams
create table public.tournaments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete set null default auth.uid(),
  name text not null check (length(trim(name)) > 0),
  location text,
  start_date bigint,
  end_date bigint,
  overs_limit smallint not null check (overs_limit >= 0),
  players_per_side smallint not null default 11 check (players_per_side between 2 and 15),
  format_label text not null,
  points_for_win smallint not null default 2 check (points_for_win >= 0),
  points_for_tie smallint not null default 1 check (points_for_tie >= 0),
  structure text not null default 'open'
    check (structure in ('open', 'leagueKnockout', 'knockout')),
  rounds_per_pair smallint not null default 1 check (rounds_per_pair between 1 and 4),
  knockout_qualifiers smallint not null default 2 check (knockout_qualifiers in (0, 2, 4, 8)),
  created_at bigint not null
);

create index idx_tournaments_owner_created on public.tournaments (owner_id, created_at desc);

create table public.tournament_teams (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  team_id uuid references public.teams(id) on delete set null,
  ad_hoc_name text,
  seed_order smallint not null default 0,
  created_at bigint not null,
  check (team_id is not null or nullif(trim(coalesce(ad_hoc_name, '')), '') is not null)
);

create index idx_tournament_teams_tournament on public.tournament_teams (tournament_id, seed_order);
create index idx_tournament_teams_team_id on public.tournament_teams (team_id) where team_id is not null;
create unique index idx_tournament_teams_unique_club
  on public.tournament_teams (tournament_id, team_id)
  where team_id is not null;

-- 5. Matches
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete set null default auth.uid(),
  tournament_id uuid references public.tournaments(id) on delete set null,
  team_a_id uuid references public.teams(id) on delete set null,
  team_b_id uuid references public.teams(id) on delete set null,
  team_a text not null,
  team_b text not null,
  batting_first_side text not null check (batting_first_side in ('a', 'b')),
  overs_limit smallint not null check (overs_limit >= 0),
  players_per_side smallint not null default 11 check (players_per_side between 2 and 15),
  format_label text not null,
  opening_striker_1_id uuid,
  opening_non_striker_1_id uuid,
  opening_bowler_1_id uuid,
  opening_striker_2_id uuid,
  opening_non_striker_2_id uuid,
  opening_bowler_2_id uuid,
  team_a_player_ids uuid[] not null default '{}',
  team_b_player_ids uuid[] not null default '{}',
  ad_hoc_players jsonb not null default '{}'::jsonb,
  tournament_stage text
    check (tournament_stage is null or tournament_stage in ('league', 'quarterFinal', 'semiFinal', 'finalMatch')),
  fixture_index smallint,
  is_test_match boolean not null default false,
  declared_innings smallint[] not null default '{}',
  follow_on_enforced boolean not null default false,
  first_innings_target_override integer,
  active_scorer_id uuid references auth.users(id) on delete set null,
  scorer_join_code text,
  is_demo boolean not null default false,
  created_at bigint not null
);

create index idx_matches_owner_created on public.matches (owner_id, created_at desc);
create index idx_matches_team_a_id on public.matches (team_a_id) where team_a_id is not null;
create index idx_matches_team_b_id on public.matches (team_b_id) where team_b_id is not null;
create index idx_matches_tournament_id on public.matches (tournament_id) where tournament_id is not null;
create index idx_matches_active_scorer_id on public.matches (active_scorer_id) where active_scorer_id is not null;
create unique index idx_matches_scorer_join_code
  on public.matches (scorer_join_code)
  where scorer_join_code is not null;

-- 6. Match Scorers
create table public.match_scorers (
  match_id uuid not null references public.matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'scorer' check (role in ('owner', 'scorer')),
  joined_at bigint not null,
  primary key (match_id, user_id)
);

create index idx_match_scorers_user_id on public.match_scorers (user_id);

-- 7. Ball Events (Strict 3NF — native UUIDs only, zero player name strings)
create table public.ball_events (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  owner_id uuid references auth.users(id) on delete set null default auth.uid(),
  innings_number smallint not null check (innings_number between 1 and 4),
  sequence_number integer not null check (sequence_number > 0),
  striker_id uuid not null,
  non_striker_id uuid not null,
  bowler_id uuid not null,
  runs_off_bat smallint not null default 0 check (runs_off_bat >= 0),
  extra_type text not null default 'none'
    check (extra_type in ('none', 'wide', 'noBall', 'bye', 'legBye', 'penalty')),
  extra_runs smallint not null default 0 check (extra_runs >= 0),
  is_wicket boolean not null default false,
  wicket_type text
    check (wicket_type is null or wicket_type in ('bowled', 'caught', 'lbw', 'runOut', 'stumped', 'hitWicket', 'retiredHurt', 'retired')),
  dismissed_batter_id uuid,
  fielder_id uuid,
  next_batter_id uuid,
  voided boolean not null default false,
  created_at bigint not null
);

create index idx_ball_events_match_seq
  on public.ball_events (match_id, innings_number, sequence_number);
create unique index idx_ball_events_active_seq
  on public.ball_events (match_id, innings_number, sequence_number)
  where voided = false;
create index idx_ball_events_owner_id on public.ball_events (owner_id);

-- 8. Row-Level Security (single combined policy per action — zero multiple-permissive warnings)
alter table public.teams enable row level security;
alter table public.players enable row level security;
alter table public.tournaments enable row level security;
alter table public.tournament_teams enable row level security;
alter table public.matches enable row level security;
alter table public.match_scorers enable row level security;
alter table public.ball_events enable row level security;

grant select on public.teams, public.players, public.tournaments, public.tournament_teams, public.matches, public.ball_events to anon;
grant select, insert, update, delete on public.teams, public.players, public.tournaments, public.tournament_teams, public.matches, public.ball_events to authenticated;
grant select on public.match_scorers to authenticated;

-- Teams RLS
create policy "teams_select_public" on public.teams for select to anon, authenticated using (true);
create policy "teams_insert_own" on public.teams for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy "teams_update_own" on public.teams for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy "teams_delete_own" on public.teams for delete to authenticated using ((select auth.uid()) = owner_id);

-- Players RLS
create policy "players_select_public" on public.players for select to anon, authenticated using (true);
create policy "players_insert_owner" on public.players for insert to authenticated
  with check (
    (select auth.uid()) = owner_id
    and exists (
      select 1 from public.teams t
      where t.id = players.team_id
        and t.owner_id = (select auth.uid())
    )
  );
create policy "players_update_owner_or_self" on public.players for update to authenticated
  using (
    (select auth.uid()) = owner_id
    or (select auth.uid()) = user_id
    or exists (
      select 1 from public.teams t
      where t.id = players.team_id
        and t.owner_id = (select auth.uid())
    )
  )
  with check (
    (select auth.uid()) = owner_id
    or (select auth.uid()) = user_id
    or user_id is null
    or exists (
      select 1 from public.teams t
      where t.id = players.team_id
        and t.owner_id = (select auth.uid())
    )
  );
create policy "players_delete_owner" on public.players for delete to authenticated
  using (
    exists (
      select 1 from public.teams t
      where t.id = players.team_id
        and t.owner_id = (select auth.uid())
    )
  );

-- Tournaments RLS
create policy "tournaments_select_public" on public.tournaments for select to anon, authenticated using (true);
create policy "tournaments_insert_own" on public.tournaments for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy "tournaments_update_own" on public.tournaments for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy "tournaments_delete_own" on public.tournaments for delete to authenticated using ((select auth.uid()) = owner_id);

-- Tournament Teams RLS
create policy "tournament_teams_select_public" on public.tournament_teams for select to anon, authenticated using (true);
create policy "tournament_teams_insert_owner" on public.tournament_teams for insert to authenticated
  with check (
    exists (
      select 1 from public.tournaments tr
      where tr.id = tournament_teams.tournament_id
        and tr.owner_id = (select auth.uid())
    )
  );
create policy "tournament_teams_update_owner" on public.tournament_teams for update to authenticated
  using (
    exists (
      select 1 from public.tournaments tr
      where tr.id = tournament_teams.tournament_id
        and tr.owner_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.tournaments tr
      where tr.id = tournament_teams.tournament_id
        and tr.owner_id = (select auth.uid())
    )
  );
create policy "tournament_teams_delete_owner" on public.tournament_teams for delete to authenticated
  using (
    exists (
      select 1 from public.tournaments tr
      where tr.id = tournament_teams.tournament_id
        and tr.owner_id = (select auth.uid())
    )
  );

-- Matches RLS (single combined update policy)
create policy "matches_select_public" on public.matches for select to anon, authenticated using (true);
create policy "matches_insert_own" on public.matches for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy "matches_update_authorized" on public.matches for update to authenticated
  using (
    (select auth.uid()) = owner_id
    or (select auth.uid()) = active_scorer_id
    or exists (
      select 1 from public.match_scorers ms
      where ms.match_id = matches.id
        and ms.user_id = (select auth.uid())
    )
  )
  with check (
    (select auth.uid()) = owner_id
    or (select auth.uid()) = active_scorer_id
    or exists (
      select 1 from public.match_scorers ms
      where ms.match_id = matches.id
        and ms.user_id = (select auth.uid())
    )
  );
create policy "matches_delete_own" on public.matches for delete to authenticated using ((select auth.uid()) = owner_id);

-- Match Scorers RLS
create policy "match_scorers_select_participant" on public.match_scorers for select to authenticated
  using (
    (select auth.uid()) = user_id
    or exists (
      select 1 from public.matches m
      where m.id = match_scorers.match_id
        and m.owner_id = (select auth.uid())
    )
  );

-- Ball Events RLS (single combined policy per action + closes match ownership hole)
create policy "ball_events_select_public" on public.ball_events for select to anon, authenticated using (true);
create policy "ball_events_insert_authorized" on public.ball_events for insert to authenticated
  with check (
    (select auth.uid()) = owner_id
    and exists (
      select 1 from public.matches m
      where m.id = ball_events.match_id
        and (
          m.owner_id = (select auth.uid())
          or m.active_scorer_id = (select auth.uid())
          or exists (
            select 1 from public.match_scorers ms
            where ms.match_id = m.id
              and ms.user_id = (select auth.uid())
          )
        )
    )
  );
create policy "ball_events_update_authorized" on public.ball_events for update to authenticated
  using (
    exists (
      select 1 from public.matches m
      where m.id = ball_events.match_id
        and (
          m.owner_id = (select auth.uid())
          or m.active_scorer_id = (select auth.uid())
          or exists (
            select 1 from public.match_scorers ms
            where ms.match_id = m.id
              and ms.user_id = (select auth.uid())
          )
        )
    )
  )
  with check (
    exists (
      select 1 from public.matches m
      where m.id = ball_events.match_id
        and (
          m.owner_id = (select auth.uid())
          or m.active_scorer_id = (select auth.uid())
          or exists (
            select 1 from public.match_scorers ms
            where ms.match_id = m.id
              and ms.user_id = (select auth.uid())
          )
        )
    )
  );
create policy "ball_events_delete_authorized" on public.ball_events for delete to authenticated
  using (
    exists (
      select 1 from public.matches m
      where m.id = ball_events.match_id
        and (
          m.owner_id = (select auth.uid())
          or m.active_scorer_id = (select auth.uid())
          or exists (
            select 1 from public.match_scorers ms
            where ms.match_id = m.id
              and ms.user_id = (select auth.uid())
          )
        )
    )
  );

-- 9. Realtime Publications
alter publication supabase_realtime add table public.teams;
alter publication supabase_realtime add table public.players;
alter publication supabase_realtime add table public.tournaments;
alter publication supabase_realtime add table public.tournament_teams;
alter publication supabase_realtime add table public.matches;
alter publication supabase_realtime add table public.ball_events;

-- 10. Internal Trigger Helpers (revoked from anon & authenticated)
create or replace function public.generate_team_profile_code(p_team_name text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_words text[];
  v_prefix text := 'CR';
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_suffix text;
  v_candidate text;
  v_i int;
  v_attempt int := 0;
begin
  v_words := regexp_split_to_array(
    trim(regexp_replace(coalesce(p_team_name, ''), '[^A-Za-z0-9]+', ' ', 'g')),
    '\s+'
  );
  if array_length(v_words, 1) >= 2
     and length(v_words[1]) >= 1
     and length(v_words[2]) >= 1 then
    v_prefix := upper(substr(v_words[1], 1, 1) || substr(v_words[2], 1, 1));
  elsif array_length(v_words, 1) = 1 and length(v_words[1]) >= 2 then
    v_prefix := upper(substr(v_words[1], 1, 2));
  elsif array_length(v_words, 1) = 1 and length(v_words[1]) = 1 then
    v_prefix := upper(v_words[1]) || 'X';
  end if;

  loop
    v_attempt := v_attempt + 1;
    v_suffix := '';
    for v_i in 1..4 loop
      v_suffix := v_suffix || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    v_candidate := v_prefix || '-' || v_suffix;
    exit when not exists (
      select 1 from public.teams where lower(profile_code) = lower(v_candidate)
    );
    if v_attempt > 50 then
      v_candidate := v_prefix || '-' || upper(substr(md5(gen_random_uuid()::text), 1, 5));
      exit;
    end if;
  end loop;

  return v_candidate;
end;
$$;

create or replace function public.teams_assign_profile_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.profile_code is null or trim(new.profile_code) = '' then
    new.profile_code := public.generate_team_profile_code(new.name);
  else
    new.profile_code := upper(trim(new.profile_code));
  end if;
  return new;
end;
$$;

create trigger trg_teams_assign_profile_code
  before insert on public.teams
  for each row
  execute function public.teams_assign_profile_code();

revoke all on function public.generate_team_profile_code(text) from public, anon, authenticated;
revoke all on function public.teams_assign_profile_code() from public, anon, authenticated;

-- 11. Live Match Single-Round-Trip Bundle RPC (SECURITY INVOKER — public read)
create or replace function public.get_live_match_bundle(p_match_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  with m as (
    select * from public.matches where id = p_match_id limit 1
  )
  select case
    when not exists (select 1 from m) then null
    else jsonb_build_object(
      'match', (select to_jsonb(m.*) from m),
      'teams', coalesce((
        select jsonb_agg(to_jsonb(t.*))
        from public.teams t, m
        where t.id in (m.team_a_id, m.team_b_id)
      ), '[]'::jsonb),
      'players', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', p.id,
          'team_id', p.team_id,
          'user_id', p.user_id,
          'display_name', p.display_name,
          'role', p.role,
          'designation', p.designation,
          'avatar_url', p.avatar_url,
          'archived', p.archived
        ))
        from public.players p, m
        where p.team_id in (m.team_a_id, m.team_b_id)
           or p.id = any(m.team_a_player_ids || m.team_b_player_ids)
      ), '[]'::jsonb),
      'events', coalesce((
        select jsonb_agg(to_jsonb(b.*) order by b.innings_number, b.sequence_number)
        from public.ball_events b
        where b.match_id = p_match_id
      ), '[]'::jsonb)
    )
  end;
$$;

grant execute on function public.get_live_match_bundle(uuid) to anon, authenticated;

-- 12. Public Discovery RPCs (exclude anonymous accounts)
create or replace function public.search_public_teams(
  p_query text,
  p_limit integer default 15
)
returns table (
  id uuid,
  name text,
  location text,
  profile_code text,
  logo_url text,
  players jsonb
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    t.id,
    t.name,
    t.location,
    t.profile_code,
    t.logo_url,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'display_name', p.display_name,
          'role', p.role,
          'designation', p.designation,
          'user_id', p.user_id,
          'avatar_url', p.avatar_url
        ) order by p.created_at asc
      )
      from public.players p
      where p.team_id = t.id
        and p.archived = false
    ), '[]'::jsonb) as players
  from public.teams t
  join auth.users u on u.id = t.owner_id
  where length(trim(coalesce(p_query, ''))) >= 2
    and coalesce(u.is_anonymous, false) = false
    and t.name ilike '%' || trim(p_query) || '%'
  order by t.created_at desc
  limit greatest(1, least(coalesce(p_limit, 15), 30));
$$;

create or replace function public.lookup_team_by_profile_code(p_code text)
returns table (
  id uuid,
  name text,
  location text,
  profile_code text,
  logo_url text,
  players jsonb
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    t.id,
    t.name,
    t.location,
    t.profile_code,
    t.logo_url,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'display_name', p.display_name,
          'role', p.role,
          'designation', p.designation,
          'user_id', p.user_id,
          'avatar_url', p.avatar_url
        ) order by p.created_at asc
      )
      from public.players p
      where p.team_id = t.id
        and p.archived = false
    ), '[]'::jsonb) as players
  from public.teams t
  join auth.users u on u.id = t.owner_id
  where coalesce(u.is_anonymous, false) = false
    and t.profile_code is not null
    and length(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')) >= 4
    and lower(regexp_replace(t.profile_code, '[^A-Za-z0-9]', '', 'g')) =
        lower(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
  limit 1;
$$;

create or replace function public.search_public_players(
  p_query text,
  p_limit integer default 15
)
returns table (
  player_id uuid,
  display_name text,
  role text,
  avatar_url text,
  team_id uuid,
  team_name text,
  team_location text
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    p.id as player_id,
    p.display_name,
    p.role,
    p.avatar_url,
    t.id as team_id,
    t.name as team_name,
    t.location as team_location
  from public.players p
  join public.teams t on t.id = p.team_id
  join auth.users u on u.id = t.owner_id
  where length(trim(coalesce(p_query, ''))) >= 2
    and p.archived = false
    and coalesce(u.is_anonymous, false) = false
    and p.display_name ilike '%' || trim(p_query) || '%'
    and p.display_name !~* '^(batter|bowler|opener)\s*\d+$'
  order by p.display_name asc, t.created_at desc
  limit greatest(1, least(coalesce(p_limit, 15), 30));
$$;

create or replace function public.search_public_matches(
  p_query text,
  p_limit integer default 10
)
returns table (
  id uuid,
  team_a text,
  team_b text,
  format_label text,
  created_at bigint
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    m.id,
    coalesce(ta.name, m.team_a) as team_a,
    coalesce(tb.name, m.team_b) as team_b,
    m.format_label,
    m.created_at
  from public.matches m
  join auth.users u on u.id = m.owner_id
  left join public.teams ta on ta.id = m.team_a_id
  left join public.teams tb on tb.id = m.team_b_id
  where length(trim(coalesce(p_query, ''))) >= 2
    and m.is_demo = false
    and coalesce(u.is_anonymous, false) = false
    and (
      coalesce(ta.name, m.team_a) ilike '%' || trim(p_query) || '%'
      or coalesce(tb.name, m.team_b) ilike '%' || trim(p_query) || '%'
    )
  order by m.created_at desc
  limit greatest(1, least(coalesce(p_limit, 10), 30));
$$;

create or replace function public.search_public_tournaments(
  p_query text,
  p_limit integer default 10
)
returns table (
  id uuid,
  name text,
  location text,
  start_date bigint,
  end_date bigint,
  format_label text,
  teams jsonb
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    tr.id,
    tr.name,
    tr.location,
    tr.start_date,
    tr.end_date,
    tr.format_label,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', tt.id,
          'team_id', tt.team_id,
          'name', coalesce(t.name, tt.ad_hoc_name),
          'seed_order', tt.seed_order
        ) order by tt.seed_order asc, tt.created_at asc
      )
      from public.tournament_teams tt
      left join public.teams t on t.id = tt.team_id
      where tt.tournament_id = tr.id
    ), '[]'::jsonb) as teams
  from public.tournaments tr
  join auth.users u on u.id = tr.owner_id
  where length(trim(coalesce(p_query, ''))) >= 2
    and coalesce(u.is_anonymous, false) = false
    and (
      tr.name ilike '%' || trim(p_query) || '%'
      or coalesce(tr.location, '') ilike '%' || trim(p_query) || '%'
    )
  order by tr.created_at desc
  limit greatest(1, least(coalesce(p_limit, 10), 30));
$$;

grant execute on function public.search_public_teams(text, integer) to anon, authenticated;
grant execute on function public.lookup_team_by_profile_code(text) to anon, authenticated;
grant execute on function public.search_public_players(text, integer) to anon, authenticated;
grant execute on function public.search_public_matches(text, integer) to anon, authenticated;
grant execute on function public.search_public_tournaments(text, integer) to anon, authenticated;

-- 13. Auth-Only RPCs (revoked from public & anon)
create or replace function public.create_team_invite_code(p_team_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.teams where id = p_team_id and owner_id = v_uid
  ) then
    raise exception 'Only the team owner can invite teammates';
  end if;

  select join_code into v_code from public.teams where id = p_team_id;
  if v_code is null then
    loop
      v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');
      exit when not exists (select 1 from public.teams where join_code = v_code);
    end loop;
    update public.teams set join_code = v_code where id = p_team_id;
  end if;

  return v_code;
end;
$$;

create or replace function public.reset_team_invite_code(p_team_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.teams where id = p_team_id and owner_id = v_uid
  ) then
    raise exception 'Only the team owner can reset the invite code';
  end if;

  loop
    v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from public.teams where join_code = v_code);
  end loop;

  update public.teams set join_code = v_code where id = p_team_id;
  return v_code;
end;
$$;

create or replace function public.preview_team_by_code(p_join_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text := regexp_replace(coalesce(p_join_code, ''), '[^0-9]', '', 'g');
  v_team record;
  v_players jsonb;
  v_my_player_id uuid;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select id, name into v_team
  from public.teams
  where join_code = v_clean
  limit 1;

  if v_team.id is null then
    raise exception 'Invalid team code';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'display_name', p.display_name,
      'role', p.role,
      'designation', p.designation,
      'user_id', p.user_id,
      'avatar_url', p.avatar_url
    ) order by p.created_at asc
  ), '[]'::jsonb)
  into v_players
  from public.players p
  where p.team_id = v_team.id
    and p.archived = false;

  select id into v_my_player_id
  from public.players
  where team_id = v_team.id
    and user_id = v_uid
    and archived = false
  limit 1;

  return jsonb_build_object(
    'team_id', v_team.id,
    'team_name', v_team.name,
    'players', v_players,
    'my_claimed_player_id', v_my_player_id
  );
end;
$$;

create or replace function public.claim_team_player(
  p_join_code text,
  p_player_id uuid default null,
  p_display_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text := regexp_replace(coalesce(p_join_code, ''), '[^0-9]', '', 'g');
  v_name text := trim(coalesce(p_display_name, ''));
  v_now bigint := (extract(epoch from now()) * 1000)::bigint;
  v_team record;
  v_player record;
  v_claimed_id uuid;
  v_claimed_name text;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select id, name, owner_id into v_team
  from public.teams
  where join_code = v_clean
  limit 1
  for update;

  if v_team.id is null then
    raise exception 'Invalid team code';
  end if;

  if p_player_id is not null then
    select id, display_name, user_id into v_player
    from public.players
    where id = p_player_id
      and team_id = v_team.id
      and archived = false
    for update;

    if v_player.id is null then
      raise exception 'Player not found in this team';
    end if;

    if v_player.user_id is not null and v_player.user_id <> v_uid then
      raise exception 'This player is already claimed';
    end if;

    update public.players
    set user_id = null, claimed_at = null, updated_at = v_now
    where team_id = v_team.id
      and user_id = v_uid
      and id <> v_player.id;

    update public.players
    set user_id = v_uid,
        claimed_at = v_now,
        updated_at = v_now
    where id = v_player.id;

    v_claimed_id := v_player.id;
    v_claimed_name := v_player.display_name;
  else
    if v_name = '' then
      raise exception 'Player name is required';
    end if;

    update public.players
    set user_id = null, claimed_at = null, updated_at = v_now
    where team_id = v_team.id
      and user_id = v_uid;

    insert into public.players (
      team_id, owner_id, user_id, display_name, member_role, claimed_at, created_at, updated_at
    )
    values (
      v_team.id, v_team.owner_id, v_uid, v_name, 'player', v_now, v_now, v_now
    )
    returning id, display_name into v_claimed_id, v_claimed_name;
  end if;

  return jsonb_build_object(
    'team_id', v_team.id,
    'team_name', v_team.name,
    'player_id', v_claimed_id,
    'display_name', v_claimed_name
  );
end;
$$;

create or replace function public.create_scorer_handover_code(p_match_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_allowed boolean;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select exists (
    select 1 from public.matches m
    where m.id = p_match_id
      and (
        m.owner_id = v_uid
        or m.active_scorer_id = v_uid
        or exists (
          select 1 from public.match_scorers ms
          where ms.match_id = m.id and ms.user_id = v_uid
        )
      )
  ) into v_allowed;

  if not v_allowed then
    raise exception 'Not authorized to hand over this match';
  end if;

  select scorer_join_code into v_code from public.matches where id = p_match_id;
  if v_code is null then
    loop
      v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');
      exit when not exists (select 1 from public.matches where scorer_join_code = v_code);
    end loop;
    update public.matches set scorer_join_code = v_code where id = p_match_id;
  end if;

  insert into public.match_scorers (match_id, user_id, role, joined_at)
  values (p_match_id, v_uid, 'owner', (extract(epoch from now()) * 1000)::bigint)
  on conflict (match_id, user_id) do nothing;

  return v_code;
end;
$$;

create or replace function public.claim_scorer_baton(p_join_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text := regexp_replace(coalesce(p_join_code, ''), '[^0-9]', '', 'g');
  v_match_id uuid;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select id into v_match_id
  from public.matches
  where scorer_join_code = v_clean
  limit 1;

  if v_match_id is null then
    raise exception 'Invalid scorer code';
  end if;

  insert into public.match_scorers (match_id, user_id, role, joined_at)
  values (v_match_id, v_uid, 'scorer', (extract(epoch from now()) * 1000)::bigint)
  on conflict (match_id, user_id) do nothing;

  update public.matches set active_scorer_id = v_uid where id = v_match_id;
  return v_match_id;
end;
$$;

create or replace function public.reclaim_scorer_baton(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_allowed boolean;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select exists (
    select 1 from public.matches m
    where m.id = p_match_id
      and (
        m.owner_id = v_uid
        or exists (
          select 1 from public.match_scorers ms
          where ms.match_id = m.id and ms.user_id = v_uid
        )
      )
  ) into v_allowed;

  if not v_allowed then
    raise exception 'Not authorized to score this match';
  end if;

  update public.matches set active_scorer_id = v_uid where id = p_match_id;
end;
$$;

create or replace function public.claim_guest_data(
  p_guest_id uuid,
  p_match_ids uuid[] default '{}',
  p_team_ids uuid[] default '{}',
  p_tournament_ids uuid[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_new_uid uuid := auth.uid();
  v_is_anon boolean := false;
  v_matches_claimed integer := 0;
  v_ball_events_claimed integer := 0;
  v_teams_claimed integer := 0;
  v_tournaments_claimed integer := 0;
  v_merged_team_ids uuid[] := '{}';
  v_merged_team_map jsonb := '{}'::jsonb;
  v_guest_team record;
  v_existing_team record;
begin
  if v_new_uid is null or p_guest_id is null or v_new_uid = p_guest_id then
    return jsonb_build_object(
      'matches_claimed', 0,
      'ball_events_claimed', 0,
      'teams_claimed', 0,
      'tournaments_claimed', 0,
      'merged_team_ids', '[]'::jsonb,
      'merged_team_map', '{}'::jsonb
    );
  end if;

  select coalesce(u.is_anonymous, false)
  into v_is_anon
  from auth.users u
  where u.id = p_guest_id;

  if not coalesce(v_is_anon, false) then
    return jsonb_build_object(
      'matches_claimed', 0,
      'ball_events_claimed', 0,
      'teams_claimed', 0,
      'tournaments_claimed', 0,
      'merged_team_ids', '[]'::jsonb,
      'merged_team_map', '{}'::jsonb
    );
  end if;

  if coalesce(array_length(p_team_ids, 1), 0) > 0 then
    for v_guest_team in
      select id, name, location
      from public.teams
      where id = any(p_team_ids)
        and owner_id = p_guest_id
    loop
      select id, location
      into v_existing_team
      from public.teams
      where owner_id = v_new_uid
        and lower(trim(name)) = lower(trim(v_guest_team.name))
      limit 1;

      if found then
        update public.teams
        set location = coalesce(nullif(trim(v_existing_team.location), ''), v_guest_team.location)
        where id = v_existing_team.id;

        update public.matches set team_a_id = v_existing_team.id where team_a_id = v_guest_team.id;
        update public.matches set team_b_id = v_existing_team.id where team_b_id = v_guest_team.id;

        update public.tournament_teams
        set team_id = v_existing_team.id
        where team_id = v_guest_team.id
          and not exists (
            select 1 from public.tournament_teams existing_tt
            where existing_tt.tournament_id = tournament_teams.tournament_id
              and existing_tt.team_id = v_existing_team.id
          );

        update public.players gp
        set team_id = v_existing_team.id,
            owner_id = v_new_uid,
            user_id = case when gp.user_id = p_guest_id then null else gp.user_id end,
            designation = case
              when gp.designation is not null and exists (
                select 1 from public.players ep
                where ep.team_id = v_existing_team.id
                  and ep.archived = false
                  and ep.designation = gp.designation
              ) then null
              else gp.designation
            end
        where gp.team_id = v_guest_team.id;

        update public.teams set owner_id = v_new_uid where id = v_guest_team.id;
        v_merged_team_ids := array_append(v_merged_team_ids, v_guest_team.id);
        v_merged_team_map := v_merged_team_map || jsonb_build_object(v_guest_team.id::text, v_existing_team.id::text);
      else
        update public.teams set owner_id = v_new_uid where id = v_guest_team.id;
        update public.players
        set owner_id = v_new_uid,
            user_id = case when user_id = p_guest_id then v_new_uid else user_id end
        where team_id = v_guest_team.id;
        v_teams_claimed := v_teams_claimed + 1;
      end if;
    end loop;
  end if;

  if coalesce(array_length(p_tournament_ids, 1), 0) > 0 then
    update public.tournaments
    set owner_id = v_new_uid
    where id = any(p_tournament_ids)
      and owner_id = p_guest_id;
    get diagnostics v_tournaments_claimed = row_count;
  end if;

  if coalesce(array_length(p_match_ids, 1), 0) > 0 then
    update public.matches
    set owner_id = v_new_uid,
        active_scorer_id = case when active_scorer_id = p_guest_id then v_new_uid else active_scorer_id end
    where id = any(p_match_ids)
      and owner_id = p_guest_id;
    get diagnostics v_matches_claimed = row_count;

    update public.matches
    set active_scorer_id = v_new_uid
    where id = any(p_match_ids)
      and active_scorer_id = p_guest_id
      and owner_id <> v_new_uid;

    update public.ball_events
    set owner_id = v_new_uid
    where match_id = any(p_match_ids)
      and owner_id = p_guest_id;
    get diagnostics v_ball_events_claimed = row_count;

    update public.match_scorers ms
    set user_id = v_new_uid
    where ms.match_id = any(p_match_ids)
      and ms.user_id = p_guest_id
      and not exists (
        select 1 from public.match_scorers existing
        where existing.match_id = ms.match_id
          and existing.user_id = v_new_uid
      );
  end if;

  return jsonb_build_object(
    'matches_claimed', v_matches_claimed,
    'ball_events_claimed', v_ball_events_claimed,
    'teams_claimed', v_teams_claimed,
    'tournaments_claimed', v_tournaments_claimed,
    'merged_team_ids', to_jsonb(v_merged_team_ids),
    'merged_team_map', v_merged_team_map
  );
end;
$$;

revoke all on function public.create_team_invite_code(uuid) from public, anon;
grant execute on function public.create_team_invite_code(uuid) to authenticated;

revoke all on function public.reset_team_invite_code(uuid) from public, anon;
grant execute on function public.reset_team_invite_code(uuid) to authenticated;

revoke all on function public.preview_team_by_code(text) from public, anon;
grant execute on function public.preview_team_by_code(text) to authenticated;

revoke all on function public.claim_team_player(text, uuid, text) from public, anon;
grant execute on function public.claim_team_player(text, uuid, text) to authenticated;

revoke all on function public.create_scorer_handover_code(uuid) from public, anon;
grant execute on function public.create_scorer_handover_code(uuid) to authenticated;

revoke all on function public.claim_scorer_baton(text) from public, anon;
grant execute on function public.claim_scorer_baton(text) to authenticated;

revoke all on function public.reclaim_scorer_baton(uuid) from public, anon;
grant execute on function public.reclaim_scorer_baton(uuid) to authenticated;

revoke all on function public.claim_guest_data(uuid, uuid[], uuid[], uuid[]) from public, anon;
grant execute on function public.claim_guest_data(uuid, uuid[], uuid[], uuid[]) to authenticated;
