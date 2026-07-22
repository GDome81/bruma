-- ============================================================================
-- Collega i nuovi messaggi alla Edge Function send-push SENZA usare la UI
-- "Webhooks" (spostata in alcune dashboard). Usa pg_net per una chiamata HTTP
-- ASINCRONA (non rallenta l'invio del messaggio).
--
-- PRIMA di eseguire: sostituisci i due segnaposto qui sotto:
--   <REF>       = la sigla del tuo progetto (dall'URL: https://<REF>.supabase.co)
--   <ANON_KEY>  = la anon key del progetto (Project Settings → API, oppure
--                 il file locale bruma.env.json)
-- ============================================================================

-- 1) Abilita pg_net (chiamate HTTP dal database).
create extension if not exists pg_net;

-- 2) Funzione che chiama la Edge Function passando la riga del messaggio.
create or replace function public.notify_new_message()
returns trigger
language plpgsql
security definer
set search_path = public, net
as $$
begin
  perform net.http_post(
    url := 'https://<REF>.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer <ANON_KEY>'
    ),
    body := jsonb_build_object('record', to_jsonb(NEW))
  );
  return NEW;
end;
$$;

-- 3) Trigger: a ogni nuovo messaggio, invia la push.
drop trigger if exists on_message_notify on public.messages;
create trigger on_message_notify
  after insert on public.messages
  for each row execute function public.notify_new_message();
