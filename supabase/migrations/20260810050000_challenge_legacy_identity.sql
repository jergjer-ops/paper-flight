-- Let existing Telegram pilots create challenges after the identity migration.
-- The canonical player_key is derived by the trusted Edge Function from the
-- validated Telegram user id, so this keeps the score check server-side.

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
  where player_key = 'telegram:' || p_telegram_user_id::text
     or (
       identity_provider = 'telegram'
       and provider_user_id = p_telegram_user_id::text
     )
  order by best_score desc
  limit 1;

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
      'c_' || encode(extensions.gen_random_bytes(12), 'hex'),
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

revoke all on function public.create_game_challenge(bigint, text, integer)
  from public, anon, authenticated;
grant execute on function public.create_game_challenge(bigint, text, integer)
  to service_role;
