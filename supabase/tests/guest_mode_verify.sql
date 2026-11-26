-- Repeatable, zero-side-effect transactional verification suite for Crease
-- guest mode, claim_guest_data RPC, and anonymous-filtered public search RPCs.
-- Safe to run against staging or production: wraps everything in BEGIN/ROLLBACK.

begin;

do $$
declare
  v_guest uuid := gen_random_uuid();
  v_reg uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_res jsonb;
  v_team_players jsonb;
  v_team_meta jsonb;
  v_team_loc text;
  v_match_a_id text;
  v_match_b_id text;
  v_match_owner uuid;
  v_ball_owner uuid;
  v_coscored_active uuid;
  v_coscored_ball_owner uuid;
  v_member_team text;
  v_member_uid uuid;
  v_cnt int;
begin
  -- 1. Seed 3 synthetic users (guest, registered, third-party owner)
  insert into auth.users (id, aud, role, is_anonymous, created_at, updated_at)
  values
    (v_guest, 'authenticated', 'authenticated', true, now(), now()),
    (v_reg,   'authenticated', 'authenticated', false, now(), now()),
    (v_other, 'authenticated', 'authenticated', false, now(), now());

  -- 2. Registered user already owns "Bhatti XI" (captain meta, empty location)
  insert into public.teams (id, owner_id, name, players, player_meta, location, created_at)
  values (
    '__verify_reg_bhatti',
    v_reg,
    'Bhatti XI',
    '["Sheran", "Abdur"]'::jsonb,
    '{"Sheran": {"role": "Batter", "designation": "C"}}'::jsonb,
    null,
    1000
  );

  -- 3. Guest created colliding "  bhatti xi " and unique "Zebra999 Guest"
  insert into public.teams (id, owner_id, name, players, player_meta, location, created_at)
  values
    (
      '__verify_guest_bhatti',
      v_guest,
      '  bhatti xi ',
      '["abdur", "Usama"]'::jsonb,
      '{"Sheran": {"role": "Bowler"}, "Usama": {"role": "Bowler"}}'::jsonb,
      'Dhamial',
      2000
    ),
    (
      '__verify_guest_unique',
      v_guest,
      'Zebra999 Guest',
      '["ZebraPlayerGuest"]'::jsonb,
      '{}'::jsonb,
      'Lahore',
      2001
    );

  insert into public.team_members (team_id, player_name, user_id, role, joined_at)
  values ('__verify_guest_bhatti', 'Usama', v_guest, 'player', 2002);

  -- 4. Guest scored a same-name derby match & co-scored someone else's match
  insert into public.matches (
    id, owner_id, active_scorer_id, team_a, team_b, team_a_id, team_b_id,
    overs_limit, format_label, batting_first_team,
    opening_striker_1, opening_non_striker_1, opening_bowler_1, is_demo, created_at
  ) values (
    '__verify_guest_match', v_guest, v_guest, 'Zebra999 Guest', 'Bhatti xi',
    '__verify_guest_bhatti', '__verify_public_opp',
    6, '6OV', 'Zebra999 Guest', 'Sheran', 'Usama', 'Test', false, 3000
  );

  insert into public.ball_events (
    id, match_id, owner_id, innings_number, sequence_number,
    striker, non_striker, bowler, runs_off_bat, created_at
  ) values (
    '__verify_ball_1', '__verify_guest_match', v_guest, 1, 1,
    'Sheran', 'Usama', 'Test', 6, 3001
  );

  insert into public.matches (
    id, owner_id, active_scorer_id, team_a, team_b,
    overs_limit, format_label, batting_first_team,
    opening_striker_1, opening_non_striker_1, opening_bowler_1, is_demo, created_at
  ) values (
    '__verify_coscored_match', v_other, v_guest, 'Alpha', 'Beta',
    6, '6OV', 'Alpha', 'A1', 'A2', 'B1', false, 4000
  );
  insert into public.match_scorers (match_id, user_id, role, joined_at)
  values ('__verify_coscored_match', v_guest, 'scorer', 4001);
  insert into public.ball_events (
    id, match_id, owner_id, innings_number, sequence_number,
    striker, non_striker, bowler, runs_off_bat, created_at
  ) values (
    '__verify_ball_coscored', '__verify_coscored_match', v_guest, 1, 1,
    'A1', 'A2', 'B1', 4, 4002
  );

  insert into public.tournaments (
    id, owner_id, name, overs_limit, format_label, created_at
  ) values (
    '__verify_guest_cup', v_guest, 'Zebra999 Guest Cup', 6, '6OV', 5000
  );

  -- 5. Verify anonymous records are excluded from all 4 public search RPCs BEFORE claim
  select count(*) into v_cnt from public.search_public_teams('Zebra999', 15) where id = '__verify_guest_unique';
  assert v_cnt = 0, 'anonymous team leaked into search_public_teams';

  select count(*) into v_cnt from public.search_public_matches('Zebra999', 10) where id = '__verify_guest_match';
  assert v_cnt = 0, 'anonymous match leaked into search_public_matches';

  select count(*) into v_cnt from public.search_public_tournaments('Zebra999', 10) where id = '__verify_guest_cup';
  assert v_cnt = 0, 'anonymous tournament leaked into search_public_tournaments';

  select count(*) into v_cnt from public.search_public_players('ZebraPlayerGuest', 15) where player_name = 'ZebraPlayerGuest';
  assert v_cnt = 0, 'anonymous player leaked into search_public_players';

  -- 6. Impersonate registered user and invoke claim_guest_data
  perform set_config('request.jwt.claim.sub', v_reg::text, true);

  v_res := public.claim_guest_data(
    v_guest,
    array['__verify_guest_match', '__verify_coscored_match'],
    array['__verify_guest_bhatti', '__verify_guest_unique'],
    array['__verify_guest_cup']
  );

  assert (v_res->>'matches_claimed')::int = 1, format('expected 1 match claimed: %s', v_res);
  assert (v_res->>'ball_events_claimed')::int = 2, format('expected 2 ball_events claimed: %s', v_res);
  assert (v_res->>'teams_claimed')::int = 1, format('expected 1 unique team claimed: %s', v_res);
  assert (v_res->>'tournaments_claimed')::int = 1, format('expected 1 tournament claimed: %s', v_res);
  assert (v_res->'merged_team_map'->>'__verify_guest_bhatti') = '__verify_reg_bhatti', format('bad merged_team_map: %s', v_res);

  -- 7. Verify merged team fields, match team ID repointing, ball_events, and team_members
  select players, player_meta, location
    into v_team_players, v_team_meta, v_team_loc
    from public.teams where id = '__verify_reg_bhatti';
  assert v_team_players = '["Sheran", "Abdur", "Usama"]'::jsonb, format('bad merged players: %s', v_team_players);
  assert v_team_meta->'Sheran'->>'role' = 'Batter', format('existing meta overwritten: %s', v_team_meta);
  assert v_team_meta->'Usama'->>'role' = 'Bowler', format('guest meta lost: %s', v_team_meta);
  assert v_team_loc = 'Dhamial', format('guest location lost: %s', v_team_loc);

  select owner_id, team_a_id, team_b_id
    into v_match_owner, v_match_a_id, v_match_b_id
    from public.matches where id = '__verify_guest_match';
  assert v_match_owner = v_reg, 'match owner not transferred';
  assert v_match_a_id = '__verify_reg_bhatti', format('team_a_id not repointed: %s', v_match_a_id);
  assert v_match_b_id = '__verify_public_opp', format('team_b_id wrongly changed: %s', v_match_b_id);

  select owner_id into v_ball_owner from public.ball_events where id = '__verify_ball_1';
  assert v_ball_owner = v_reg, 'ball_events owner_id not transferred';

  select active_scorer_id into v_coscored_active from public.matches where id = '__verify_coscored_match';
  assert v_coscored_active = v_reg, 'co-scored active_scorer_id not transferred';

  select owner_id into v_coscored_ball_owner from public.ball_events where id = '__verify_ball_coscored';
  assert v_coscored_ball_owner = v_reg, 'co-scored ball_events owner_id not transferred';

  select team_id, user_id into v_member_team, v_member_uid
    from public.team_members where player_name = 'Usama';
  assert v_member_team = '__verify_reg_bhatti' and v_member_uid = v_reg,
    format('team_member not migrated: team=%s uid=%s', v_member_team, v_member_uid);

  -- 8. Verify claimed records ARE now discoverable in all 4 public search RPCs AFTER claim
  select count(*) into v_cnt from public.search_public_teams('Zebra999', 15) where id = '__verify_guest_unique';
  assert v_cnt = 1, 'claimed team missing from search_public_teams';

  select count(*) into v_cnt from public.search_public_matches('Zebra999', 10) where id = '__verify_guest_match';
  assert v_cnt = 1, 'claimed match missing from search_public_matches';

  select count(*) into v_cnt from public.search_public_tournaments('Zebra999', 10) where id = '__verify_guest_cup';
  assert v_cnt = 1, 'claimed tournament missing from search_public_tournaments';

  select count(*) into v_cnt from public.search_public_players('ZebraPlayerGuest', 15) where player_name = 'ZebraPlayerGuest';
  assert v_cnt = 1, 'claimed player missing from search_public_players';

  -- 9. Verify Team Profile ID auto-generation & exact lookup_team_by_profile_code
  declare
    v_reg_code text;
    v_found_id text;
  begin
    select profile_code into v_reg_code from public.teams where id = '__verify_reg_bhatti';
    assert v_reg_code is not null and v_reg_code ~ '^[A-Z0-9]{2}-[A-Z0-9]{4,5}$',
      format('invalid auto profile_code: %s', v_reg_code);

    -- Lookup works with exact code AND lowercase unhyphenated code
    select id into v_found_id from public.lookup_team_by_profile_code(v_reg_code);
    assert v_found_id = '__verify_reg_bhatti', format('exact code lookup failed: %s', v_found_id);

    select id into v_found_id from public.lookup_team_by_profile_code(lower(replace(v_reg_code, '-', '')));
    assert v_found_id = '__verify_reg_bhatti', format('normalized code lookup failed: %s', v_found_id);
  end;
end $$;

rollback;
select 'ALL_GUEST_MODE_SQL_VERIFICATIONS_PASSED' as status;
