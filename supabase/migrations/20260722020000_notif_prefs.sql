-- ============================================================================
-- Preferenze notifiche: suono/vibrazione per utente + chat silenziate.
-- Lette dalla Edge Function `send-push` per applicare le stesse scelte anche
-- alle notifiche push (app chiusa/sospesa).
-- ============================================================================

create table if not exists public.notif_prefs (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  sound       boolean not null default true,
  vibrate     boolean not null default true,
  updated_at  timestamptz not null default now()
);

alter table public.notif_prefs enable row level security;

drop policy if exists "notif_prefs_all" on public.notif_prefs;
create policy "notif_prefs_all" on public.notif_prefs
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create table if not exists public.chat_mutes (
  user_id         uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  primary key (user_id, conversation_id)
);

alter table public.chat_mutes enable row level security;

drop policy if exists "chat_mutes_all" on public.chat_mutes;
create policy "chat_mutes_all" on public.chat_mutes
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
