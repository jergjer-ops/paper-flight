ALTER TABLE leaderboard ADD COLUMN IF NOT EXISTS coins INTEGER DEFAULT 0;

CREATE OR REPLACE FUNCTION submit_score_telegram(
  p_telegram_user_id BIGINT,
  p_session TEXT,
  p_score INTEGER,
  p_coins INTEGER DEFAULT 0
)
RETURNS TABLE (
  player_name TEXT,
  best_score INTEGER,
  total_flights INTEGER,
  coins INTEGER,
  challenge JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_player_key TEXT;
  v_session_valid BOOLEAN;
  v_current_best INTEGER;
BEGIN
  v_player_key := 'telegram:' || p_telegram_user_id;

  SELECT EXISTS(
    SELECT 1 FROM flight_sessions
    WHERE session_id = p_session::uuid
      AND player_key = v_player_key
      AND ended_at IS NULL
  ) INTO v_session_valid;

  IF NOT v_session_valid THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  INSERT INTO leaderboard (player_key, player_name, best_score, total_flights, coins, updated_at)
  VALUES (v_player_key, v_player_key, p_score, 1, p_coins, now())
  ON CONFLICT (player_key) DO UPDATE SET
    best_score = GREATEST(leaderboard.best_score, EXCLUDED.best_score),
    total_flights = leaderboard.total_flights + 1,
    coins = p_coins,
    updated_at = now();

  UPDATE flight_sessions SET ended_at = now() WHERE session_id = p_session::uuid;

  SELECT lb.best_score INTO v_current_best
  FROM leaderboard lb WHERE lb.player_key = v_player_key;

  RETURN QUERY
  SELECT lb.player_name, lb.best_score, lb.total_flights, lb.coins, NULL::JSONB
  FROM leaderboard lb WHERE lb.player_key = v_player_key;
END;
$$;
