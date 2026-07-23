-- ============================================================================
-- Throttle notifiche — un solo timestamp per utente ("ultimo avviso sonoro").
-- Usato SOLO dalla Edge Function `send-push` (service role) per limitare la
-- frequenza degli avvisi: al massimo uno "sonoro" ogni N minuti; i messaggi nel
-- mezzo aggiornano la notifica in silenzio (web) o vengono saltati (FCM).
-- RLS attiva SENZA policy: gli utenti non possono leggere/scrivere questo
-- metadato (nessuna esposizione lato client); la service role aggira la RLS.
-- ============================================================================

create table if not exists public.notif_state (
  user_id          uuid primary key references public.profiles(id) on delete cascade,
  last_notified_at timestamptz
);

alter table public.notif_state enable row level security;
