-- Idempotency ledger for Telegram webhook updates.

create table if not exists public.telegram_webhook_updates (
  update_id bigint primary key,
  received_at timestamptz not null default now()
);

create index if not exists telegram_webhook_updates_received_idx
  on public.telegram_webhook_updates (received_at);

alter table public.telegram_webhook_updates enable row level security;
revoke all on table public.telegram_webhook_updates from public, anon, authenticated;

-- Keep the bounded ledger small without affecting active Telegram retries.
create or replace function public.prune_telegram_webhook_updates()
returns void
language sql
security definer
set search_path = pg_catalog, public
as $function$
  delete from public.telegram_webhook_updates
  where received_at < now() - interval '7 days';
$function$;

revoke all on function public.prune_telegram_webhook_updates()
  from public, anon, authenticated;
grant execute on function public.prune_telegram_webhook_updates()
  to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'paper-flight-public',
  'paper-flight-public',
  true,
  10485760,
  array['video/mp4', 'image/png']
)
on conflict (id) do update
set public = true,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "temporary-paper-flight-welcome-upload" on storage.objects;
create policy "temporary-paper-flight-welcome-upload"
on storage.objects for insert to anon
with check (
  bucket_id = 'paper-flight-public'
  and name in (
    'welcome/paper-flight-how-to-play.mp4',
    'welcome/paper-flight-how-to-play-poster.png'
  )
);
