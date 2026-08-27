-- Add coins column to leaderboard for server-side coin persistence.

ALTER TABLE public.leaderboard ADD COLUMN IF NOT EXISTS coins INTEGER NOT NULL DEFAULT 0;

-- Update submit_score_telegram to accept and save coins.
create or replace function public.submit_score_telegram(
  p_telegram_user_id bigint,
  p_session uuid,
  p_score integer,
  p_coins integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_player_key text;
  v_row public.leaderboard%rowtype;
  v_new_record boolean;
begin
  v_player_key := 'telegram:' || p_telegram_user_id;

  -- Validate session
  if not exists (
    select 1 from public.flight_sessions
    where id = p_session
      and player_key = v_player_key
      and finished_at is null
  ) then
    raise exception 'Invalid or expired session';
  end if;

  -- Mark session finished
  update public.flight_sessions
  set finished_at = now(), score = p_score
  where id = p_session;

  -- Upsert leaderboard row
  insert into public.leaderboard (player_key, player_name, best_score, total_flights, coins, last_score, updated_at)
  values (v_player_key, '', p_score, 1, p_coins, p_score, now())
  on conflict (player_key) do update
  set
    best_score = GREATEST(public.leaderboard.best_score, excluded.best_score),
    total_flights = public.leaderboard.total_flights + 1,
    coins = GREATEST(public.leaderboard.coins, excluded.coins),
    last_score = excluded.last_score,
    updated_at = now()
  returning * into v_row;

  v_new_record := (v_row.best_score = p_score and p_score > 0);

  return jsonb_build_object(
    'best_score', v_row.best_score,
    'total_flights', v_row.total_flights,
    'coins', v_row.coins,
    'new_record', v_new_record
  );
end;
$function$;

-- Update existing rows: set coins from best_score * 5 for players without coins.
UPDATE public.leaderboard SET coins = GREATEST(best_score * 5, 0) WHERE coins = 0 AND best_score > 0;
