-- ============================================================================
-- Bruma — funzioni aggiuntive: reactions, elimina, modifica, richieste di
-- reinvio/rinnovo. Migration ADDITIVA (eseguibile dopo lo schema iniziale).
-- Applicare con: supabase db push, oppure incollare nel SQL Editor.
-- ============================================================================

-- ---- messages: modifica / eliminazione (soft) + citazione ----------------
alter table public.messages add column if not exists edited_at  timestamptz;
alter table public.messages add column if not exists deleted_at timestamptz;
alter table public.messages add column if not exists reply_to   uuid
  references public.messages(id) on delete set null;
-- (Le mutazioni su messages passano dalle RPC SECURITY DEFINER più sotto:
--  nessuna policy di UPDATE diretta per i client.)

-- ---- helper: posso vedere questo messaggio? ------------------------------
create or replace function public.can_see_message(p_message_id uuid)
returns boolean language sql stable security invoker set search_path = public as $$
  select exists (
    select 1 from public.messages m
    join public.conversations c on c.id = m.conversation_id
    where m.id = p_message_id
      and (c.user_a = auth.uid() or c.user_b = auth.uid())
  );
$$;

-- ---- reactions -----------------------------------------------------------
create table if not exists public.message_reactions (
  id         uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  emoji      text not null,
  created_at timestamptz not null default now(),
  unique (message_id, user_id)   -- una reaction per utente (aggiornabile)
);
create index if not exists message_reactions_message_idx
  on public.message_reactions(message_id);

alter table public.message_reactions enable row level security;

drop policy if exists "reactions_select" on public.message_reactions;
create policy "reactions_select" on public.message_reactions for select to authenticated
  using (public.can_see_message(message_id));

drop policy if exists "reactions_insert" on public.message_reactions;
create policy "reactions_insert" on public.message_reactions for insert to authenticated
  with check (user_id = auth.uid() and public.can_see_message(message_id));

drop policy if exists "reactions_update" on public.message_reactions;
create policy "reactions_update" on public.message_reactions for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.can_see_message(message_id));

drop policy if exists "reactions_delete" on public.message_reactions;
create policy "reactions_delete" on public.message_reactions for delete to authenticated
  using (user_id = auth.uid());

-- ---- content_requests (reinvio / rinnovo) --------------------------------
create table if not exists public.content_requests (
  id           uuid primary key default gen_random_uuid(),
  message_id   uuid not null references public.messages(id) on delete cascade,
  requester_id uuid not null references public.profiles(id) on delete cascade, -- destinatario
  owner_id     uuid not null references public.profiles(id) on delete cascade, -- mittente
  status       text not null default 'pending'
    check (status in ('pending','renewed','resent','denied')),
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz
);
create index if not exists content_requests_owner_idx
  on public.content_requests(owner_id, status);
create index if not exists content_requests_msg_idx
  on public.content_requests(message_id);

alter table public.content_requests enable row level security;

drop policy if exists "requests_select" on public.content_requests;
create policy "requests_select" on public.content_requests for select to authenticated
  using (requester_id = auth.uid() or owner_id = auth.uid());

drop policy if exists "requests_insert" on public.content_requests;
create policy "requests_insert" on public.content_requests for insert to authenticated
  with check (
    requester_id = auth.uid()
    and owner_id <> auth.uid()
    -- il richiedente deve essere davvero destinatario del messaggio e owner_id
    -- deve esserne il vero mittente
    and exists (
      select 1 from public.messages m
      join public.message_access ma on ma.message_id = m.id
      where m.id = content_requests.message_id
        and m.sender_id = content_requests.owner_id
        and ma.recipient_id = auth.uid()
    )
  );

drop policy if exists "requests_update" on public.content_requests;
create policy "requests_update" on public.content_requests for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- ---- RPC: modifica testo (ciphertext + due wrapped_key + edited_at) ------
create or replace function public.edit_text_message(
  p_message_id uuid,
  p_ciphertext text,
  p_wrapped_recipient text,
  p_wrapped_self text
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.messages m
    where m.id = p_message_id and m.sender_id = auth.uid() and m.type = 'text'
  ) then
    raise exception 'not_owner' using errcode = 'P0001';
  end if;

  update public.messages
    set ciphertext = p_ciphertext, edited_at = now()
    where id = p_message_id;

  update public.message_access set wrapped_key = p_wrapped_recipient
    where message_id = p_message_id and recipient_id <> auth.uid();
  update public.message_access set wrapped_key = p_wrapped_self
    where message_id = p_message_id and recipient_id = auth.uid();
end; $$;
revoke all on function public.edit_text_message(uuid, text, text, text) from public;
grant execute on function public.edit_text_message(uuid, text, text, text) to authenticated;

-- ---- RPC: eliminazione (soft) di un proprio messaggio --------------------
create or replace function public.delete_message(p_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.messages m
    where m.id = p_message_id and m.sender_id = auth.uid()
  ) then
    raise exception 'not_owner' using errcode = 'P0001';
  end if;
  update public.messages
    set deleted_at = now(), ciphertext = null, storage_path = null
    where id = p_message_id;
  delete from public.message_access where message_id = p_message_id;
end; $$;
revoke all on function public.delete_message(uuid) from public;
grant execute on function public.delete_message(uuid) to authenticated;

-- ---- RPC: rinnovo limiti (mittente) sulla riga del destinatario ----------
create or replace function public.renew_access(p_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.messages m
    where m.id = p_message_id and m.sender_id = auth.uid()
  ) then
    raise exception 'not_owner' using errcode = 'P0001';
  end if;
  update public.message_access
    set open_count = 0, active = true, expires_at = null
    where message_id = p_message_id and recipient_id <> auth.uid();
end; $$;
revoke all on function public.renew_access(uuid) from public;
grant execute on function public.renew_access(uuid) to authenticated;

-- ---- Realtime ------------------------------------------------------------
do $$
begin
  begin
    alter publication supabase_realtime add table public.message_reactions;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.content_requests;
  exception when duplicate_object then null;
  end;
end $$;
