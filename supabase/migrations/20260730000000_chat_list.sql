-- ============================================================================
-- Lista chat in UNA sola query.
--
-- Prima il client faceva, PER OGNI conversazione, due richieste in sequenza
-- (ultimo messaggio + conteggio non letti): con 5 chat erano ~12 round trip,
-- ripetuti a ogni messaggio in arrivo. Era la causa della lista chat lenta.
--
-- Lo stato "letto" resta LOCALE al dispositivo (scelta di progetto: nessuna
-- tabella read_state sul server), quindi il client passa le proprie soglie in
-- `p_last_read`: { "<conversation_id>": "<timestamptz ISO>" }.
--
-- SECURITY DEFINER ma senza scorciatoie: la CTE `mine` limita tutto alle
-- conversazioni in cui l'utente autenticato è partecipante, e restituisce solo
-- dati che potrebbe già leggere via RLS.
-- ============================================================================

create or replace function public.chat_list(p_last_read jsonb default '{}'::jsonb)
returns table (
  conversation_id uuid,
  last_message    jsonb,
  unread          int
)
language sql
security definer
set search_path = public
as $$
  with mine as (
    select c.id
      from public.conversations c
     where c.user_a = auth.uid() or c.user_b = auth.uid()
  ),
  visible as (
    -- Messaggi che contano per anteprima e non letti: né eliminati né di
    -- sistema (richieste/riaperture non hanno contenuto).
    select m.*
      from public.messages m
      join mine mi on mi.id = m.conversation_id
     where m.deleted_at is null
       and m.type not in ('reopen_request', 'reopened')
  ),
  last_msg as (
    select distinct on (v.conversation_id) v.*
      from visible v
     order by v.conversation_id, v.created_at desc
  ),
  unread_cnt as (
    select mi.id as conversation_id,
           count(v.id)::int as n   -- count(v.id): con il left join un NULL non conta
      from mine mi
      left join visible v
        on v.conversation_id = mi.id
       and v.sender_id <> auth.uid()
       and v.created_at > coalesce(
             (p_last_read ->> mi.id::text)::timestamptz,
             '-infinity'::timestamptz)
     group by mi.id
  )
  select mi.id,
         -- Senza il CASE una conversazione vuota darebbe un oggetto di soli
         -- null invece di NULL, e il client proverebbe a costruirne un Message.
         case when lm.id is null then null::jsonb else to_jsonb(lm) end,
         coalesce(u.n, 0)
    from mine mi
    left join last_msg lm on lm.conversation_id = mi.id
    left join unread_cnt u on u.conversation_id = mi.id;
$$;

revoke all on function public.chat_list(jsonb) from public;
grant execute on function public.chat_list(jsonb) to authenticated;

-- ============================================================================
-- Ricevute di lettura di una conversazione in UNA query.
--
-- Prima ogni bolla interrogava il server per conto proprio (decine di richieste
-- per schermata). Interrogare `open_events` direttamente restituirebbe una riga
-- per APERTURA, non per messaggio: superato il tetto di righe di PostgREST
-- (1000) la risposta verrebbe troncata in modo arbitrario e alcuni messaggi già
-- letti perderebbero la terza spunta. Qui il `distinct` fa sì che le righe siano
-- al massimo quante i messaggi.
-- ============================================================================

create or replace function public.read_message_ids(p_conversation_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select distinct oe.message_id
    from public.open_events oe
    join public.messages m on m.id = oe.message_id
   where m.conversation_id = p_conversation_id
     and m.sender_id = auth.uid()        -- solo i MIEI messaggi
     and oe.outcome = 'granted'
     and oe.recipient_id <> auth.uid();  -- escludi le mie riletture
$$;

revoke all on function public.read_message_ids(uuid) from public;
grant execute on function public.read_message_ids(uuid) to authenticated;
