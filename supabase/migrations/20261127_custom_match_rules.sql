-- Crease — Gully / Tape-Ball Custom Match Rules
-- Adds last_man_stands and max_overs_per_bowler to matches and tournaments
-- (players_per_side already exists on both tables).

alter table public.tournaments
  add column if not exists last_man_stands boolean not null default false;

alter table public.tournaments
  add column if not exists max_overs_per_bowler smallint
    check (max_overs_per_bowler is null or max_overs_per_bowler >= 1);

alter table public.matches
  add column if not exists last_man_stands boolean not null default false;

alter table public.matches
  add column if not exists max_overs_per_bowler smallint
    check (max_overs_per_bowler is null or max_overs_per_bowler >= 1);

-- Refresh get_live_match_bundle so to_jsonb(m.*) includes the new rule columns
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
