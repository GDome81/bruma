-- ============================================================================
-- Promemoria notifiche — un solo timestamp per utente: "ultimo avviso sonoro".
-- Scritto e letto SOLO dalla Edge Function `send-push` (service role). Serve a
-- ri-avvisare (promemoria) se restano messaggi non letti dopo N minuti.
-- RLS attiva SENZA policy → i client non possono né leggere né scrivere questo
-- metadato (nessuna esposizione, nessun segnale di "app aperta"); la service
-- role aggira la RLS.
-- ============================================================================

create table if not exists public.notif_state (
  user_id          uuid primary key references public.profiles(id) on delete cascade,
  last_notified_at timestamptz
);

alter table public.notif_state enable row level security;
