-- ============================================================================
-- Web Push (PWA) — sottoscrizioni push per notifiche ad app chiusa/sospesa.
-- Ogni dispositivo registra una subscription (endpoint + chiavi) associata
-- all'utente. La Edge Function `send-push` (service role) legge questa tabella
-- e invia la notifica generica (🌙) al destinatario di ogni nuovo messaggio.
-- ============================================================================

create table if not exists public.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  created_at  timestamptz not null default now()
);

create index if not exists push_subscriptions_user_idx
  on public.push_subscriptions(user_id);

alter table public.push_subscriptions enable row level security;

-- L'utente gestisce SOLO le proprie subscription. La Edge Function usa la
-- service role key e aggira la RLS per leggerle tutte.
drop policy if exists "push_select" on public.push_subscriptions;
create policy "push_select" on public.push_subscriptions
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "push_insert" on public.push_subscriptions;
create policy "push_insert" on public.push_subscriptions
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "push_update" on public.push_subscriptions;
create policy "push_update" on public.push_subscriptions
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "push_delete" on public.push_subscriptions;
create policy "push_delete" on public.push_subscriptions
  for delete to authenticated using (user_id = auth.uid());
