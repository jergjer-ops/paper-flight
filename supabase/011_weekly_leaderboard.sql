-- Add a UTC weekly ranking without exposing Telegram identifiers.
-- Scores come only from finished, server-validated flight sessions.

create or replace function public.game_leaderboard_payload()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  with all_time as (
    select coalesce(jsonb_agg(to_jsonb(ranked)), '[]'::jsonb) as rows
    from (
      select player_name, best_score, identity_provider
      from public.leaderboard
      order by best_score desc, best_at asc nulls last
      limit 100
    ) as ranked
  ), weekly as (
    select coalesce(jsonb_agg(to_jsonb(ranked)), '[]'::jsonb) as rows
    from (
      select
        board.player_name,
        max(session.score)::integer as best_score,
        board.identity_provider
      from public.flight_sessions as session
      join public.leaderboard as board on board.player_key = session.player_key
      where session.finished_at >= date_trunc('week', now() at time zone 'utc') at time zone 'utc'
        and session.score > 0
      group by board.player_key, board.player_name, board.identity_provider
      order by max(session.score) desc, min(session.finished_at) asc
      limit 100
    ) as ranked
  )
  select jsonb_build_object(
    'leaderboard', all_time.rows,
    'weekly_leaderboard', weekly.rows,
    'week_starts_at', date_trunc('week', now() at time zone 'utc') at time zone 'utc'
  )
  from all_time, weekly;
$function$;

revoke all on function public.game_leaderboard_payload() from public, anon, authenticated;

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
  return public.game_leaderboard_payload() || jsonb_build_object('total_visitors', v_total);
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
  return public.game_leaderboard_payload() || jsonb_build_object('total_visitors', v_total);
end;
$function$;

revoke all on function public.register_game_visit(text) from public;
revoke all on function public.register_telegram_game_visit(bigint) from public, anon, authenticated;
grant execute on function public.register_game_visit(text) to anon, authenticated;
grant execute on function public.register_telegram_game_visit(bigint) to service_role;
