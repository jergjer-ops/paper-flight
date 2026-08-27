-- Authoritative Telegram wallet and atomic shop state across devices.

alter table public.leaderboard
  add column if not exists owned_planes jsonb not null default '["fighter"]',
  add column if not exists selected_plane text not null default 'fighter',
  add column if not exists owned_tracks jsonb not null default '["morning"]',
  add column if not exists selected_track text not null default 'morning',
  add column if not exists banked_lives integer not null default 0;

create or replace function public.update_telegram_shop(
  p_telegram_user_id bigint,
  p_item_kind text,
  p_item_id text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_price integer;
  v_row public.leaderboard;
begin
  if p_telegram_user_id is null or p_telegram_user_id <= 0 then raise exception 'Invalid Telegram user'; end if;

  select * into v_row from public.leaderboard
  where player_key = 'telegram:' || p_telegram_user_id::text
    and identity_provider = 'telegram'
    and provider_user_id = p_telegram_user_id::text
  for update;
  if not found then raise exception 'Telegram profile not found'; end if;

  if p_item_kind = 'plane' then
    v_price := case p_item_id when 'fighter' then 0 when 'golden' then 400 else null end;
    if v_price is null then raise exception 'Invalid plane'; end if;
    if not (v_row.owned_planes ? p_item_id) then
      if v_row.coins < v_price then raise exception 'Not enough coins'; end if;
      v_row.coins := v_row.coins - v_price;
      v_row.owned_planes := v_row.owned_planes || jsonb_build_array(p_item_id);
    end if;
    v_row.selected_plane := p_item_id;
  elsif p_item_kind = 'track' then
    v_price := case p_item_id when 'morning' then 0 when 'sunset' then 150 when 'night' then 150 when 'dungeon' then 300 else null end;
    if v_price is null then raise exception 'Invalid track'; end if;
    if not (v_row.owned_tracks ? p_item_id) then
      if v_row.coins < v_price then raise exception 'Not enough coins'; end if;
      v_row.coins := v_row.coins - v_price;
      v_row.owned_tracks := v_row.owned_tracks || jsonb_build_array(p_item_id);
    end if;
    v_row.selected_track := p_item_id;
  elsif p_item_kind = 'lives' and p_item_id = 'pack10' then
    if v_row.banked_lives >= 10 then raise exception 'Lives already full'; end if;
    if v_row.coins < 200 then raise exception 'Not enough coins'; end if;
    v_row.coins := v_row.coins - 200;
    v_row.banked_lives := 10;
  else
    raise exception 'Invalid shop item';
  end if;

  update public.leaderboard set
    coins = v_row.coins, owned_planes = v_row.owned_planes,
    selected_plane = v_row.selected_plane, owned_tracks = v_row.owned_tracks,
    selected_track = v_row.selected_track, banked_lives = v_row.banked_lives,
    updated_at = now()
  where player_key = v_row.player_key returning * into v_row;

  return jsonb_build_object(
    'best_score', v_row.best_score, 'total_flights', v_row.total_flights,
    'coins', v_row.coins, 'owned_planes', v_row.owned_planes,
    'selected_plane', v_row.selected_plane, 'owned_tracks', v_row.owned_tracks,
    'selected_track', v_row.selected_track, 'banked_lives', v_row.banked_lives
  );
end;
$function$;

revoke all on function public.update_telegram_shop(bigint, text, text) from public, anon, authenticated;
grant execute on function public.update_telegram_shop(bigint, text, text) to service_role;
