-- Crease Phase 1 MVP — Supabase Postgres Schema (matches migration init_crease_mvp)
-- Append-only ball-by-ball event log with RLS + Realtime enabled.

create table if not exists public.matches (
  id text primary key,
  owner_id uuid references auth.users(id) on delete set null default auth.uid(),
  team_a text not null,
  team_b text not null,
  team_a_id text,
  team_b_id text,
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


-- Structured Tournaments: fixtures, knockouts & match stages (migration add_tournament_structure)
alter table public.tournaments
  add column if not exists structure text not null default 'open',
  add column if not exists rounds_per_pair integer not null default 1,
  add column if not exists knockout_qualifiers integer not null default 2;

alter table public.matches
  add column if not exists tournament_stage text,
  add column if not exists fixture_index integer;


-- Performance indexes for launch-lean scaling (migration add_performance_indexes)
create index if not exists idx_matches_owner_created
  on public.matches (owner_id, created_at desc);

create index if not exists idx_matches_team_a
  on public.matches (lower(team_a));

create index if not exists idx_matches_team_b
  on public.matches (lower(team_b));

create index if not exists idx_team_members_user_id
  on public.team_members (user_id);

create index if not exists idx_tournaments_owner_created
  on public.tournaments (owner_id, created_at desc);

-- Allow Test (unlimited overs = 0) tournaments (migration allow_test_tournament_overs)
alter table public.tournaments drop constraint if exists tournaments_overs_limit_check;
alter table public.tournaments add constraint tournaments_overs_limit_check check (overs_limit >= 0);

-- Transfer anonymous guest data to newly signed-in account with smart team merge
-- (migrations add_claim_guest_data_rpc, smart_merge_guest_teams_on_claim)
create or replace function public.claim_guest_data(
  p_guest_id uuid,
  p_match_ids text[] default '{}',
  p_team_ids text[] default '{}',
  p_tournament_ids text[] default '{}'
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
  v_teams_claimed integer := 0;
  v_tournaments_claimed integer := 0;
  v_merged_team_ids text[] := '{}';
  v_guest_team record;
  v_existing_team record;
  v_merged_players jsonb;
begin
  if v_new_uid is null or p_guest_id is null or v_new_uid = p_guest_id then
    return jsonb_build_object(
      'matches_claimed', 0,
      'teams_claimed', 0,
      'tournaments_claimed', 0,
      'merged_team_ids', '[]'::jsonb
    );
  end if;

  select coalesce(u.is_anonymous, false)
    into v_is_anon
    from auth.users u
   where u.id = p_guest_id;

  if not coalesce(v_is_anon, false) then
    return jsonb_build_object(
      'matches_claimed', 0,
      'teams_claimed', 0,
      'tournaments_claimed', 0,
      'merged_team_ids', '[]'::jsonb
    );
  end if;

  if coalesce(array_length(p_team_ids, 1), 0) > 0 then
    for v_guest_team in
      select id, name, players
        from public.teams
       where id = any(p_team_ids)
         and owner_id = p_guest_id
    loop
      select id, players
        into v_existing_team
        from public.teams
       where owner_id = v_new_uid
         and lower(trim(name)) = lower(trim(v_guest_team.name))
       limit 1;

      if found then
        select coalesce(
          (
            select jsonb_agg(p order by ord)
              from (
                select distinct on (lower(trim(val))) val as p, ord
                  from (
                    select elem as val, idx as ord
                      from jsonb_array_elements_text(coalesce(v_existing_team.players, '[]'::jsonb)) with ordinality as e(elem, idx)
                    union all
                    select elem as val, 100000 + idx as ord
                      from jsonb_array_elements_text(coalesce(v_guest_team.players, '[]'::jsonb)) with ordinality as g(elem, idx)
                  ) combined
                 where trim(val) <> ''
                 order by lower(trim(val)), ord
              ) dedup
          ),
          '[]'::jsonb
        ) into v_merged_players;

        update public.teams
           set players = v_merged_players
         where id = v_existing_team.id;

        update public.teams
           set owner_id = v_new_uid
         where id = v_guest_team.id;

        v_merged_team_ids := array_append(v_merged_team_ids, v_guest_team.id);
      else
        update public.teams
           set owner_id = v_new_uid
         where id = v_guest_team.id;
        v_teams_claimed := v_teams_claimed + 1;

        update public.team_members tm
           set user_id = v_new_uid
         where tm.team_id = v_guest_team.id
           and tm.user_id = p_guest_id
           and not exists (
             select 1
               from public.team_members existing
              where existing.team_id = tm.team_id
                and existing.user_id = v_new_uid
           );
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
           active_scorer_id = case
             when active_scorer_id = p_guest_id then v_new_uid
             else active_scorer_id
           end
     where id = any(p_match_ids)
       and owner_id = p_guest_id;
    get diagnostics v_matches_claimed = row_count;

    update public.match_scorers ms
       set user_id = v_new_uid
     where ms.match_id = any(p_match_ids)
       and ms.user_id = p_guest_id
       and not exists (
         select 1
           from public.match_scorers existing
          where existing.match_id = ms.match_id
            and existing.user_id = v_new_uid
       );
  end if;

  return jsonb_build_object(
    'matches_claimed', v_matches_claimed,
    'teams_claimed', v_teams_claimed,
    'tournaments_claimed', v_tournaments_claimed,
    'merged_team_ids', to_jsonb(v_merged_team_ids)
  );
end;
$$;

revoke all on function public.claim_guest_data(uuid, text[], text[], text[]) from public, anon;
grant execute on function public.claim_guest_data(uuid, text[], text[], text[]) to authenticated;

-- Team location & Tournament venue/dates (migration add_team_and_tournament_location_dates)
alter table public.teams
  add column if not exists location text;

alter table public.tournaments
  add column if not exists location text,
  add column if not exists start_date bigint,
  add column if not exists end_date bigint;

-- Search players across public Crease teams (migration add_search_public_players_rpc)
create or replace function public.search_public_players(
  p_query text,
  p_limit integer default 15
)
returns table (
  player_name text,
  team_id text,
  team_name text,
  team_location text
)
language sql
stable
security invoker
set search_path = public
as $$
  select distinct on (lower(trim(elem)), t.id)
    trim(elem) as player_name,
    t.id as team_id,
    t.name as team_name,
    t.location as team_location
  from public.teams t,
       lateral jsonb_array_elements_text(coalesce(t.players, '[]'::jsonb)) as elem
  where length(trim(coalesce(p_query, ''))) >= 2
    and trim(elem) ilike '%' || trim(p_query) || '%'
    and trim(elem) !~* '^(batter|bowler|opener)\s*\d+$'
  order by lower(trim(elem)), t.id, t.created_at desc
  limit greatest(1, least(coalesce(p_limit, 15), 30));
$$;

grant execute on function public.search_public_players(text, integer) to anon, authenticated;

-- Sync linked player profile avatars for public display (migration add_team_member_avatar_url)
alter table public.team_members
  add column if not exists avatar_url text;

create policy "team_members_update_own"
  on public.team_members
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Allow team owners to auto-link themselves as captain in team_members
-- (migration add_team_members_owner_insert_policy)
create policy "team_members_insert_owner_self"
  on public.team_members
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
        from public.teams t
       where t.id = team_members.team_id
         and t.owner_id = (select auth.uid())
    )
  );
grant insert, update on public.team_members to authenticated;
