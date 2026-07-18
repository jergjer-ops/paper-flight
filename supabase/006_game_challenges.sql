-- Personalized Telegram challenges and their conversion funnel.
-- Telegram identities reach these RPCs only through the telegram-flight Edge Function.

create extension if not exists pgcrypto;

create table if not exists public.game_challenges (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^c_[0-9a-f]{24}$'),
  challenger_telegram_id bigint not null check (challenger_telegram_id > 0),
  challenger_name text not null check (char_length(challenger_name) between 1 and 18),
  target_score integer not null check (target_score between 1 and 1000),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days'),
  open_count bigint not null default 0 check (open_count >= 0),
  first_opened_at timestamptz
);

create index if not exists game_challenges_creator_idx
  on public.game_challenges (challenger_telegram_id, created_at desc);

create table if not exists public.game_challenge_participants (
  challenge_id uuid not null references public.game_challenges(id) on delete cascade,
  participant_telegram_id bigint not null check (participant_telegram_id > 0),
  opened_at timestamptz not null default now(),
  first_flight_at timestamptz,
  best_score integer not null default 0 check (best_score between 0 and 1000),
  completed_at timestamptz,
  primary key (challenge_id, participant_telegram_id)
);

create index if not exists game_challenge_participant_idx
  on public.game_challenge_participants (participant_telegram_id, opened_at desc);

alter table public.game_challenges enable row level security;
alter table public.game_challenge_participants enable row level security;
revoke all on table public.game_challenges from public, anon, authenticated;
revoke all on table public.game_challenge_participants from public, anon, authenticated;

create or replace function public.create_game_challenge(
  p_telegram_user_id bigint,
  p_name text,
  p_score integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_name text;
  v_best integer;
  v_challenge public.game_challenges;
begin
  if p_telegram_user_id is null or p_telegram_user_id <= 0 then
    raise exception 'Invalid Telegram user';
  end if;
  if p_score is null or p_score < 1 or p_score > 1000 then
    raise exception 'Complete a scored flight before creating a challenge';
  end if;

  v_name := trim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  if char_length(v_name) < 1 or char_length(v_name) > 18 or v_name ~ '[[:cntrl:]<>]' then
    raise exception 'Invalid player name';
  end if;

  select best_score into v_best
  from public.leaderboard
  where identity_provider = 'telegram'
    and provider_user_id = p_telegram_user_id::text;

  if v_best is null or p_score > v_best then
    raise exception 'Challenge score has not been verified';
  end if;

  select * into v_challenge
  from public.game_challenges
  where challenger_telegram_id = p_telegram_user_id
    and target_score = p_score
    and created_at > now() - interval '2 minutes'
    and expires_at > now()
  order by created_at desc
  limit 1;

  if not found then
    if (
      select count(*) from public.game_challenges
      where challenger_telegram_id = p_telegram_user_id
        and created_at > now() - interval '1 hour'
    ) >= 20 then
      raise exception 'Too many challenges';
    end if;

    insert into public.game_challenges (
      code, challenger_telegram_id, challenger_name, target_score
    ) values (
      'c_' || encode(gen_random_bytes(12), 'hex'),
      p_telegram_user_id,
      v_name,
      p_score
    ) returning * into v_challenge;
  end if;

  return jsonb_build_object(
    'code', v_challenge.code,
    'challenger_name', v_challenge.challenger_name,
    'target_score', v_challenge.target_score,
    'expires_at', v_challenge.expires_at
  );
end;
$function$;

create or replace function public.open_game_challenge(
  p_telegram_user_id bigint,
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_challenge public.game_challenges;
  v_inserted integer := 0;
begin
  if p_telegram_user_id is null or p_telegram_user_id <= 0 then
    raise exception 'Invalid Telegram user';
  end if;
  if coalesce(p_code, '') !~ '^c_[0-9a-f]{24}$' then
    return null;
  end if;

  select * into v_challenge
  from public.game_challenges
  where code = p_code and expires_at > now();
  if not found then return null; end if;

  if v_challenge.challenger_telegram_id <> p_telegram_user_id then
    insert into public.game_challenge_participants (challenge_id, participant_telegram_id)
    values (v_challenge.id, p_telegram_user_id)
    on conflict do nothing;
    get diagnostics v_inserted = row_count;

    if v_inserted = 1 then
      update public.game_challenges
      set open_count = open_count + 1,
          first_opened_at = coalesce(first_opened_at, now())
      where id = v_challenge.id;
    end if;
  end if;

  return jsonb_build_object(
    'code', v_challenge.code,
    'challenger_name', v_challenge.challenger_name,
    'target_score', v_challenge.target_score,
    'is_self', v_challenge.challenger_telegram_id = p_telegram_user_id
  );
end;
$function$;

create or replace function public.mark_game_challenge_flight(
  p_telegram_user_id bigint,
  p_code text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  update public.game_challenge_participants as participant
  set first_flight_at = coalesce(participant.first_flight_at, now())
  from public.game_challenges as challenge
  where challenge.id = participant.challenge_id
    and challenge.code = p_code
    and challenge.expires_at > now()
    and participant.participant_telegram_id = p_telegram_user_id;
end;
$function$;

create or replace function public.record_game_challenge_score(
  p_telegram_user_id bigint,
  p_code text,
  p_score integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_target integer;
  v_best integer;
begin
  if p_score is null or p_score < 0 or p_score > 1000 then return null; end if;

  update public.game_challenge_participants as participant
  set best_score = greatest(participant.best_score, p_score),
      completed_at = case
        when p_score > challenge.target_score then coalesce(participant.completed_at, now())
        else participant.completed_at
      end
  from public.game_challenges as challenge
  where challenge.id = participant.challenge_id
    and challenge.code = p_code
    and challenge.expires_at > now()
    and participant.participant_telegram_id = p_telegram_user_id
  returning challenge.target_score, participant.best_score into v_target, v_best;

  if not found then return null; end if;
  return jsonb_build_object(
    'target_score', v_target,
    'best_score', v_best,
    'completed', v_best > v_target
  );
end;
$function$;

revoke all on function public.create_game_challenge(bigint, text, integer) from public, anon, authenticated;
revoke all on function public.open_game_challenge(bigint, text) from public, anon, authenticated;
revoke all on function public.mark_game_challenge_flight(bigint, text) from public, anon, authenticated;
revoke all on function public.record_game_challenge_score(bigint, text, integer) from public, anon, authenticated;

grant execute on function public.create_game_challenge(bigint, text, integer) to service_role;
grant execute on function public.open_game_challenge(bigint, text) to service_role;
grant execute on function public.mark_game_challenge_flight(bigint, text) to service_role;
grant execute on function public.record_game_challenge_score(bigint, text, integer) to service_role;
