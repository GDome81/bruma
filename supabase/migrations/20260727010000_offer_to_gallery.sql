-- ============================================================================
-- Offrire alla galleria una foto GIÀ inviata (dal mittente, dalla chat).
-- Imposta messages.gallery_offered = true e rende la copia del DESTINATARIO
-- protetta ma SENZA limiti (aperture illimitate, nessuna scadenza). Solo il
-- mittente del messaggio può farlo. Le mutazioni su message_access passano solo
-- da funzioni SECURITY DEFINER (i client non hanno UPDATE diretto).
-- ============================================================================

create or replace function public.offer_to_gallery(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender uuid;
begin
  select sender_id into v_sender from public.messages where id = p_message_id;
  if v_sender is null or v_sender <> auth.uid() then
    raise exception 'not_owner' using errcode = 'P0001';
  end if;

  update public.messages set gallery_offered = true where id = p_message_id;

  -- Copia del destinatario: protetta ma illimitata. Non tocca `active` né
  -- `open_count` (se era stata revocata, il blob è già perso: non la "resuscita").
  update public.message_access
    set protection_enabled = true,
        max_opens = 0,
        max_duration_seconds = 0,
        expires_at = null
    where message_id = p_message_id and recipient_id <> auth.uid();
end;
$$;

revoke all on function public.offer_to_gallery(uuid) from public;
grant execute on function public.offer_to_gallery(uuid) to authenticated;
