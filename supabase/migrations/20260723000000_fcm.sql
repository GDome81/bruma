-- ============================================================================
-- FCM (Android APK) — token dei dispositivi per le notifiche push native.
-- Parallela a `push_subscriptions` (Web Push): qui salviamo i token FCM. La
-- Edge Function `send-push` (service role) legge questa tabella e invia la
-- notifica anonima (🌙) al destinatario di ogni nuovo messaggio.
-- ============================================================================

create table if not exists public.fcm_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  token       text not null unique,
  created_at  timestamptz not null default now()
);

create index if not exists fcm_tokens_user_idx
  on public.fcm_tokens(user_id);

alter table public.fcm_tokens enable row level security;

-- L'utente gestisce SOLO i propri token. La Edge Function usa la service role
-- key e aggira la RLS per leggerli tutti.
drop policy if exists "fcm_select" on public.fcm_tokens;
create policy "fcm_select" on public.fcm_tokens
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "fcm_insert" on public.fcm_tokens;
create policy "fcm_insert" on public.fcm_tokens
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "fcm_update" on public.fcm_tokens;
create policy "fcm_update" on public.fcm_tokens
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "fcm_delete" on public.fcm_tokens;
create policy "fcm_delete" on public.fcm_tokens
  for delete to authenticated using (user_id = auth.uid());
