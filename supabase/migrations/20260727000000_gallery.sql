-- ============================================================================
-- Galleria per-chat delle foto "senza limiti".
--  * Una foto "da galleria" è cifrata come sempre (chiave E2E, revocabile),
--    ma inviata con aperture ILLIMITATE e senza scadenza. Il messaggio viene
--    marcato `gallery_offered = true`.
--  * Ogni utente sceglie quali salvare nella propria galleria (gallery_items).
--    "Salvare" = segnalibro: la foto resta cifrata su Storage e riapribile;
--    se il mittente la revoca, sparisce per tutti.
-- ============================================================================

alter table public.messages
  add column if not exists gallery_offered boolean not null default false;

create table if not exists public.gallery_items (
  user_id         uuid not null references public.profiles(id) on delete cascade,
  message_id      uuid not null references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  added_at        timestamptz not null default now(),
  primary key (user_id, message_id)
);

create index if not exists gallery_items_user_conv_idx
  on public.gallery_items(user_id, conversation_id);

alter table public.gallery_items enable row level security;

-- Ognuno gestisce SOLO la propria galleria.
drop policy if exists "gallery_items_all" on public.gallery_items;
create policy "gallery_items_all" on public.gallery_items
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
