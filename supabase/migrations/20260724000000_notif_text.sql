-- ============================================================================
-- Testo notifica personalizzato (mascheramento): il destinatario può scegliere
-- titolo/testo generico al posto del 🌙. Letto dalla Edge Function `send-push`.
-- NULL = usa il default ("Bruma" / "🌙").
-- ============================================================================

alter table public.notif_prefs add column if not exists notif_title text;
alter table public.notif_prefs add column if not exists notif_body  text;
