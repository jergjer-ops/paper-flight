-- Telegram production safety: bot-scoped webhook idempotency, bounded request
-- rates, verified Telegram visits, and self-service player-data deletion.

create table if not exists public.telegram_webhook_receipts (
  bot_id bigint not null check (bot_id > 0),
  update_id bigint not null,
  received_at timestamptz not null default now(),
  primary key (bot_id, update_id)
);

create index if not exists telegram_webhook_receipts_received_idx
  on public.telegram_webhook_receipts (received_at);

create table if not exists public.telegram_bot_rate_limits (
  telegram_user_id bigint primary key check (telegram_user_id > 0),
  window_started_at timestamptz not null default now(),
  request_count integer not null default 0 check (request_count >= 0)
);

create table if not exists public.telegram_api_rate_limits (
  telegram_user_id bigint not null check (telegram_user_id > 0),
  action text not null check (action ~ '^[a-z_]{1,32}$'),
  window_started_at timestamptz not null default now(),
  request_count integer not null default 0 check (request_count >= 0),
  primary key (telegram_user_id, action)
);

alter table public.telegram_webhook_receipts enable row level security;
alter table public.telegram_bot_rate_limits enable row level security;
alter table public.telegram_api_rate_limits enable row level security;

revoke all on table public.telegram_webhook_receipts from public, anon, authenticated;
revoke all on table public.telegram_bot_rate_limits from public, anon, authenticated;
revoke all on table public.telegram_api_rate_limits from public, anon, authenticated;

create or replace function public.claim_telegram_bot_request(
  p_telegram_user_id bigint,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_row public.telegram_bot_rate_limits;
begin
  if p_telegram_user_id is null or p_telegram_user_id <= 0
     or p_limit is null or p_limit < 1 or p_limit > 120
     or p_window_seconds is null or p_window_seconds < 1 or p_window_seconds > 3600 then
    return false;
  end if;

  insert into public.telegram_bot_rate_limits (telegram_user_id, request_count)
  values (p_telegram_user_id, 0)
  on conflict (telegram_user_id) do nothing;

  select * into v_row
  from public.telegram_bot_rate_limits
  where telegram_user_id = p_telegram_user_id
  for update;

  if v_row.window_started_at <= now() - make_interval(secs => p_window_seconds) then
    update public.telegram_bot_rate_limits
    set window_started_at = now(), request_count = 1
    where telegram_user_id = p_telegram_user_id;
    return true;
  end if;

  if v_row.request_count >= p_limit then return false; end if;

  update public.telegram_bot_rate_limits
  set request_count = request_count + 1
  where telegram_user_id = p_telegram_user_id;
  return true;
end;
$function$;

create or replace function public.claim_telegram_api_request(
  p_telegram_user_id bigint,
  p_action text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_action text := lower(trim(coalesce(p_action, '')));
  v_row public.telegram_api_rate_limits;
begin
  if p_telegram_user_id is null or p_telegram_user_id <= 0
     or v_action !~ '^[a-z_]{1,32}$'
     or p_limit is null or p_limit < 1 or p_limit > 240
     or p_window_seconds is null or p_window_seconds < 1 or p_window_seconds > 3600 then
    return false;
  end if;

  insert into public.telegram_api_rate_limits (telegram_user_id, action, request_count)
  values (p_telegram_user_id, v_action, 0)
  on conflict (telegram_user_id, action) do nothing;

  select * into v_row
  from public.telegram_api_rate_limits
  where telegram_user_id = p_telegram_user_id and action = v_action
  for update;

  if v_row.window_started_at <= now() - make_interval(secs => p_window_seconds) then
    update public.telegram_api_rate_limits
    set window_started_at = now(), request_count = 1
    where telegram_user_id = p_telegram_user_id and action = v_action;
    return true;
  end if;

  if v_row.request_count >= p_limit then return false; end if;

  update public.telegram_api_rate_limits
  set request_count = request_count + 1
  where telegram_user_id = p_telegram_user_id and action = v_action;
  return true;
end;
$function$;

-- Anonymous web callers may register only a random web visitor UUID. Telegram
-- visitor keys are accepted solely by register_telegram_game_visit below.
create or replace function public.register_game_visit(p_visitor_key text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_key text := trim(coalesce(p_visitor_key, ''));
  v_total bigint;
  v_leaderboard jsonb;
begin
  if v_key !~ '^web:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' then
    raise exception 'Invalid web visitor key';
  end if;

  insert into public.game_visitors (visitor_key)
  values (v_key)
  on conflict (visitor_key) do update
  set last_seen = now(), visit_count = game_visitors.visit_count + 1;

  select count(*) into v_total from public.game_visitors;
  select coalesce(jsonb_agg(to_jsonb(ranked)), '[]'::jsonb)
  into v_leaderboard
  from (
    select player_name, best_score, identity_provider
    from public.leaderboard
    order by best_score desc, best_at asc nulls last
    limit 100
  ) as ranked;

  return jsonb_build_object('total_visitors', v_total, 'leaderboard', v_leaderboard);
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
  v_leaderboard jsonb;
begin
  if p_telegram_user_id is null or p_telegram_user_id <= 0 then
    raise exception 'Invalid Telegram user';
  end if;

  insert into public.game_visitors (visitor_key)
  values ('telegram:' || p_telegram_user_id::text)
  on conflict (visitor_key) do update
  set last_seen = now(), visit_count = game_visitors.visit_count + 1;

  select count(*) into v_total from public.game_visitors;
  select coalesce(jsonb_agg(to_jsonb(ranked)), '[]'::jsonb)
  into v_leaderboard
  from (
    select player_name, best_score, identity_provider
    from public.leaderboard
    order by best_score desc, best_at asc nulls last
    limit 100
  ) as ranked;

  return jsonb_build_object('total_visitors', v_total, 'leaderboard', v_leaderboard);
end;
$function$;

create or replace function public.delete_telegram_player_data(p_telegram_user_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_participants integer := 0;
  v_challenges integer := 0;
  v_sessions integer := 0;
  v_profiles integer := 0;
  v_visitors integer := 0;
begin
  if p_telegram_user_id is null or p_telegram_user_id <= 0 then
    raise exception 'Invalid Telegram user';
  end if;

  delete from public.game_challenge_participants
  where participant_telegram_id = p_telegram_user_id;
  get diagnostics v_participants = row_count;

  delete from public.game_challenges
  where challenger_telegram_id = p_telegram_user_id;
  get diagnostics v_challenges = row_count;

  delete from public.flight_sessions
  where telegram_user_id = p_telegram_user_id
     or player_key = 'telegram:' || p_telegram_user_id::text;
  get diagnostics v_sessions = row_count;

  delete from public.leaderboard
  where player_key = 'telegram:' || p_telegram_user_id::text
     or (identity_provider = 'telegram' and provider_user_id = p_telegram_user_id::text);
  get diagnostics v_profiles = row_count;

  delete from public.game_visitors
  where visitor_key = 'telegram:' || p_telegram_user_id::text;
  get diagnostics v_visitors = row_count;

  delete from public.telegram_api_rate_limits where telegram_user_id = p_telegram_user_id;
  delete from public.telegram_bot_rate_limits where telegram_user_id = p_telegram_user_id;

  return jsonb_build_object(
    'participants_deleted', v_participants,
    'challenges_deleted', v_challenges,
    'sessions_deleted', v_sessions,
    'profiles_deleted', v_profiles,
    'visitors_deleted', v_visitors
  );
end;
$function$;

create or replace function public.prune_telegram_bot_security_data()
returns void
language sql
security definer
set search_path = pg_catalog, public
as $function$
  delete from public.telegram_webhook_receipts
  where received_at < now() - interval '7 days';
  delete from public.telegram_bot_rate_limits
  where window_started_at < now() - interval '1 day';
  delete from public.telegram_api_rate_limits
  where window_started_at < now() - interval '1 day';
$function$;

revoke all on function public.claim_telegram_bot_request(bigint, integer, integer) from public, anon, authenticated;
revoke all on function public.claim_telegram_api_request(bigint, text, integer, integer) from public, anon, authenticated;
revoke all on function public.register_telegram_game_visit(bigint) from public, anon, authenticated;
revoke all on function public.delete_telegram_player_data(bigint) from public, anon, authenticated;
revoke all on function public.prune_telegram_bot_security_data() from public, anon, authenticated;
revoke all on function public.register_game_visit(text) from public;

grant execute on function public.claim_telegram_bot_request(bigint, integer, integer) to service_role;
grant execute on function public.claim_telegram_api_request(bigint, text, integer, integer) to service_role;
grant execute on function public.register_telegram_game_visit(bigint) to service_role;
grant execute on function public.delete_telegram_player_data(bigint) to service_role;
grant execute on function public.prune_telegram_bot_security_data() to service_role;
grant execute on function public.register_game_visit(text) to anon, authenticated;
