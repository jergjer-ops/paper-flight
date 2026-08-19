-- Abuse controls shared by standalone clients. Apply through the normal
-- Supabase migration workflow; no client secret is introduced.

create or replace function public.guard_flight_session_insert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  -- Opportunistic cleanup prevents abandoned anonymous sessions growing forever.
  delete from public.flight_sessions
  where expires_at < now() - interval '7 days';

  if (
    select count(*) from public.flight_sessions
    where player_key = new.player_key
      and started_at > now() - interval '10 minutes'
  ) >= 15 then
    raise exception 'Too many flight sessions';
  end if;

  if (
    select count(*) from public.flight_sessions
    where started_at > now() - interval '1 minute'
  ) >= 600 then
    raise exception 'Flight service is temporarily busy';
  end if;
  return new;
end;
$function$

drop trigger if exists guard_flight_session_insert on public.flight_sessions

create trigger guard_flight_session_insert
before insert on public.flight_sessions
for each row execute function public.guard_flight_session_insert()

create or replace function public.guard_flight_session_score()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  elapsed_seconds numeric;
  plausible_score integer;
begin
  if new.finished_at is not null and old.finished_at is null then
    elapsed_seconds := extract(epoch from (now() - old.started_at));
    plausible_score := case
      when elapsed_seconds < 2 then 0
      else floor((elapsed_seconds - 2) / 1.05)::integer + 1
    end;
    if new.score is null or new.score < 0 or new.score > plausible_score then
      raise exception 'Score is not physically possible for this session';
    end if;
  end if;
  return new;
end;
$function$

drop trigger if exists guard_flight_session_score on public.flight_sessions

create trigger guard_flight_session_score
before update of finished_at, score on public.flight_sessions
for each row execute function public.guard_flight_session_score()

create or replace function public.guard_new_visitor_insert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if (
    select count(*) from public.game_visitors
    where last_seen > now() - interval '1 minute'
  ) >= 300 then
    raise exception 'Visitor registration is temporarily busy';
  end if;
  return new;
end;
$function$

drop trigger if exists guard_new_visitor_insert on public.game_visitors

create trigger guard_new_visitor_insert
before insert on public.game_visitors
for each row execute function public.guard_new_visitor_insert()

revoke all on function public.guard_flight_session_insert() from public, anon, authenticated

revoke all on function public.guard_flight_session_score() from public, anon, authenticated

revoke all on function public.guard_new_visitor_insert() from public, anon, authenticated
