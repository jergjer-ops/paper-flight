-- Exclude bots / scripts from the online counter.
-- register_game_visit now accepts the client user-agent. Real browsers keep
-- refreshing last_seen (counted as online); bots (curl, wget, headless,
-- common libraries) still increment visit_count / total_visitors but do NOT
-- refresh last_seen, so they never appear in the "online" window.
--
-- PostgREST does not support default parameters on RPCs, so we expose two
-- explicit overloads: register_game_visit(text, text) and a convenience
-- register_game_visit(text) for legacy callers.

alter table public.game_visitors
  add column if not exists last_user_agent text;

create or replace function public.game_online_payload()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select jsonb_build_object(
    'online_players', count(*)::bigint
  )
  from public.game_visitors
  where last_seen >= now() - interval '5 minutes'
    and (
      last_user_agent is null
      or last_user_agent !~* '(curl|wget|python-requests|python/|urllib|httpx|go-http-client|node-fetch|axios|postmanruntime|java/|okhttp|httpclient|libwww|bot|spider|crawler|headless|phantom|slimerjs|electron)'
    );
$function$;

revoke all on function public.game_online_payload() from public, anon, authenticated;

drop function if exists public.register_game_visit(text, text);

create or replace function public.register_game_visit(p_visitor_key text, p_user_agent text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_key text := trim(coalesce(p_visitor_key, ''));
  v_user_agent text := nullif(p_user_agent, '');
  v_is_bot boolean := coalesce(v_user_agent, '') ~* '(curl|wget|python-requests|python/|urllib|httpx|go-http-client|node-fetch|axios|postmanruntime|java/|okhttp|httpclient|libwww|bot|spider|crawler|headless|phantom|slimerjs|electron)';
  v_total bigint;
begin
  if v_key !~ '^web:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' then
    raise exception 'Invalid web visitor key';
  end if;

  insert into public.game_visitors (visitor_key, last_seen, last_user_agent)
  values (v_key, now(), v_user_agent)
  on conflict (visitor_key) do update
  set
    last_seen = case when v_is_bot then game_visitors.last_seen else now() end,
    visit_count = game_visitors.visit_count + 1,
    last_user_agent = v_user_agent;

  select count(*) into v_total from public.game_visitors;
  return public.game_leaderboard_payload() || jsonb_build_object('total_visitors', v_total) || public.game_online_payload();
end;
$function$;

create or replace function public.register_game_visit(p_visitor_key text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  return public.register_game_visit(p_visitor_key, null);
end;
$function$;

revoke all on function public.register_game_visit(text, text) from public;
revoke all on function public.register_game_visit(text) from public;
grant execute on function public.register_game_visit(text, text) to anon, authenticated;
grant execute on function public.register_game_visit(text) to anon, authenticated;