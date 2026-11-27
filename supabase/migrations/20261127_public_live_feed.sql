-- Crease — Public Live Tab: Visibility, CQRS Live Summary Projection & Feed RPCs
-- Both matches and tournaments default to 'unlisted' (link-only) until opted in.

-- 1. Visibility & optional venue on matches and tournaments
alter table public.tournaments
  add column if not exists visibility text not null default 'unlisted'
    check (visibility in ('unlisted', 'public'));

alter table public.matches
  add column if not exists visibility text not null default 'unlisted'
    check (visibility in ('unlisted', 'public'));

alter table public.matches
  add column if not exists venue text;

create index if not exists idx_tournaments_public_created
  on public.tournaments (created_at desc)
  where visibility = 'public';

create index if not exists idx_matches_public_created
  on public.matches (created_at desc)
  where visibility = 'public' and is_demo = false;

-- Refresh get_live_match_bundle so its match JSON includes the new visibility & venue columns
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

-- 2. Lightweight 1:1 CQRS live summary projection (ball_events remains source of truth)
create table if not exists public.match_live_summary (
  match_id uuid primary key references public.matches(id) on delete cascade,
  status text not null default 'live'
    check (status in ('live', 'inningsBreak', 'completed', 'abandoned')),
  active_innings smallint not null default 1 check (active_innings between 1 and 4),
  batting_side text not null default 'a' check (batting_side in ('a', 'b')),
  inn1_batting_side text not null default 'a' check (inn1_batting_side in ('a', 'b')),
  inn1_runs integer not null default 0 check (inn1_runs >= 0),
  inn1_wickets smallint not null default 0 check (inn1_wickets >= 0),
  inn1_overs text not null default '0.0',
  inn2_started boolean not null default false,
  inn2_batting_side text
    check (inn2_batting_side is null or inn2_batting_side in ('a', 'b')),
  inn2_runs integer not null default 0 check (inn2_runs >= 0),
  inn2_wickets smallint not null default 0 check (inn2_wickets >= 0),
  inn2_overs text not null default '0.0',
  status_line text,
  last_ball_label text,
  last_ball_kind text not null default 'normal'
    check (last_ball_kind in ('normal', 'boundary', 'wicket', 'extra')),
  balls_count integer not null default 0 check (balls_count >= 0),
  last_event_at bigint not null,
  updated_at bigint not null
);

create index if not exists idx_match_live_summary_status_event
  on public.match_live_summary (status, last_event_at desc)
  where balls_count > 0;

create index if not exists idx_match_live_summary_last_event
  on public.match_live_summary (last_event_at desc)
  where balls_count > 0;

-- 3. Row-Level Security on match_live_summary (single policy per action)
alter table public.match_live_summary enable row level security;

grant select on public.match_live_summary to anon;
grant select, insert, update, delete on public.match_live_summary to authenticated;

drop policy if exists "match_live_summary_select_public" on public.match_live_summary;
create policy "match_live_summary_select_public"
  on public.match_live_summary for select to anon, authenticated
  using (true);

drop policy if exists "match_live_summary_insert_authorized" on public.match_live_summary;
create policy "match_live_summary_insert_authorized"
  on public.match_live_summary for insert to authenticated
  with check (
    exists (
      select 1 from public.matches m
      where m.id = match_live_summary.match_id
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

drop policy if exists "match_live_summary_update_authorized" on public.match_live_summary;
create policy "match_live_summary_update_authorized"
  on public.match_live_summary for update to authenticated
  using (
    exists (
      select 1 from public.matches m
      where m.id = match_live_summary.match_id
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
      where m.id = match_live_summary.match_id
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

drop policy if exists "match_live_summary_delete_authorized" on public.match_live_summary;
create policy "match_live_summary_delete_authorized"
  on public.match_live_summary for delete to authenticated
  using (
    exists (
      select 1 from public.matches m
      where m.id = match_live_summary.match_id
        and m.owner_id = (select auth.uid())
    )
  );

-- Add match_live_summary to supabase_realtime publication safely
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'match_live_summary'
  ) then
    alter publication supabase_realtime add table public.match_live_summary;
  end if;
end $$;

-- 4. Atomic Tournament Visibility RPC (cascades to all tournament matches)
create or replace function public.set_tournament_visibility(
  p_tournament_id uuid,
  p_visibility text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_vis text := lower(trim(coalesce(p_visibility, 'unlisted')));
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;
  if v_vis not in ('unlisted', 'public') then
    raise exception 'Invalid visibility value';
  end if;

  update public.tournaments
  set visibility = v_vis
  where id = p_tournament_id
    and owner_id = v_uid;

  if not found then
    return false;
  end if;

  update public.matches
  set visibility = v_vis
  where tournament_id = p_tournament_id;

  return true;
end;
$$;

revoke all on function public.set_tournament_visibility(uuid, text) from public, anon;
grant execute on function public.set_tournament_visibility(uuid, text) to authenticated;

-- 5. Single-Round-Trip Public Live Feed RPC (anon + authenticated)
create or replace function public.get_live_feed(
  p_live_limit integer default 30,
  p_recent_limit integer default 20
)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
  with params as (
    select
      (extract(epoch from now()) * 1000)::bigint as now_ms,
      greatest(1, least(coalesce(p_live_limit, 30), 60)) as lim_live,
      greatest(1, least(coalesce(p_recent_limit, 20), 40)) as lim_recent
  ),
  public_matches_base as (
    select
      m.id,
      coalesce(ta.name, m.team_a) as team_a,
      coalesce(tb.name, m.team_b) as team_b,
      m.team_a_id,
      m.team_b_id,
      ta.logo_url as team_a_logo_url,
      tb.logo_url as team_b_logo_url,
      m.format_label,
      m.overs_limit,
      m.is_test_match,
      m.tournament_id,
      tr.name as tournament_name,
      coalesce(
        nullif(trim(m.venue), ''),
        nullif(trim(tr.location), ''),
        nullif(trim(ta.location), '')
      ) as venue,
      s.status,
      s.active_innings,
      s.batting_side,
      s.inn1_batting_side,
      s.inn1_runs,
      s.inn1_wickets,
      s.inn1_overs,
      s.inn2_started,
      s.inn2_batting_side,
      s.inn2_runs,
      s.inn2_wickets,
      s.inn2_overs,
      s.status_line,
      s.last_ball_label,
      s.last_ball_kind,
      s.balls_count,
      s.last_event_at
    from public.matches m
    join public.match_live_summary s on s.match_id = m.id
    join auth.users u on u.id = m.owner_id
    left join public.tournaments tr on tr.id = m.tournament_id
    left join public.teams ta on ta.id = m.team_a_id
    left join public.teams tb on tb.id = m.team_b_id
    where m.is_demo = false
      and coalesce(u.is_anonymous, false) = false
      and (m.visibility = 'public' or coalesce(tr.visibility, 'unlisted') = 'public')
      and s.balls_count > 0
  ),
  live_matches as (
    select b.*
    from public_matches_base b, params p
    where b.status in ('live', 'inningsBreak')
      and (
        (b.is_test_match = false and b.last_event_at >= p.now_ms - 14400000) -- 4 hours
        or (b.is_test_match = true and b.last_event_at >= p.now_ms - 86400000) -- 24 hours
      )
    order by b.last_event_at desc
    limit (select lim_live from params)
  ),
  recent_matches as (
    select b.*
    from public_matches_base b
    where b.status in ('completed', 'abandoned')
    order by b.last_event_at desc
    limit (select lim_recent from params)
  ),
  public_tournaments as (
    select
      tr.id,
      tr.name,
      tr.location,
      tr.format_label,
      tr.structure,
      tr.start_date,
      tr.end_date,
      tr.created_at,
      (
        select count(*)::int
        from public.tournament_teams tt
        where tt.tournament_id = tr.id
      ) as team_count,
      (
        select count(*)::int
        from live_matches lm
        where lm.tournament_id = tr.id
      ) as live_match_count,
      (
        select count(*)::int
        from public.matches m2
        join public.match_live_summary s2 on s2.match_id = m2.id
        where m2.tournament_id = tr.id
          and m2.is_demo = false
          and s2.status = 'completed'
      ) as completed_match_count,
      coalesce((
        select max(s3.last_event_at)
        from public.matches m3
        join public.match_live_summary s3 on s3.match_id = m3.id
        where m3.tournament_id = tr.id
          and m3.is_demo = false
      ), tr.created_at) as latest_activity
    from public.tournaments tr
    join auth.users u on u.id = tr.owner_id
    where tr.visibility = 'public'
      and coalesce(u.is_anonymous, false) = false
  )
  select jsonb_build_object(
    'server_now_ms', (select now_ms from params),
    'live_matches', coalesce((
      select jsonb_agg(to_jsonb(lm.*) order by lm.last_event_at desc)
      from live_matches lm
    ), '[]'::jsonb),
    'recent_matches', coalesce((
      select jsonb_agg(to_jsonb(rm.*) order by rm.last_event_at desc)
      from recent_matches rm
    ), '[]'::jsonb),
    'tournaments', coalesce((
      select jsonb_agg(to_jsonb(pt.*) order by pt.live_match_count desc, pt.latest_activity desc)
      from (
        select t.* from public_tournaments t, params p
        where t.team_count >= 2
          and (
            t.live_match_count > 0
            or t.latest_activity >= p.now_ms - 1209600000 -- 14 days
            or (
              t.start_date is not null
              and t.end_date is not null
              and t.start_date <= p.now_ms
              and t.end_date >= p.now_ms - 86400000
            )
          )
        order by t.live_match_count desc, t.latest_activity desc
        limit 20
      ) pt
    ), '[]'::jsonb)
  );
$$;

grant execute on function public.get_live_feed(integer, integer) to anon, authenticated;

-- 6. Lightweight live count RPC for bottom-nav ambient indicator
create or replace function public.get_public_live_count()
returns integer
language sql
stable
security definer
set search_path = public, auth
as $$
  with params as (
    select (extract(epoch from now()) * 1000)::bigint as now_ms
  )
  select count(*)::int
  from public.matches m
  join public.match_live_summary s on s.match_id = m.id
  join auth.users u on u.id = m.owner_id
  left join public.tournaments tr on tr.id = m.tournament_id
  cross join params p
  where m.is_demo = false
    and coalesce(u.is_anonymous, false) = false
    and (m.visibility = 'public' or coalesce(tr.visibility, 'unlisted') = 'public')
    and s.balls_count > 0
    and s.status in ('live', 'inningsBreak')
    and (
      (m.is_test_match = false and s.last_event_at >= p.now_ms - 14400000)
      or (m.is_test_match = true and s.last_event_at >= p.now_ms - 86400000)
    );
$$;

grant execute on function public.get_public_live_count() to anon, authenticated;
