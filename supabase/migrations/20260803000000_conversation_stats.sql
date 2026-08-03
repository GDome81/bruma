-- ============================================================================
-- Statistiche di una conversazione calcolate SUL SERVER.
--
-- Prima il client scaricava le righe e contava in locale: PostgREST però
-- restituisce al massimo 1000 righe, quindi in una chat lunga i conteggi si
-- fermavano a 1000 (sembravano "congelati") e le visualizzazioni delle foto
-- erano incomplete, perché anche gli open_events venivano troncati.
--
-- Qui si conta in SQL: esatto, una sola richiesta, nessun tetto di righe.
--
-- SECURITY DEFINER, ma la CTE `guard` verifica che il chiamante sia
-- partecipante della conversazione; i conteggi delle visualizzazioni sono
-- limitati alle foto inviate DA LUI (come la RLS di open_events).
-- ============================================================================

create or replace function public.conversation_stats(p_conversation_id uuid)
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
  msgs as (
    select m.id, m.sender_id, m.type
      from public.messages m
     where m.conversation_id = p_conversation_id
       and m.deleted_at is null
       and m.type not in ('reopen_request', 'reopened')
       and exists (select 1 from guard)
  ),
  counts as (
    select
      count(*) filter (where sender_id =  auth.uid())                        as sent,
      count(*) filter (where sender_id <> auth.uid())                        as received,
      count(*) filter (where sender_id =  auth.uid() and type = 'photo')     as sent_photos,
      count(*) filter (where sender_id <> auth.uid() and type = 'photo')     as received_photos
    from msgs
  ),
  -- Aperture delle MIE foto da parte del destinatario (escluse le mie riletture).
  ev as (
    select oe.message_id, oe.outcome
      from public.open_events oe
      join msgs m on m.id = oe.message_id
     where m.sender_id = auth.uid()
       and m.type = 'photo'
       and oe.recipient_id <> auth.uid()
  ),
  views as (
    select message_id, count(*)::int as n
      from ev
     where outcome = 'granted'
     group by message_id
  )
  select jsonb_build_object(
    'sent',            (select sent             from counts),
    'received',        (select received         from counts),
    'sent_photos',     (select sent_photos      from counts),
    'received_photos', (select received_photos  from counts),
    'denied_photo',    (select count(*)::int from ev where outcome <> 'granted'),
    'views',           coalesce(
                         (select jsonb_object_agg(message_id::text, n) from views),
                         '{}'::jsonb)
  );
$$;

revoke all on function public.conversation_stats(uuid) from public;
grant execute on function public.conversation_stats(uuid) to authenticated;
