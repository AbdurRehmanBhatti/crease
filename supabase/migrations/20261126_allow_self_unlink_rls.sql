-- Allow a signed-in teammate who claimed a player spot (`auth.uid() = user_id` in USING)
-- to unlink themselves (`user_id = null`) via Leave Team or Unlink My Account.

drop policy if exists "players_update_owner_or_self" on public.players;

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
