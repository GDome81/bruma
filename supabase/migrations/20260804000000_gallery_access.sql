-- ============================================================================
-- Stato di accesso di TUTTE le foto di una conversazione, in UNA query.
--
-- Serve a due schermate:
--  * "Le mie"    → quante aperture restano ALL'ALTRO sulle foto che ho inviato
--  * "Ricevute"  → quante aperture restano A ME sulle foto che ho ricevuto
--
-- Per ogni foto si restituisce la riga di accesso della CONTROPARTE se l'ho
-- inviata io, oppure la MIA riga se l'ho ricevuta: in entrambi i casi è
-- l'informazione "quante volte si può ancora aprire".
--
-- Calcolato in SQL e non lato client per lo stesso motivo di chat_list e
-- conversation_stats: il server restituisce al massimo 1000 righe, quindi
-- scaricare e filtrare in locale dava risultati troncati in silenzio.
--
-- SECURITY DEFINER, ma la CTE `guard` limita tutto alle conversazioni di cui il
-- chiamante è partecipante. Il mittente poteva già leggere il contatore del
-- destinatario (statistiche/ricevute): nessuna informazione nuova esposta.
-- La colonna wrapped_key NON viene mai restituita.
-- ============================================================================

create or replace function public.gallery_access(p_conversation_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with guard as (
    select 1
      from public.conversations c
     where c.id = p_conversation_id
       and (c.user_a = auth.uid() or c.user_b = auth.uid())
  ),
  photos as (
    select m.id, m.sender_id, m.gallery_offered
      from public.messages m
     where m.conversation_id = p_conversation_id
       and m.type = 'photo'
       and m.deleted_at is null
       and exists (select 1 from guard)
  ),
  joined as (
    select p.id                        as message_id,
           (p.sender_id = auth.uid())  as mine,
           p.gallery_offered,
           a.id                        as access_id,
           a.recipient_id,
           a.protection_enabled,
           a.max_opens,
           a.max_duration_seconds,
           a.expires_at,
           a.open_count,
           a.active
      from photos p
      join public.message_access a
        on a.message_id = p.id
       and (
             -- l'ho inviata io → la riga della controparte
             (p.sender_id =  auth.uid() and a.recipient_id <> auth.uid())
             -- l'ho ricevuta   → la mia riga
          or (p.sender_id <> auth.uid() and a.recipient_id =  auth.uid())
       )
  )
  select coalesce(
    jsonb_agg(jsonb_build_object(
      'id',                   access_id,
      'message_id',           message_id,
      'recipient_id',         recipient_id,
      'protection_enabled',   protection_enabled,
      'max_opens',            max_opens,
      'max_duration_seconds', max_duration_seconds,
      'expires_at',           expires_at,
      'open_count',           open_count,
      'active',               active,
      'mine',                 mine,
      'gallery_offered',      gallery_offered
    )),
    '[]'::jsonb)
  from joined;
$$;

revoke all on function public.gallery_access(uuid) from public;
grant execute on function public.gallery_access(uuid) to authenticated;
