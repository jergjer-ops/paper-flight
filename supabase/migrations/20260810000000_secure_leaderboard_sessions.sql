-- Phase 1: add a backwards-compatible, session-based score API.
-- The legacy RPCs remain available until the web client is migrated and tested.

create table if not exists public.flight_sessions (
  id uuid primary key default gen_random_uuid(),
  player_key text not null,
  player_name text not null,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '45 minutes'),
  finished_at timestamptz,
  score integer,
  constraint flight_sessions_player_name_length
    check (char_length(player_name) between 1 and 18),
  constraint flight_sessions_score_range
    check (score is null or score between 0 and 1000)
);

create index if not exists flight_sessions_player_started_idx
  on public.flight_sessions (player_key, started_at desc);

alter table public.flight_sessions enable row level security;
revoke all on table public.flight_sessions from public, anon, authenticated;

create or replace function public.start_flight_v2(p_name text)
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
  v_name := trim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));

  if char_length(v_name) < 1 or char_length(v_name) > 18 then
    raise exception 'Player name must contain 1 to 18 characters';
  end if;

  if v_name ~ '[[:cntrl:]<>]' then
    raise exception 'Player name contains forbidden characters';
  end if;

  v_key := lower(v_name);

  if (
    select count(*)
    from public.flight_sessions
    where player_key = v_key
      and started_at > now() - interval '10 minutes'
  ) >= 40 then
    raise exception 'Too many flight sessions';
  end if;

  insert into public.flight_sessions (player_key, player_name)
  values (v_key, v_name)
  returning * into v_session;

  return jsonb_build_object(
    'session_id', v_session.id,
    'started_at', v_session.started_at,
    'expires_at', v_session.expires_at
  );
end;
$function$;

create or replace function public.submit_score_v2(
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
  if p_session is null then
    raise exception 'Flight session is required';
  end if;

  if p_score is null or p_score < 0 or p_score > 1000 then
    raise exception 'Invalid score';
  end if;

  select * into v_session
  from public.flight_sessions
  where id = p_session
  for update;

  if not found then
    raise exception 'Unknown flight session';
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
    player_key, player_name, best_score, total_flights, best_at
  )
  values (
    v_session.player_key,
    v_session.player_name,
    p_score,
    1,
    case when p_score > 0 then now() else null end
  )
  on conflict (player_key) do update
  set player_name = excluded.player_name,
      best_at = case
        when excluded.best_score > leaderboard.best_score then now()
        else leaderboard.best_at
      end,
      best_score = greatest(leaderboard.best_score, excluded.best_score),
      total_flights = leaderboard.total_flights + 1,
      updated_at = now()
  returning * into v_row;

  return jsonb_build_object(
    'player_name', v_row.player_name,
    'best_score', v_row.best_score,
    'total_flights', v_row.total_flights
  );
end;
$function$;

revoke all on function public.start_flight_v2(text) from public;
revoke all on function public.submit_score_v2(uuid, integer) from public;
grant execute on function public.start_flight_v2(text) to anon, authenticated;
grant execute on function public.submit_score_v2(uuid, integer) to anon, authenticated;
