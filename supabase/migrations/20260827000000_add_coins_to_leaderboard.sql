ALTER TABLE leaderboard ADD COLUMN IF NOT EXISTS coins INTEGER DEFAULT 0;

DROP FUNCTION IF EXISTS public.submit_score_telegram(bigint, uuid, integer);

CREATE OR REPLACE FUNCTION public.submit_score_telegram(
  p_telegram_user_id bigint,
  p_session uuid,
  p_score integer,
  p_coins integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_session public.flight_sessions;
  v_elapsed numeric;
  v_max_score integer;
  v_row public.leaderboard;
begin
  if p_telegram_user_id is null or p_telegram_user_id <= 0 then
    raise exception 'Invalid Telegram user';
  end if;

  if p_session is null then
    raise exception 'Flight session is required';
  end if;

  if p_score is null or p_score < 0 or p_score > 1000 then
    raise exception 'Invalid score';
  end if;

  select * into v_session
  from public.flight_sessions
  where id = p_session
    and telegram_user_id = p_telegram_user_id
  for update;

  if not found then
    raise exception 'Unknown flight session for this Telegram user';
  end if;

  if v_session.finished_at is not null then
    raise exception 'Flight session has already been used';
  end if;

  if v_session.expires_at < now() then
    raise exception 'Flight session has expired';
  end if;

  v_elapsed := extract(epoch from (now() - v_session.started_at));
  v_max_score := case
    when v_elapsed < 2 then 0
    else floor((v_elapsed - 2) / 0.8)::integer + 1
  end;

  if p_score > v_max_score then
    raise exception 'Score is not physically possible for this session';
  end if;

  update public.flight_sessions
  set finished_at = now(), score = p_score
  where id = v_session.id;

  insert into public.leaderboard (
    player_key,
    player_name,
    best_score,
    total_flights,
    coins,
    best_at,
    identity_provider,
    provider_user_id
  )
  values (
    v_session.player_key,
    v_session.player_name,
    p_score,
    1,
    p_coins,
    case when p_score > 0 then now() else null end,
    'telegram',
    p_telegram_user_id::text
  )
  on conflict (player_key) do update
  set player_name = excluded.player_name,
      best_at = case
        when excluded.best_score > leaderboard.best_score then now()
        else leaderboard.best_at
      end,
      best_score = greatest(leaderboard.best_score, excluded.best_score),
      total_flights = leaderboard.total_flights + 1,
      coins = p_coins,
      identity_provider = 'telegram',
      provider_user_id = excluded.provider_user_id,
      updated_at = now()
  returning * into v_row;

  return jsonb_build_object(
    'player_name', v_row.player_name,
    'best_score', v_row.best_score,
    'total_flights', v_row.total_flights,
    'coins', v_row.coins,
    'identity_provider', v_row.identity_provider
  );
end;
$function$;

REVOKE ALL ON FUNCTION public.submit_score_telegram(bigint, uuid, integer, integer)
  FROM public, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.submit_score_telegram(bigint, uuid, integer, integer)
  TO service_role;
