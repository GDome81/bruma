-- ============================================================================
-- Togliere una foto dalla galleria SENZA cancellarla: torna un contenuto
-- protetto/limitato normale (NON revocato → il blob resta). Solo il mittente.
-- Al contrario di revoke_message (che cancella il blob), qui il contenuto
-- rimane: ripristina i limiti della conversazione e rimuove la foto dalle
-- gallerie di tutti.
-- ============================================================================

create or replace function public.unoffer_from_gallery(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender uuid;
  v_conv   uuid;
  v_prot   boolean;
  v_opens  int;
  v_dur    int;
begin
  select m.sender_id, m.conversation_id into v_sender, v_conv
    from public.messages m where m.id = p_message_id;
  if v_sender is null or v_sender <> auth.uid() then
    raise exception 'not_owner' using errcode = 'P0001';
  end if;

  select c.protection_enabled, c.max_opens, c.max_duration_seconds
    into v_prot, v_opens, v_dur
    from public.conversations c where c.id = v_conv;

  update public.messages set gallery_offered = false where id = p_message_id;

  -- Copia del destinatario: torna protetta con i limiti della conversazione,
  -- contatore azzerato e scadenza da ricominciare alla prossima apertura.
  -- Non tocca `active` e NON cancella il blob.
  update public.message_access
    set protection_enabled   = coalesce(v_prot, true),
        max_opens            = coalesce(v_opens, 3),
        max_duration_seconds = coalesce(v_dur, 30),
        open_count           = 0,
        expires_at           = null
    where message_id = p_message_id and recipient_id <> auth.uid();

  -- Esce dalle gallerie di tutti (i segnalibri non hanno più senso: è limitata).
  delete from public.gallery_items where message_id = p_message_id;
end;
$$;

revoke all on function public.unoffer_from_gallery(uuid) from public;
grant execute on function public.unoffer_from_gallery(uuid) to authenticated;
