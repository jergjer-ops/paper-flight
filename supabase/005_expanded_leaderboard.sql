-- Expand the public leaderboard response for the full in-game ranking.
-- Only display-safe fields are returned; provider user IDs remain private.

create or replace function public.register_game_visit(p_visitor_key text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_key text;
  v_total bigint;
  v_leaderboard jsonb;
begin
  v_key := trim(coalesce(p_visitor_key, ''));

  if v_key !~ '^(telegram:[0-9]{1,20}|web:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12})$' then
    raise exception 'Invalid visitor key';
  end if;

  insert into public.game_visitors (visitor_key)
  values (v_key)
  on conflict (visitor_key) do update
  set last_seen = now(),
      visit_count = game_visitors.visit_count + 1;

  select count(*) into v_total from public.game_visitors;

  select coalesce(jsonb_agg(to_jsonb(ranked)), '[]'::jsonb)
  into v_leaderboard
  from (
    select player_name, best_score, identity_provider
    from public.leaderboard
    order by best_score desc, best_at asc nulls last
    limit 100
  ) as ranked;

  return jsonb_build_object(
    'total_visitors', v_total,
    'leaderboard', v_leaderboard
  );
end;
$function$;

revoke all on function public.register_game_visit(text) from public;
grant execute on function public.register_game_visit(text) to anon, authenticated;
