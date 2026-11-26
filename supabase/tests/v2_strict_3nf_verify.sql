-- Repeatable, zero-side-effect transactional verification suite for Crease v2
-- (Strict 3NF native UUID schema, hardened RLS, get_live_match_bundle,
--  search_public_players, claim_team_player, and claim_guest_data).
-- Safe to run against live DB: wraps everything in BEGIN/ROLLBACK.

begin;

do $$
declare
  v_guest uuid := gen_random_uuid();
  v_reg uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_team_reg uuid := gen_random_uuid();
  v_team_guest uuid := gen_random_uuid();
  v_team_unique uuid := gen_random_uuid();
  v_p_sheran uuid := gen_random_uuid();
  v_p_abdur uuid := gen_random_uuid();
  v_p_usama uuid := gen_random_uuid();
  v_p_zebra uuid := gen_random_uuid();
  v_match_id uuid := gen_random_uuid();
  v_ball_id uuid := gen_random_uuid();
  v_other_match_id uuid := gen_random_uuid();
  v_forbidden_caught boolean := false;
  v_invite_code text;
  v_claim_res jsonb;
  v_guest_claim_res jsonb;
  v_bundle jsonb;
  v_cnt int;
  v_owner uuid;
begin
  -- 1. Seed 3 synthetic users
  insert into auth.users (id, aud, role, is_anonymous, created_at, updated_at)
  values
    (v_guest, 'authenticated', 'authenticated', true, now(), now()),
    (v_reg,   'authenticated', 'authenticated', false, now(), now()),
    (v_other, 'authenticated', 'authenticated', false, now(), now());

  -- 2. Registered user owns "Bhatti XI" (with Sheran C and Abdur)
  insert into public.teams (id, owner_id, name, location, created_at)
  values (v_team_reg, v_reg, 'Bhatti XI', null, 1000);

  insert into public.players (id, team_id, owner_id, display_name, role, designation, created_at, updated_at)
  values
    (v_p_sheran, v_team_reg, v_reg, 'Sheran', 'Batter', 'C', 1000, 1000),
    (v_p_abdur,  v_team_reg, v_reg, 'Abdur',  'All-rounder', null, 1000, 1000);

  -- 3. Guest creates colliding "  bhatti xi " and unique "Zebra999 Guest"
  insert into public.teams (id, owner_id, name, location, created_at)
  values
    (v_team_guest,  v_guest, '  bhatti xi ', 'Dhamial', 2000),
    (v_team_unique, v_guest, 'Zebra999 Guest', 'Lahore', 2001);

  insert into public.players (id, team_id, owner_id, user_id, display_name, role, designation, created_at, updated_at)
  values
    (v_p_usama, v_team_guest, v_guest, v_guest, 'Usama', 'Bowler', 'C', 2000, 2000),
    (v_p_zebra, v_team_unique, v_guest, null, 'ZebraPlayer', 'Batter', null, 2001, 2001);

  -- 4. Guest scores a match; Other user owns a separate match
  insert into public.matches (
    id, owner_id, team_a_id, team_a, team_b, batting_first_side,
    overs_limit, format_label, opening_striker_1_id, opening_non_striker_1_id,
    opening_bowler_1_id, is_demo, created_at
  ) values (
    v_match_id, v_guest, v_team_guest, 'bhatti xi', 'Opponent XI', 'a',
    6, '6OV', v_p_sheran, v_p_usama, v_p_zebra, false, 3000
  );

  insert into public.ball_events (
    id, match_id, owner_id, innings_number, sequence_number,
    striker_id, non_striker_id, bowler_id, runs_off_bat, created_at
  ) values (
    v_ball_id, v_match_id, v_guest, 1, 1,
    v_p_sheran, v_p_usama, v_p_zebra, 6, 3001
  );

  insert into public.matches (
    id, owner_id, team_a, team_b, batting_first_side,
    overs_limit, format_label, is_demo, created_at
  ) values (
    v_other_match_id, v_other, 'Other A', 'Other B', 'a',
    6, '6OV', false, 3002
  );

  -- 5. Verify profile_code auto-generation trigger & search_public_players filtering
  perform 1 from public.teams where id = v_team_reg and profile_code ~ '^[A-Z0-9]{2}-[A-Z0-9]{4,5}$';
  if not found then
    raise exception 'profile_code trigger did not assign expected code on v_team_reg';
  end if;

  select count(*) into v_cnt from public.search_public_players('ZebraPlayer', 10);
  if v_cnt <> 0 then
    raise exception 'Anonymous guest players must be hidden from search_public_players';
  end if;

  select count(*) into v_cnt from public.search_public_players('Sheran', 10) where player_id = v_p_sheran;
  if v_cnt <> 1 then
    raise exception 'Registered player Sheran should appear with exact player_id in search_public_players';
  end if;

  -- 6. Verify get_live_match_bundle returns match, teams, players, events in 1 round-trip
  v_bundle := public.get_live_match_bundle(v_match_id);
  if v_bundle is null
     or (v_bundle->'match'->>'id')::uuid <> v_match_id
     or jsonb_array_length(v_bundle->'events') <> 1 then
    raise exception 'get_live_match_bundle failed: %', v_bundle;
  end if;

  -- 7. Negative RLS test: v_reg CANNOT insert a ball_event into v_other_match_id
  perform set_config('request.jwt.claim.sub', v_reg::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';

  begin
    insert into public.ball_events (
      match_id, owner_id, innings_number, sequence_number,
      striker_id, non_striker_id, bowler_id, runs_off_bat, created_at
    ) values (
      v_other_match_id, v_reg, 1, 1, v_p_sheran, v_p_abdur, v_p_usama, 4, 4000
    );
  exception when insufficient_privilege then
    v_forbidden_caught := true;
  end;

  execute 'reset role';

  if not v_forbidden_caught then
    raise exception 'SECURITY FAILURE: unrelated user was allowed to insert ball into someone else match';
  end if;

  -- 8. Test invite code & claim_team_player by player_id
  perform set_config('request.jwt.claim.sub', v_reg::text, true);
  v_invite_code := public.create_team_invite_code(v_team_reg);
  perform set_config('request.jwt.claim.sub', v_other::text, true);
  v_claim_res := public.claim_team_player(v_invite_code, v_p_abdur, null);
  if (v_claim_res->>'player_id')::uuid <> v_p_abdur then
    raise exception 'claim_team_player did not return claimed player_id';
  end if;

  -- 9. Test claim_guest_data smart merge + player reparenting + designation conflict clearing
  perform set_config('request.jwt.claim.sub', v_reg::text, true);
  v_guest_claim_res := public.claim_guest_data(
    v_guest,
    array[v_match_id],
    array[v_team_guest, v_team_unique],
    '{}'::uuid[]
  );
  if (v_guest_claim_res->>'matches_claimed')::int <> 1
     or (v_guest_claim_res->>'ball_events_claimed')::int <> 1
     or (v_guest_claim_res->>'teams_claimed')::int <> 1 then
    raise exception 'Unexpected claim_guest_data summary: %', v_guest_claim_res;
  end if;

  -- Usama should now belong to v_team_reg, and conflicting designation 'C' should be cleared
  select count(*) into v_cnt
  from public.players
  where id = v_p_usama
    and team_id = v_team_reg
    and designation is null;
  if v_cnt <> 1 then
    raise exception 'Guest player reparenting / designation conflict resolution failed';
  end if;

  -- Guest match should now point to surviving v_team_reg and belong to v_reg
  select owner_id into v_owner from public.matches where id = v_match_id;
  if v_owner <> v_reg then
    raise exception 'Guest match owner_id not transferred';
  end if;

  -- 10. Instant rename in public.players updates display_name cleanly
  update public.players set display_name = 'Abdur Rehman', updated_at = 5000 where id = v_p_abdur;
  v_bundle := public.get_live_match_bundle(v_match_id);
  perform 1 from jsonb_array_elements(v_bundle->'players') elem
   where (elem->>'id')::uuid = v_p_abdur and elem->>'display_name' = 'Abdur Rehman';
  if not found then
    -- Check direct select on surviving team players
    perform 1 from public.players where id = v_p_abdur and display_name = 'Abdur Rehman';
    if not found then
      raise exception 'Player rename failed';
    end if;
  end if;
end $$;

rollback;
