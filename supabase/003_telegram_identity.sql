-- Phase 3: bind score sessions to a Telegram Mini App identity.
-- Verified identity values enter PostgreSQL only through the service role.
-- Telegram initData is verified in the telegram-flight Edge Function. These
-- RPCs are intentionally callable only by service_role.

alter table public.flight_sessions
  add column if not exists telegram_user_id bigint;

alter table public.leaderboard
  add column if not exists identity_provider text,
  add column if not exists provider_user_id text;

create index if not exists flight_sessions_telegram_started_idx
  on public.flight_sessions (telegram_user_id, started_at desc)
  where telegram_user_id is not null;

create unique index if not exists leaderboard_provider_identity_idx
  on public.leaderboard (identity_provider, provider_user_id)
  where identity_provider is not null and provider_user_id is not null;

create or replace function public.start_flight_telegram(
  p_telegram_user_id bigint,
  p_name text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_name text;
  v_key text;
  v_session public.flight_sessions;
begin
  if p_telegram_user_id is null or p_telegram_user_id <= 0 then
    raise exception 'Invalid Telegram user';
  end if;

  v_name := trim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));

  if char_length(v_name) < 1 or char_length(v_name) > 18 then
    raise exception 'Player name must contain 1 to 18 characters';
  end if;

  if v_name ~ '[[:cntrl:]<>]' then
    raise exception 'Player name contains forbidden characters';
  end if;

  v_key := 'telegram:' || p_telegram_user_id::text;

  if (
    select count(*)
    from public.flight_sessions
    where telegram_user_id = p_telegram_user_id
      and started_at > now() - interval '10 minutes'
  ) >= 40 then
    raise exception 'Too many flight sessions';
  end if;

  insert into public.flight_sessions (
    player_key, player_name, telegram_user_id
  )
  values (
    v_key, v_name, p_telegram_user_id
  )
  returning * into v_session;

  return jsonb_build_object(
    'session_id', v_session.id,
    'started_at', v_session.started_at,
    'expires_at', v_session.expires_at,
    'player_name', v_session.player_name
  );
end;
$function$;

create or replace function public.submit_score_telegram(
  p_telegram_user_id bigint,
  p_session uuid,
  p_score integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
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
    best_at,
    identity_provider,
    provider_user_id
  )
  values (
    v_session.player_key,
    v_session.player_name,
    p_score,
    1,
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
      identity_provider = 'telegram',
      provider_user_id = excluded.provider_user_id,
      updated_at = now()
  returning * into v_row;

  return jsonb_build_object(
    'player_name', v_row.player_name,
    'best_score', v_row.best_score,
    'total_flights', v_row.total_flights,
    'identity_provider', v_row.identity_provider
  );
end;
$function$;

revoke all on function public.start_flight_telegram(bigint, text)
  from public, anon, authenticated;
revoke all on function public.submit_score_telegram(bigint, uuid, integer)
  from public, anon, authenticated;

grant execute on function public.start_flight_telegram(bigint, text)
  to service_role;
grant execute on function public.submit_score_telegram(bigint, uuid, integer)
  to service_role;
