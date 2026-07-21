-- ============================================================================
-- Bruma — schema iniziale (Postgres / Supabase)
-- Contiene: tabelle, indici, Row Level Security, GRANT a livello di colonna,
-- RPC atomiche (request_key, redeem_invite, revoke_*), Storage + Realtime.
--
-- Applicare con:  supabase db push
-- oppure incollare l'intero file nel SQL Editor del dashboard Supabase.
--
-- NOTE DI SICUREZZA IMPORTANTI:
--  * La colonna message_access.wrapped_key NON e' leggibile in SELECT dagli
--    utenti 'authenticated' (grant a livello di colonna). Esce SOLO dalla RPC
--    request_key (SECURITY DEFINER) che fa il check-and-increment atomico.
--  * Le mutazioni su message_access e open_events avvengono SOLO tramite le
--    funzioni SECURITY DEFINER (request_key / revoke_*). I client non hanno
--    privilegi di UPDATE/DELETE diretti su queste tabelle.
-- ============================================================================

-- pgcrypto fornisce gen_random_uuid() (di norma gia' presente su Supabase)
create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- 1) TABELLE
-- ----------------------------------------------------------------------------

-- Profilo utente (id coincide con auth.uid())
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  public_key   text not null,                 -- chiave pubblica X25519 (base64)
  created_at   timestamptz not null default now()
);

-- Codici invito condivisibili
create table if not exists public.invite_codes (
  code       text primary key,
  owner      uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists invite_codes_owner_idx on public.invite_codes(owner);

-- Relazione di contatto (una riga per direzione)
create table if not exists public.contacts (
  id         uuid primary key default gen_random_uuid(),
  owner      uuid not null references public.profiles(id) on delete cascade,
  contact    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (owner, contact)
);
create index if not exists contacts_owner_idx on public.contacts(owner);

-- Conversazione 1-a-1 + impostazioni di protezione (modello per i messaggi).
-- Canonicalizzata: user_a = least(uid_1, uid_2), user_b = greatest(...).
create table if not exists public.conversations (
  id                    uuid primary key default gen_random_uuid(),
  user_a                uuid not null references public.profiles(id) on delete cascade,
  user_b                uuid not null references public.profiles(id) on delete cascade,
  protection_enabled    boolean not null default true,
  max_opens             int not null default 3,
  max_duration_seconds  int not null default 30,
  applies_to            text not null default 'all',
  created_at            timestamptz not null default now(),
  unique (user_a, user_b),
  check (user_a <> user_b)
);
create index if not exists conversations_user_a_idx on public.conversations(user_a);
create index if not exists conversations_user_b_idx on public.conversations(user_b);

-- Messaggi (testo o foto). Il ciphertext include il nonce anteposto
-- (nonce || ciphertext, base64). Nessuna colonna nonce dedicata.
create table if not exists public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id       uuid not null references public.profiles(id) on delete cascade,
  type            text not null check (type in ('text','photo')),
  ciphertext      text,          -- per il testo cifrato (base64: nonce||ct)
  storage_path    text,          -- per la foto cifrata su Storage
  created_at      timestamptz not null default now()
);
create index if not exists messages_conversation_idx
  on public.messages(conversation_id, created_at);
create index if not exists messages_sender_idx on public.messages(sender_id);

-- Policy di accesso + contatore, uno per (messaggio, destinatario).
create table if not exists public.message_access (
  id                    uuid primary key default gen_random_uuid(),
  message_id            uuid not null references public.messages(id) on delete cascade,
  recipient_id          uuid not null references public.profiles(id) on delete cascade,
  wrapped_key           text not null,   -- K incapsulata (sealed box) per il destinatario
  protection_enabled    boolean not null default true,
  max_opens             int not null,
  max_duration_seconds  int not null,
  expires_at            timestamptz,     -- null finche' non avviene la prima apertura
  open_count            int not null default 0,
  active                boolean not null default true,
  created_at            timestamptz not null default now(),
  unique (message_id, recipient_id)
);
create index if not exists message_access_recipient_idx
  on public.message_access(recipient_id);

-- Registro eventi di apertura (fonte delle statistiche + Realtime al mittente).
create table if not exists public.open_events (
  id           uuid primary key default gen_random_uuid(),
  message_id   uuid not null references public.messages(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  opened_at    timestamptz not null default now(),
  outcome      text not null
    check (outcome in ('granted','denied_revoked','denied_expired','denied_limit'))
);
create index if not exists open_events_message_idx on public.open_events(message_id);

-- ----------------------------------------------------------------------------
-- 2) FUNZIONI HELPER
-- ----------------------------------------------------------------------------

-- Vero se auth.uid() partecipa alla conversazione indicata.
create or replace function public.is_participant(p_conversation_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1 from public.conversations c
    where c.id = p_conversation_id
      and (c.user_a = auth.uid() or c.user_b = auth.uid())
  );
$$;

-- ----------------------------------------------------------------------------
-- 3) ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------

alter table public.profiles       enable row level security;
alter table public.invite_codes   enable row level security;
alter table public.contacts       enable row level security;
alter table public.conversations  enable row level security;
alter table public.messages       enable row level security;
alter table public.message_access enable row level security;
alter table public.open_events    enable row level security;

-- profiles: leggibile a se stessi e ai propri contatti; scrittura solo propria.
drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or exists (select 1 from public.contacts c
               where c.owner = auth.uid() and c.contact = public.profiles.id)
  );
drop policy if exists "profiles_insert" on public.profiles;
create policy "profiles_insert" on public.profiles for insert to authenticated
  with check (id = auth.uid());
drop policy if exists "profiles_update" on public.profiles;
create policy "profiles_update" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- invite_codes: solo il proprietario legge/crea/cancella i propri.
-- (Il riscatto avviene via RPC SECURITY DEFINER redeem_invite.)
drop policy if exists "invites_select" on public.invite_codes;
create policy "invites_select" on public.invite_codes for select to authenticated
  using (owner = auth.uid());
drop policy if exists "invites_insert" on public.invite_codes;
create policy "invites_insert" on public.invite_codes for insert to authenticated
  with check (owner = auth.uid());
drop policy if exists "invites_delete" on public.invite_codes;
create policy "invites_delete" on public.invite_codes for delete to authenticated
  using (owner = auth.uid());

-- contacts: il proprietario legge i propri. Inserimento via redeem_invite.
drop policy if exists "contacts_select" on public.contacts;
create policy "contacts_select" on public.contacts for select to authenticated
  using (owner = auth.uid());

-- conversations: leggibile/aggiornabile dai due partecipanti. Insert via RPC.
drop policy if exists "conversations_select" on public.conversations;
create policy "conversations_select" on public.conversations for select to authenticated
  using (user_a = auth.uid() or user_b = auth.uid());
drop policy if exists "conversations_update" on public.conversations;
create policy "conversations_update" on public.conversations for update to authenticated
  using (user_a = auth.uid() or user_b = auth.uid())
  with check (user_a = auth.uid() or user_b = auth.uid());

-- messages: leggibile dai partecipanti; inseribile solo dal mittente.
drop policy if exists "messages_select" on public.messages;
create policy "messages_select" on public.messages for select to authenticated
  using (public.is_participant(conversation_id));
drop policy if exists "messages_insert" on public.messages;
create policy "messages_insert" on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.is_participant(conversation_id));

-- message_access: leggibile dal destinatario (per i contatori) e dal mittente
-- (per le statistiche); inseribile solo dal mittente del messaggio.
-- NB: la colonna wrapped_key e' esclusa dai GRANT di SELECT piu' sotto.
drop policy if exists "message_access_select" on public.message_access;
create policy "message_access_select" on public.message_access for select to authenticated
  using (
    recipient_id = auth.uid()
    or exists (select 1 from public.messages m
               where m.id = public.message_access.message_id and m.sender_id = auth.uid())
  );
drop policy if exists "message_access_insert" on public.message_access;
create policy "message_access_insert" on public.message_access for insert to authenticated
  with check (
    exists (select 1 from public.messages m
            where m.id = public.message_access.message_id and m.sender_id = auth.uid())
  );
-- Nessuna policy di UPDATE/DELETE: le mutazioni passano solo dalle RPC definer.

-- open_events: leggibile dal mittente dei propri messaggi (stats + realtime).
-- Nessuna policy di INSERT: gli eventi sono scritti solo dalle RPC definer.
drop policy if exists "open_events_select" on public.open_events;
create policy "open_events_select" on public.open_events for select to authenticated
  using (
    exists (select 1 from public.messages m
            where m.id = public.open_events.message_id and m.sender_id = auth.uid())
  );

-- ----------------------------------------------------------------------------
-- 4) GRANT A LIVELLO DI COLONNA (protezione di wrapped_key)
-- ----------------------------------------------------------------------------
-- Supabase concede di default privilegi ampi ai ruoli anon/authenticated: qui
-- li revochiamo su message_access e open_events e riconcediamo esplicitamente
-- solo cio' che serve, ESCLUDENDO wrapped_key dalla SELECT.

revoke all on table public.message_access from anon, authenticated;
grant select (
  id, message_id, recipient_id, protection_enabled,
  max_opens, max_duration_seconds, expires_at, open_count, active, created_at
) on table public.message_access to authenticated;
grant insert (
  message_id, recipient_id, wrapped_key, protection_enabled,
  max_opens, max_duration_seconds
) on table public.message_access to authenticated;

revoke all on table public.open_events from anon, authenticated;
grant select on table public.open_events to authenticated;

-- ----------------------------------------------------------------------------
-- 5) RPC: request_key (rilascio chiave atomico) — sezione 5.4 / 7 della spec
-- ----------------------------------------------------------------------------
create or replace function public.request_key(p_message_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  a public.message_access;
begin
  select * into a
  from public.message_access
  where message_id = p_message_id
    and recipient_id = auth.uid()
  for update;   -- lock di riga: atomicita' del check-and-increment

  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  -- La revoca vale SEMPRE, anche per i messaggi non protetti.
  if not a.active then
    insert into public.open_events(message_id, recipient_id, outcome)
      values (p_message_id, auth.uid(), 'denied_revoked');
    raise exception 'revoked' using errcode = 'P0001';
  end if;

  -- Protezione disattivata: apertura libera (nessun contatore ne' scadenza),
  -- ma solo se non revocata (controllo gia' fatto sopra).
  if a.protection_enabled = false then
    insert into public.open_events(message_id, recipient_id, outcome)
      values (p_message_id, auth.uid(), 'granted');
    return a.wrapped_key;
  end if;

  if a.expires_at is not null and now() > a.expires_at then
    update public.message_access set active = false where id = a.id;
    insert into public.open_events(message_id, recipient_id, outcome)
      values (p_message_id, auth.uid(), 'denied_expired');
    raise exception 'expired' using errcode = 'P0001';
  end if;

  -- max_opens = 0  => aperture illimitate
  if a.max_opens > 0 and a.open_count >= a.max_opens then
    insert into public.open_events(message_id, recipient_id, outcome)
      values (p_message_id, auth.uid(), 'denied_limit');
    raise exception 'limit_reached' using errcode = 'P0001';
  end if;

  -- max_duration_seconds = 0 => nessuna scadenza (expires_at resta null)
  update public.message_access
    set open_count = open_count + 1,
        expires_at = case
          when a.expires_at is not null then a.expires_at
          when a.max_duration_seconds > 0
            then now() + make_interval(secs => a.max_duration_seconds)
          else null
        end
    where id = a.id;

  insert into public.open_events(message_id, recipient_id, outcome)
    values (p_message_id, auth.uid(), 'granted');

  return a.wrapped_key;
end;
$$;

revoke all on function public.request_key(uuid) from public;
grant execute on function public.request_key(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 6) RPC: redeem_invite (aggiunta contatto + scambio chiavi, atomico)
-- ----------------------------------------------------------------------------
-- B chiama redeem_invite(codice di A). Crea (idempotente) le due righe contacts
-- e la conversation canonicalizzata, e restituisce il profilo di A + conv id.
create or replace function public.redeem_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner   uuid;
  v_me      uuid := auth.uid();
  v_a       uuid;
  v_b       uuid;
  v_conv    uuid;
  v_profile public.profiles;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  select owner into v_owner from public.invite_codes where code = p_code;
  if v_owner is null then
    raise exception 'invalid_code' using errcode = 'P0002';
  end if;
  if v_owner = v_me then
    raise exception 'cannot_add_self' using errcode = 'P0001';
  end if;

  -- canonicalizzazione della conversazione
  if v_owner < v_me then v_a := v_owner; v_b := v_me;
  else                   v_a := v_me;    v_b := v_owner;
  end if;

  insert into public.conversations(user_a, user_b)
    values (v_a, v_b)
    on conflict (user_a, user_b) do nothing;

  select id into v_conv from public.conversations
    where user_a = v_a and user_b = v_b;

  insert into public.contacts(owner, contact) values (v_me, v_owner)
    on conflict (owner, contact) do nothing;
  insert into public.contacts(owner, contact) values (v_owner, v_me)
    on conflict (owner, contact) do nothing;

  select * into v_profile from public.profiles where id = v_owner;

  return jsonb_build_object(
    'conversation_id', v_conv,
    'contact', jsonb_build_object(
      'id', v_profile.id,
      'display_name', v_profile.display_name,
      'public_key', v_profile.public_key
    )
  );
end;
$$;

revoke all on function public.redeem_invite(text) from public;
grant execute on function public.redeem_invite(text) to authenticated;

-- ----------------------------------------------------------------------------
-- 7) RPC: revoca (singolo messaggio / intera chat per i propri messaggi)
-- ----------------------------------------------------------------------------
create or replace function public.revoke_message(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.messages m
                 where m.id = p_message_id and m.sender_id = auth.uid()) then
    raise exception 'not_owner' using errcode = 'P0001';
  end if;
  update public.message_access set active = false where message_id = p_message_id;
end;
$$;
revoke all on function public.revoke_message(uuid) from public;
grant execute on function public.revoke_message(uuid) to authenticated;

create or replace function public.revoke_conversation(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_participant(p_conversation_id) then
    raise exception 'not_participant' using errcode = 'P0001';
  end if;
  update public.message_access ma
    set active = false
    from public.messages m
    where ma.message_id = m.id
      and m.conversation_id = p_conversation_id
      and m.sender_id = auth.uid();   -- revoca solo i messaggi inviati da me
end;
$$;
revoke all on function public.revoke_conversation(uuid) from public;
grant execute on function public.revoke_conversation(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 8) STORAGE (bucket privato per le foto cifrate) + policy
-- ----------------------------------------------------------------------------
-- Convenzione path: "<conversation_id>/<message_id>.bin"
insert into storage.buckets (id, name, public)
  values ('photos', 'photos', false)
  on conflict (id) do nothing;

drop policy if exists "photos_select" on storage.objects;
create policy "photos_select" on storage.objects for select to authenticated
  using (
    bucket_id = 'photos'
    and public.is_participant(((storage.foldername(name))[1])::uuid)
  );

-- Solo il caricatore (owner) puo' inserire/cancellare il proprio blob, e solo
-- entro una conversazione a cui partecipa. Il destinatario puo' leggerlo
-- (policy di select sopra) ma non sovrascriverlo/cancellarlo.
drop policy if exists "photos_insert" on storage.objects;
create policy "photos_insert" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'photos'
    and owner = auth.uid()
    and public.is_participant(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists "photos_delete" on storage.objects;
create policy "photos_delete" on storage.objects for delete to authenticated
  using (
    bucket_id = 'photos'
    and owner = auth.uid()
    and public.is_participant(((storage.foldername(name))[1])::uuid)
  );

-- ----------------------------------------------------------------------------
-- 9) REALTIME (consegna messaggi live + notifiche di apertura al mittente)
-- ----------------------------------------------------------------------------
-- La pubblicazione supabase_realtime esiste gia' su Supabase; aggiungiamo le
-- tabelle che ci servono. RLS continua ad applicarsi ai canali Realtime.
--
-- IMPORTANTE: NON pubblichiamo message_access. Realtime (postgres_changes)
-- applica solo il filtro di RIGA della RLS e NON i GRANT a livello di colonna:
-- pubblicare message_access spedirebbe l'intera riga (incluso wrapped_key) al
-- destinatario nel payload di INSERT, aggirando completamente request_key.
-- I client sottoscrivono solo messages (consegna) e open_events (statistiche).
do $$
begin
  begin
    alter publication supabase_realtime add table public.messages;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.open_events;
  exception when duplicate_object then null;
  end;
end $$;
