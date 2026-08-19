-- Add a "players online" counter based on recent last_seen activity.
-- Online = visitors whose last_seen is within the last 5 minutes.

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
  where last_seen >= now() - interval '5 minutes';
$function$;

revoke all on function public.game_online_payload() from public, anon, authenticated;

create or replace function public.register_game_visit(p_visitor_key text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_key text := trim(coalesce(p_visitor_key, ''));
  v_total bigint;
begin
  if v_key !~ '^web:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' then
    raise exception 'Invalid web visitor key';
  end if;

  insert into public.game_visitors (visitor_key)
  values (v_key)
  on conflict (visitor_key) do update
  set last_seen = now(), visit_count = game_visitors.visit_count + 1;

  select count(*) into v_total from public.game_visitors;
  return public.game_leaderboard_payload() || jsonb_build_object('total_visitors', v_total) || public.game_online_payload();
end;
$function$;

create or replace function public.register_telegram_game_visit(p_telegram_user_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_total bigint;
begin
  if p_telegram_user_id is null or p_telegram_user_id <= 0 then
    raise exception 'Invalid Telegram user';
  end if;

  insert into public.game_visitors (visitor_key)
  values ('telegram:' || p_telegram_user_id::text)
  on conflict (visitor_key) do update
  set last_seen = now(), visit_count = game_visitors.visit_count + 1;

  select count(*) into v_total from public.game_visitors;
  return public.game_leaderboard_payload() || jsonb_build_object('total_visitors', v_total) || public.game_online_payload();
end;
$function$;

revoke all on function public.register_game_visit(text) from public;
revoke all on function public.register_telegram_game_visit(bigint) from public, anon, authenticated;
grant execute on function public.register_game_visit(text) to anon, authenticated;
grant execute on function public.register_telegram_game_visit(bigint) to service_role;
