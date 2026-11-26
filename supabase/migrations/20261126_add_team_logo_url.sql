-- Add optional team logo_url to public.teams and include it in public lookup/search RPCs.

alter table public.teams
  add column if not exists logo_url text;

drop function if exists public.search_public_teams(text, integer);
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

drop function if exists public.lookup_team_by_profile_code(text);
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

grant execute on function public.search_public_teams(text, integer) to anon, authenticated;
grant execute on function public.lookup_team_by_profile_code(text) to anon, authenticated;
