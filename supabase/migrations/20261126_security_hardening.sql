-- Crease Security Hardening Migration (2026-11-26 — Strict Pre-Launch Edition)
-- Zero backwards-compatibility compromises required (empty pre-launch DB).
-- Fixes:
--   1. Private RLS-locked tables for team invite codes, match handover codes (30-min single-use TTL),
--      and persistent per-user rate-limiting (max 8 failed attempts / 15 min, committed via JSONB returns).
--   2. CSPRNG (pgcrypto) unbiased 6-digit code generation.
--   3. Drop unused claim_guest_data IDOR function.
--   4. Explicit column projections in get_live_match_bundle & public search RPCs; strip raw user_id/owner_id
--      from public payloads (expose boolean is_claimed instead).
--   5. Switch all 5 public search/lookup RPCs to SECURITY INVOKER with escaped ILIKE wildcards.
--   6. Fail-closed BEFORE INSERT/UPDATE guard triggers on matches, ball_events, players, teams, tournaments.
--   7. Strict URL allowlists (logo_url, avatar_url) + anti-DoS payload size & domain CHECK constraints.
--   8. Block anonymous JWTs on all write RLS policies, Storage policies, and privileged RPCs.
--   9. Principle of Least Privilege: revoke TRUNCATE, TRIGGER, REFERENCES, and anon write grants.

begin;

-- ============================================================================
-- 1. Private Secret-Code & Rate-Limit Tables (RLS enabled, ZERO policies, NOT in Realtime)
-- ============================================================================

create table if not exists public.team_invite_codes (
  team_id uuid primary key references public.teams(id) on delete cascade,
  join_code text not null unique check (join_code ~ '^[0-9]{6}$'),
  created_at bigint not null default (extract(epoch from now()) * 1000)::bigint,
  updated_at bigint not null default (extract(epoch from now()) * 1000)::bigint
);

alter table public.team_invite_codes enable row level security;
revoke all on public.team_invite_codes from public, anon, authenticated;

create table if not exists public.match_handover_codes (
  match_id uuid primary key references public.matches(id) on delete cascade,
  join_code text not null unique check (join_code ~ '^[0-9]{6}$'),
  created_by uuid references auth.users(id) on delete set null,
  created_at bigint not null default (extract(epoch from now()) * 1000)::bigint,
  expires_at bigint not null
);

alter table public.match_handover_codes enable row level security;
revoke all on public.match_handover_codes from public, anon, authenticated;

create table if not exists public.rpc_code_attempts (
  user_id uuid not null,
  scope text not null check (scope in ('team_invite', 'scorer_handover')),
  window_start bigint not null,
  failed_count integer not null default 0,
  primary key (user_id, scope)
);

alter table public.rpc_code_attempts enable row level security;
revoke all on public.rpc_code_attempts from public, anon, authenticated;

-- Drop exposed secret columns from public tables (idempotent)
drop index if exists public.idx_teams_join_code;
alter table public.teams drop column if exists join_code;

drop index if exists public.idx_matches_scorer_join_code;
alter table public.matches drop column if exists scorer_join_code;

-- ============================================================================
-- 2. Internal CSPRNG & Rate-Limit Helpers (Revoked from public/anon/authenticated)
-- ============================================================================

create or replace function public._generate_secure_6digit_code()
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_bytes bytea;
  v_num bigint;
begin
  loop
    v_bytes := extensions.gen_random_bytes(4);
    v_num := (get_byte(v_bytes, 0)::bigint << 24)
           | (get_byte(v_bytes, 1)::bigint << 16)
           | (get_byte(v_bytes, 2)::bigint << 8)
           | get_byte(v_bytes, 3)::bigint;
    -- Unbiased rejection sampling over 4,294,000,000 (exact multiple of 1,000,000)
    exit when v_num < 4294000000;
  end loop;
  return lpad((v_num % 1000000)::text, 6, '0');
end;
$$;

-- Returns 0 if allowed, or seconds remaining before lockout window expires.
create or replace function public._check_code_rate_limit(
  p_uid uuid,
  p_scope text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now bigint := (extract(epoch from now()) * 1000)::bigint;
  v_window_ms constant bigint := 900000; -- 15 minutes
  v_max_attempts constant integer := 8;
  v_row record;
  v_remaining_ms bigint;
begin
  select window_start, failed_count into v_row
  from public.rpc_code_attempts
  where user_id = p_uid and scope = p_scope;

  if not found then
    return 0;
  end if;

  if (v_now - v_row.window_start) >= v_window_ms then
    return 0;
  end if;

  if v_row.failed_count >= v_max_attempts then
    v_remaining_ms := v_window_ms - (v_now - v_row.window_start);
    return greatest(1, ceil(v_remaining_ms / 1000.0)::integer);
  end if;

  return 0;
end;
$$;

create or replace function public._record_code_attempt(
  p_uid uuid,
  p_scope text,
  p_success boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now bigint := (extract(epoch from now()) * 1000)::bigint;
  v_window_ms constant bigint := 900000; -- 15 minutes
begin
  if p_success then
    delete from public.rpc_code_attempts
    where user_id = p_uid and scope = p_scope;
    return;
  end if;

  insert into public.rpc_code_attempts (user_id, scope, window_start, failed_count)
  values (p_uid, p_scope, v_now, 1)
  on conflict (user_id, scope) do update
    set window_start = case
          when (v_now - public.rpc_code_attempts.window_start) >= v_window_ms then v_now
          else public.rpc_code_attempts.window_start
        end,
        failed_count = case
          when (v_now - public.rpc_code_attempts.window_start) >= v_window_ms then 1
          else public.rpc_code_attempts.failed_count + 1
        end;
end;
$$;

revoke all on function public._generate_secure_6digit_code() from public, anon, authenticated;
revoke all on function public._check_code_rate_limit(uuid, text) from public, anon, authenticated;
revoke all on function public._record_code_attempt(uuid, text, boolean) from public, anon, authenticated;

-- ============================================================================
-- 3. Drop Unused IDOR Function (claim_guest_data)
-- ============================================================================

drop function if exists public.claim_guest_data(uuid, uuid[], uuid[], uuid[]);

-- ============================================================================
-- 4. Explicit Column Projections in get_live_match_bundle (Zero UID / Secret Leakage)
-- ============================================================================

create or replace function public.get_live_match_bundle(p_match_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  with m as (
    select
      id, tournament_id, team_a_id, team_b_id, team_a, team_b,
      batting_first_side, overs_limit, players_per_side, format_label,
      opening_striker_1_id, opening_non_striker_1_id, opening_bowler_1_id,
      opening_striker_2_id, opening_non_striker_2_id, opening_bowler_2_id,
      team_a_player_ids, team_b_player_ids, ad_hoc_players,
      tournament_stage, fixture_index, is_test_match, declared_innings,
      follow_on_enforced, first_innings_target_override,
      is_demo, created_at
    from public.matches
    where id = p_match_id
    limit 1
  )
  select case
    when not exists (select 1 from m) then null
    else jsonb_build_object(
      'match', (select to_jsonb(m.*) from m),
      'teams', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', t.id,
          'name', t.name,
          'location', t.location,
          'profile_code', t.profile_code,
          'logo_url', t.logo_url,
          'created_at', t.created_at
        ))
        from public.teams t, m
        where t.id in (m.team_a_id, m.team_b_id)
      ), '[]'::jsonb),
      'players', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', p.id,
          'team_id', p.team_id,
          'is_claimed', (p.user_id is not null),
          'display_name', p.display_name,
          'role', p.role,
          'designation', p.designation,
          'member_role', p.member_role,
          'avatar_url', p.avatar_url,
          'archived', p.archived,
          'created_at', p.created_at,
          'updated_at', p.updated_at
        ))
        from public.players p, m
        where p.team_id in (m.team_a_id, m.team_b_id)
           or p.id = any(m.team_a_player_ids || m.team_b_player_ids)
      ), '[]'::jsonb),
      'events', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', b.id,
          'match_id', b.match_id,
          'innings_number', b.innings_number,
          'sequence_number', b.sequence_number,
          'striker_id', b.striker_id,
          'non_striker_id', b.non_striker_id,
          'bowler_id', b.bowler_id,
          'runs_off_bat', b.runs_off_bat,
          'extra_type', b.extra_type,
          'extra_runs', b.extra_runs,
          'is_wicket', b.is_wicket,
          'wicket_type', b.wicket_type,
          'dismissed_batter_id', b.dismissed_batter_id,
          'fielder_id', b.fielder_id,
          'next_batter_id', b.next_batter_id,
          'voided', b.voided,
          'created_at', b.created_at
        ) order by b.innings_number, b.sequence_number)
        from public.ball_events b
        where b.match_id = p_match_id
      ), '[]'::jsonb)
    )
  end;
$$;

revoke all on function public.get_live_match_bundle(uuid) from public;
grant execute on function public.get_live_match_bundle(uuid) to anon, authenticated;

-- ============================================================================
-- 5. Hardened Invite & Scorer Handover RPCs (CSPRNG + TTL + Committed Rate Limiting)
-- ============================================================================

create or replace function public.create_team_invite_code(p_team_id uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_now bigint := (extract(epoch from now()) * 1000)::bigint;
  v_code text;
begin
  if v_uid is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.teams where id = p_team_id and owner_id = v_uid
  ) then
    raise exception 'Only the team owner can invite teammates';
  end if;

  select join_code into v_code
  from public.team_invite_codes
  where team_id = p_team_id;

  if v_code is null then
    loop
      v_code := public._generate_secure_6digit_code();
      begin
        insert into public.team_invite_codes (team_id, join_code, created_at, updated_at)
        values (p_team_id, v_code, v_now, v_now)
        on conflict (team_id) do update
          set join_code = excluded.join_code,
              updated_at = excluded.updated_at;
        exit;
      exception when unique_violation then
      end;
    end loop;
  end if;

  return v_code;
end;
$$;

create or replace function public.reset_team_invite_code(p_team_id uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_now bigint := (extract(epoch from now()) * 1000)::bigint;
  v_code text;
begin
  if v_uid is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.teams where id = p_team_id and owner_id = v_uid
  ) then
    raise exception 'Only the team owner can reset the invite code';
  end if;

  loop
    v_code := public._generate_secure_6digit_code();
    begin
      insert into public.team_invite_codes (team_id, join_code, created_at, updated_at)
      values (p_team_id, v_code, v_now, v_now)
      on conflict (team_id) do update
        set join_code = excluded.join_code,
            updated_at = excluded.updated_at;
      exit;
    exception when unique_violation then
    end;
  end loop;

  return v_code;
end;
$$;

-- Returns structured JSONB (ok: true|false) so rate-limit increments COMMIT cleanly.
create or replace function public.preview_team_by_code(p_join_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text := regexp_replace(coalesce(p_join_code, ''), '[^0-9]', '', 'g');
  v_retry_after integer;
  v_team record;
  v_players jsonb;
  v_my_player_id uuid;
begin
  if v_uid is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    return jsonb_build_object('ok', false, 'error', 'auth_required');
  end if;

  v_retry_after := public._check_code_rate_limit(v_uid, 'team_invite');
  if v_retry_after > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'rate_limited',
      'retry_after_seconds', v_retry_after
    );
  end if;

  if length(v_clean) <> 6 then
    perform public._record_code_attempt(v_uid, 'team_invite', false);
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  select t.id, t.name into v_team
  from public.team_invite_codes tic
  join public.teams t on t.id = tic.team_id
  where tic.join_code = v_clean
  limit 1;

  if v_team.id is null then
    perform public._record_code_attempt(v_uid, 'team_invite', false);
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  perform public._record_code_attempt(v_uid, 'team_invite', true);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'display_name', p.display_name,
      'role', p.role,
      'designation', p.designation,
      'is_claimed', (p.user_id is not null),
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
    'ok', true,
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
  v_retry_after integer;
  v_team record;
  v_player record;
  v_claimed_id uuid;
  v_claimed_name text;
begin
  if v_uid is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    return jsonb_build_object('ok', false, 'error', 'auth_required');
  end if;

  v_retry_after := public._check_code_rate_limit(v_uid, 'team_invite');
  if v_retry_after > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'rate_limited',
      'retry_after_seconds', v_retry_after
    );
  end if;

  if length(v_clean) <> 6 then
    perform public._record_code_attempt(v_uid, 'team_invite', false);
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  select t.id, t.name, t.owner_id into v_team
  from public.team_invite_codes tic
  join public.teams t on t.id = tic.team_id
  where tic.join_code = v_clean
  limit 1
  for update of t;

  if v_team.id is null then
    perform public._record_code_attempt(v_uid, 'team_invite', false);
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  perform public._record_code_attempt(v_uid, 'team_invite', true);

  if p_player_id is not null then
    select id, display_name, user_id into v_player
    from public.players
    where id = p_player_id
      and team_id = v_team.id
      and archived = false
    for update;

    if v_player.id is null then
      return jsonb_build_object('ok', false, 'error', 'player_not_found');
    end if;

    if v_player.user_id is not null and v_player.user_id <> v_uid then
      return jsonb_build_object('ok', false, 'error', 'already_claimed');
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
    if v_name = '' or length(v_name) > 80 then
      return jsonb_build_object('ok', false, 'error', 'invalid_name');
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
    'ok', true,
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
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_now bigint := (extract(epoch from now()) * 1000)::bigint;
  v_ttl_ms constant bigint := 1800000; -- 30 minutes
  v_code text;
  v_allowed boolean;
begin
  if v_uid is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
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

  delete from public.match_handover_codes where expires_at <= v_now;

  select join_code into v_code
  from public.match_handover_codes
  where match_id = p_match_id
    and expires_at > v_now;

  if v_code is null then
    loop
      v_code := public._generate_secure_6digit_code();
      begin
        insert into public.match_handover_codes (match_id, join_code, created_by, created_at, expires_at)
        values (p_match_id, v_code, v_uid, v_now, v_now + v_ttl_ms)
        on conflict (match_id) do update
          set join_code = excluded.join_code,
              created_by = excluded.created_by,
              created_at = excluded.created_at,
              expires_at = excluded.expires_at;
        exit;
      exception when unique_violation then
      end;
    end loop;
  end if;

  insert into public.match_scorers (match_id, user_id, role, joined_at)
  values (p_match_id, v_uid, 'owner', v_now)
  on conflict (match_id, user_id) do nothing;

  return v_code;
end;
$$;

-- Return type upgraded from uuid -> jsonb so rate-limit increments COMMIT cleanly
drop function if exists public.claim_scorer_baton(text);
create or replace function public.claim_scorer_baton(p_join_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_now bigint := (extract(epoch from now()) * 1000)::bigint;
  v_clean text := regexp_replace(coalesce(p_join_code, ''), '[^0-9]', '', 'g');
  v_retry_after integer;
  v_match_id uuid;
begin
  if v_uid is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    return jsonb_build_object('ok', false, 'error', 'auth_required');
  end if;

  v_retry_after := public._check_code_rate_limit(v_uid, 'scorer_handover');
  if v_retry_after > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'rate_limited',
      'retry_after_seconds', v_retry_after
    );
  end if;

  if length(v_clean) <> 6 then
    perform public._record_code_attempt(v_uid, 'scorer_handover', false);
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  select match_id into v_match_id
  from public.match_handover_codes
  where join_code = v_clean
    and expires_at > v_now
  limit 1
  for update;

  if v_match_id is null then
    perform public._record_code_attempt(v_uid, 'scorer_handover', false);
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  perform public._record_code_attempt(v_uid, 'scorer_handover', true);

  insert into public.match_scorers (match_id, user_id, role, joined_at)
  values (v_match_id, v_uid, 'scorer', v_now)
  on conflict (match_id, user_id) do nothing;

  update public.matches set active_scorer_id = v_uid where id = v_match_id;

  -- Single-use handover code: consume immediately on claim
  delete from public.match_handover_codes where match_id = v_match_id;

  return jsonb_build_object('ok', true, 'match_id', v_match_id);
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
  if v_uid is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
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

-- ============================================================================
-- 6. Public Search & Lookup RPCs -> SECURITY INVOKER + Escaped ILIKE + No Raw UIDs
--    (Clears all 5 anon_security_definer_function_executable Advisor warnings)
-- ============================================================================

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
security invoker
set search_path = public
as $$
  with q as (
    select
      length(regexp_replace(trim(coalesce(p_query, '')), '[%_\\]', '', 'g')) as clean_len,
      replace(replace(replace(trim(coalesce(p_query, '')), '\', '\\'), '%', '\%'), '_', '\_') as escaped
  )
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
          'is_claimed', (p.user_id is not null),
          'avatar_url', p.avatar_url
        ) order by p.created_at asc
      )
      from public.players p
      where p.team_id = t.id
        and p.archived = false
    ), '[]'::jsonb) as players
  from public.teams t, q
  where q.clean_len >= 2
    and t.owner_id is not null
    and t.name ilike '%' || q.escaped || '%' escape '\'
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
security invoker
set search_path = public
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
          'is_claimed', (p.user_id is not null),
          'avatar_url', p.avatar_url
        ) order by p.created_at asc
      )
      from public.players p
      where p.team_id = t.id
        and p.archived = false
    ), '[]'::jsonb) as players
  from public.teams t
  where t.owner_id is not null
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
security invoker
set search_path = public
as $$
  with q as (
    select
      length(regexp_replace(trim(coalesce(p_query, '')), '[%_\\]', '', 'g')) as clean_len,
      replace(replace(replace(trim(coalesce(p_query, '')), '\', '\\'), '%', '\%'), '_', '\_') as escaped
  )
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
  cross join q
  where q.clean_len >= 2
    and p.archived = false
    and t.owner_id is not null
    and p.display_name ilike '%' || q.escaped || '%' escape '\'
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
security invoker
set search_path = public
as $$
  with q as (
    select
      length(regexp_replace(trim(coalesce(p_query, '')), '[%_\\]', '', 'g')) as clean_len,
      replace(replace(replace(trim(coalesce(p_query, '')), '\', '\\'), '%', '\%'), '_', '\_') as escaped
  )
  select
    m.id,
    coalesce(ta.name, m.team_a) as team_a,
    coalesce(tb.name, m.team_b) as team_b,
    m.format_label,
    m.created_at
  from public.matches m
  left join public.teams ta on ta.id = m.team_a_id
  left join public.teams tb on tb.id = m.team_b_id
  cross join q
  where q.clean_len >= 2
    and m.is_demo = false
    and m.owner_id is not null
    and (
      coalesce(ta.name, m.team_a) ilike '%' || q.escaped || '%' escape '\'
      or coalesce(tb.name, m.team_b) ilike '%' || q.escaped || '%' escape '\'
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
security invoker
set search_path = public
as $$
  with q as (
    select
      length(regexp_replace(trim(coalesce(p_query, '')), '[%_\\]', '', 'g')) as clean_len,
      replace(replace(replace(trim(coalesce(p_query, '')), '\', '\\'), '%', '\%'), '_', '\_') as escaped
  )
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
  from public.tournaments tr, q
  where q.clean_len >= 2
    and tr.owner_id is not null
    and (
      tr.name ilike '%' || q.escaped || '%' escape '\'
      or coalesce(tr.location, '') ilike '%' || q.escaped || '%' escape '\'
    )
  order by tr.created_at desc
  limit greatest(1, least(coalesce(p_limit, 10), 30));
$$;

revoke all on function public.search_public_teams(text, integer) from public;
grant execute on function public.search_public_teams(text, integer) to anon, authenticated;

revoke all on function public.lookup_team_by_profile_code(text) from public;
grant execute on function public.lookup_team_by_profile_code(text) to anon, authenticated;

revoke all on function public.search_public_players(text, integer) from public;
grant execute on function public.search_public_players(text, integer) to anon, authenticated;

revoke all on function public.search_public_matches(text, integer) from public;
grant execute on function public.search_public_matches(text, integer) to anon, authenticated;

revoke all on function public.search_public_tournaments(text, integer) from public;
grant execute on function public.search_public_tournaments(text, integer) to anon, authenticated;

-- ============================================================================
-- 7. Fail-Closed Column Integrity Guard Triggers
-- ============================================================================

create or replace function public.guard_matches_write()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.tournament_id is not null and not exists (
      select 1 from public.tournaments tr
      where tr.id = new.tournament_id
        and tr.owner_id = v_uid
    ) then
      raise exception 'Not authorized to link match to this tournament';
    end if;

    if new.active_scorer_id is not null and new.active_scorer_id is distinct from v_uid then
      raise exception 'Cannot set active_scorer_id to another user on insert';
    end if;

    return new;
  end if;

  -- UPDATE: fail loudly on immutable or privileged column tampering
  if new.owner_id is distinct from old.owner_id then
    raise exception 'Cannot modify match owner_id';
  end if;

  if new.created_at is distinct from old.created_at then
    raise exception 'Cannot modify match created_at';
  end if;

  if new.active_scorer_id is distinct from old.active_scorer_id then
    raise exception 'Use scorer handover RPCs to transfer active_scorer_id';
  end if;

  if old.owner_id is distinct from v_uid then
    if new.tournament_id is distinct from old.tournament_id
       or new.is_demo is distinct from old.is_demo then
      raise exception 'Only the match owner can modify tournament linkage or demo flag';
    end if;
  elsif new.tournament_id is distinct from old.tournament_id
        and new.tournament_id is not null then
    if not exists (
      select 1 from public.tournaments tr
      where tr.id = new.tournament_id
        and tr.owner_id = v_uid
    ) then
      raise exception 'Not authorized to link match to this tournament';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_matches_write on public.matches;
create trigger trg_guard_matches_write
  before insert or update on public.matches
  for each row
  execute function public.guard_matches_write();

create or replace function public.guard_ball_events_write()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.match_id is distinct from old.match_id
     or new.owner_id is distinct from old.owner_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Cannot modify ball event match_id, owner_id, or created_at';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_ball_events_write on public.ball_events;
create trigger trg_guard_ball_events_write
  before update on public.ball_events
  for each row
  execute function public.guard_ball_events_write();

create or replace function public.guard_players_write()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_is_team_owner boolean;
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.user_id is not null and new.user_id is distinct from v_uid then
      if not exists (
        select 1 from public.players existing
        where existing.id = new.id
          and existing.team_id = new.team_id
          and existing.user_id = new.user_id
      ) then
        raise exception 'Cannot link another user directly; teammates must claim their spot with an invite code';
      end if;
    end if;
    return new;
  end if;

  if new.team_id is distinct from old.team_id then
    raise exception 'Cannot move player to another team';
  end if;

  if new.owner_id is distinct from old.owner_id then
    raise exception 'Cannot modify player owner_id';
  end if;

  if new.created_at is distinct from old.created_at then
    raise exception 'Cannot modify player created_at';
  end if;

  select exists (
    select 1 from public.teams t
    where t.id = old.team_id
      and t.owner_id = v_uid
  ) into v_is_team_owner;

  if v_is_team_owner then
    if new.user_id is distinct from old.user_id then
      if new.user_id is not null and not (new.user_id = v_uid and old.user_id is null) then
        raise exception 'Cannot assign another user to a player slot';
      end if;
    end if;
    return new;
  end if;

  if old.user_id is distinct from v_uid then
    raise exception 'Not authorized to update this player';
  end if;

  if new.role is distinct from old.role
     or new.designation is distinct from old.designation
     or new.member_role is distinct from old.member_role
     or new.archived is distinct from old.archived then
    raise exception 'Only the team owner can modify squad role, designation, or archive status';
  end if;

  if new.user_id is distinct from old.user_id and new.user_id is not null then
    raise exception 'Cannot transfer a claimed player spot to another user';
  end if;

  if new.user_id is null then
    new.claimed_at := null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_players_write on public.players;
create trigger trg_guard_players_write
  before insert or update on public.players
  for each row
  execute function public.guard_players_write();

create or replace function public.guard_owned_entity_update()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.owner_id is distinct from old.owner_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Cannot modify owner_id or created_at';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_teams_update on public.teams;
create trigger trg_guard_teams_update
  before update on public.teams
  for each row
  execute function public.guard_owned_entity_update();

drop trigger if exists trg_guard_tournaments_update on public.tournaments;
create trigger trg_guard_tournaments_update
  before update on public.tournaments
  for each row
  execute function public.guard_owned_entity_update();

revoke all on function public.guard_matches_write() from public, anon, authenticated;
revoke all on function public.guard_ball_events_write() from public, anon, authenticated;
revoke all on function public.guard_players_write() from public, anon, authenticated;
revoke all on function public.guard_owned_entity_update() from public, anon, authenticated;

-- ============================================================================
-- 8. URL Allowlists & Anti-DoS Domain CHECK Constraints
-- ============================================================================

alter table public.teams
  drop constraint if exists teams_logo_url_safe_check,
  add constraint teams_logo_url_safe_check check (
    logo_url is null
    or (
      length(logo_url) <= 512
      and logo_url ~ '^https://ajwqkcblakfojsbyqjqt\.supabase\.co/storage/v1/object/public/avatars/[0-9a-fA-F-]+/[A-Za-z0-9._-]+(\?v=[0-9]+)?$'
    )
  ),
  drop constraint if exists teams_text_bounds_check,
  add constraint teams_text_bounds_check check (
    length(name) <= 80
    and (location is null or length(location) <= 120)
    and (profile_code is null or length(profile_code) <= 20)
  );

alter table public.players
  drop constraint if exists players_avatar_url_safe_check,
  add constraint players_avatar_url_safe_check check (
    avatar_url is null
    or (
      length(avatar_url) <= 1024
      and avatar_url ~ '^https://(ajwqkcblakfojsbyqjqt\.supabase\.co/storage/v1/object/public/avatars/[0-9a-fA-F-]+/[A-Za-z0-9._-]+(\?v=[0-9]+)?|lh[3-6]\.googleusercontent\.com/[^\s"''<>]+)$'
    )
  ),
  drop constraint if exists players_name_bounds_check,
  add constraint players_name_bounds_check check (
    length(display_name) <= 80
  );

alter table public.tournaments
  drop constraint if exists tournaments_bounds_check,
  add constraint tournaments_bounds_check check (
    length(name) <= 100
    and (location is null or length(location) <= 120)
    and length(format_label) <= 40
    and overs_limit <= 500
  );

alter table public.matches
  drop constraint if exists matches_bounds_check,
  add constraint matches_bounds_check check (
    length(team_a) <= 80
    and length(team_b) <= 80
    and length(format_label) <= 40
    and overs_limit <= 500
    and cardinality(team_a_player_ids) <= 30
    and cardinality(team_b_player_ids) <= 30
    and cardinality(declared_innings) <= 8
    and pg_column_size(ad_hoc_players) <= 16384
  );

alter table public.ball_events
  drop constraint if exists ball_events_bounds_check,
  add constraint ball_events_bounds_check check (
    runs_off_bat <= 12
    and extra_runs <= 12
  );

-- ============================================================================
-- 9. Hardened RLS Policies (Block Anonymous JWTs + Cross-Tenant Integrity)
-- ============================================================================

-- Teams
drop policy if exists "teams_insert_own" on public.teams;
create policy "teams_insert_own" on public.teams for insert to authenticated
  with check (
    (select auth.uid()) = owner_id
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
  );

drop policy if exists "teams_update_own" on public.teams;
create policy "teams_update_own" on public.teams for update to authenticated
  using (
    (select auth.uid()) = owner_id
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
  )
  with check (
    (select auth.uid()) = owner_id
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
  );

drop policy if exists "teams_delete_own" on public.teams;
create policy "teams_delete_own" on public.teams for delete to authenticated
  using (
    (select auth.uid()) = owner_id
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
  );

-- Players
drop policy if exists "players_insert_owner" on public.players;
create policy "players_insert_owner" on public.players for insert to authenticated
  with check (
    (select auth.uid()) = owner_id
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
    and exists (
      select 1 from public.teams t
      where t.id = players.team_id
        and t.owner_id = (select auth.uid())
    )
  );

drop policy if exists "players_update_owner_or_self" on public.players;
create policy "players_update_owner_or_self" on public.players for update to authenticated
  using (
    coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
    and (
      (select auth.uid()) = user_id
      or exists (
        select 1 from public.teams t
        where t.id = players.team_id
          and t.owner_id = (select auth.uid())
      )
    )
  )
  with check (
    coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
    and (
      (select auth.uid()) = user_id
      or user_id is null
      or exists (
        select 1 from public.teams t
        where t.id = players.team_id
          and t.owner_id = (select auth.uid())
      )
    )
  );

drop policy if exists "players_delete_owner" on public.players;
create policy "players_delete_owner" on public.players for delete to authenticated
  using (
    coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
    and exists (
      select 1 from public.teams t
      where t.id = players.team_id
        and t.owner_id = (select auth.uid())
    )
  );

-- Tournaments
drop policy if exists "tournaments_insert_own" on public.tournaments;
create policy "tournaments_insert_own" on public.tournaments for insert to authenticated
  with check (
    (select auth.uid()) = owner_id
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
  );

drop policy if exists "tournaments_update_own" on public.tournaments;
create policy "tournaments_update_own" on public.tournaments for update to authenticated
  using (
    (select auth.uid()) = owner_id
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
  )
  with check (
    (select auth.uid()) = owner_id
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
  );

drop policy if exists "tournaments_delete_own" on public.tournaments;
create policy "tournaments_delete_own" on public.tournaments for delete to authenticated
  using (
    (select auth.uid()) = owner_id
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
  );

-- Tournament Teams
drop policy if exists "tournament_teams_insert_owner" on public.tournament_teams;
create policy "tournament_teams_insert_owner" on public.tournament_teams for insert to authenticated
  with check (
    coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
    and exists (
      select 1 from public.tournaments tr
      where tr.id = tournament_teams.tournament_id
        and tr.owner_id = (select auth.uid())
    )
  );

drop policy if exists "tournament_teams_update_owner" on public.tournament_teams;
create policy "tournament_teams_update_owner" on public.tournament_teams for update to authenticated
  using (
    coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
    and exists (
      select 1 from public.tournaments tr
      where tr.id = tournament_teams.tournament_id
        and tr.owner_id = (select auth.uid())
    )
  )
  with check (
    coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
    and exists (
      select 1 from public.tournaments tr
      where tr.id = tournament_teams.tournament_id
        and tr.owner_id = (select auth.uid())
    )
  );

drop policy if exists "tournament_teams_delete_owner" on public.tournament_teams;
create policy "tournament_teams_delete_owner" on public.tournament_teams for delete to authenticated
  using (
    coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
    and exists (
      select 1 from public.tournaments tr
      where tr.id = tournament_teams.tournament_id
        and tr.owner_id = (select auth.uid())
    )
  );

-- Matches
drop policy if exists "matches_insert_own" on public.matches;
create policy "matches_insert_own" on public.matches for insert to authenticated
  with check (
    (select auth.uid()) = owner_id
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
    and (
      tournament_id is null
      or exists (
        select 1 from public.tournaments tr
        where tr.id = matches.tournament_id
          and tr.owner_id = (select auth.uid())
      )
    )
  );

drop policy if exists "matches_update_authorized" on public.matches;
create policy "matches_update_authorized" on public.matches for update to authenticated
  using (
    coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
    and (
      (select auth.uid()) = owner_id
      or (select auth.uid()) = active_scorer_id
      or exists (
        select 1 from public.match_scorers ms
        where ms.match_id = matches.id
          and ms.user_id = (select auth.uid())
      )
    )
  )
  with check (
    coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
    and (
      (select auth.uid()) = owner_id
      or (select auth.uid()) = active_scorer_id
      or exists (
        select 1 from public.match_scorers ms
        where ms.match_id = matches.id
          and ms.user_id = (select auth.uid())
      )
    )
  );

drop policy if exists "matches_delete_own" on public.matches;
create policy "matches_delete_own" on public.matches for delete to authenticated
  using (
    (select auth.uid()) = owner_id
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
  );

-- Ball Events
drop policy if exists "ball_events_insert_authorized" on public.ball_events;
create policy "ball_events_insert_authorized" on public.ball_events for insert to authenticated
  with check (
    (select auth.uid()) = owner_id
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
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

drop policy if exists "ball_events_update_authorized" on public.ball_events;
create policy "ball_events_update_authorized" on public.ball_events for update to authenticated
  using (
    coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
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
  )
  with check (
    coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
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

drop policy if exists "ball_events_delete_authorized" on public.ball_events;
create policy "ball_events_delete_authorized" on public.ball_events for delete to authenticated
  using (
    coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
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

-- Storage (avatars bucket)
drop policy if exists "avatars_owner_insert" on storage.objects;
create policy "avatars_owner_insert" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = ((select auth.uid())::text)
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
  );

drop policy if exists "avatars_owner_update" on storage.objects;
create policy "avatars_owner_update" on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = ((select auth.uid())::text)
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = ((select auth.uid())::text)
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
  );

drop policy if exists "avatars_owner_delete" on storage.objects;
create policy "avatars_owner_delete" on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = ((select auth.uid())::text)
    and coalesce((select (auth.jwt() ->> 'is_anonymous')::boolean), false) = false
  );

-- ============================================================================
-- 10. Principle of Least Privilege — Revoke TRUNCATE / TRIGGER / Excess Grants
-- ============================================================================

revoke all on table
  public.teams,
  public.players,
  public.tournaments,
  public.tournament_teams,
  public.matches,
  public.match_scorers,
  public.ball_events,
  public.team_invite_codes,
  public.match_handover_codes,
  public.rpc_code_attempts
from public, anon, authenticated;

grant select on table
  public.teams,
  public.players,
  public.tournaments,
  public.tournament_teams,
  public.matches,
  public.ball_events
to anon;

grant select, insert, update, delete on table
  public.teams,
  public.players,
  public.tournaments,
  public.tournament_teams,
  public.matches,
  public.ball_events
to authenticated;

grant select on table public.match_scorers to authenticated;

commit;
