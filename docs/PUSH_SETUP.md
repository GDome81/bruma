# Notifiche push (Web Push / PWA) — setup Supabase

Codice già pronto nel repo:
- Client: si registra e salva la subscription (pulsante **Impostazioni → Sicurezza → Attiva notifiche**).
- Service worker push: `web/push-sw.js` (mostra 🌙, nessun contenuto).
- Tabella + RLS: `supabase/migrations/20260722000000_push.sql`.
- Edge Function: `supabase/functions/send-push/index.ts`.

Restano da fare **su Supabase** (una volta sola). Ti servono la **Supabase CLI**
(`npm i -g supabase`) e il *project ref* (lo trovi nell'URL del progetto).

## 1) Applica la migration
Dashboard → **SQL Editor** → incolla e lancia il contenuto di
`supabase/migrations/20260722000000_push.sql`.
(Oppure `supabase db push` se usi la CLI collegata.)

## 2) Chiavi VAPID
Sono già generate (te le ho date in chat):
- **Public** (non segreta, già nel client `AppConfig.vapidPublicKey`):
  `BLaSx24EtYwcukwWWYfLZzQ5NMhY-dzcUgiKHpw2vkh8ko3OpUpFSqU5WZ_gj9N8Chl9-EAey2ACQEsc234WFdI`
- **Private** (SEGRETA — NON committarla): è quella che ti ho dato in chat.

Imposta i secret della Edge Function (la private key qui):
```
supabase secrets set VAPID_PUBLIC_KEY=BLaSx24EtYwcukwWWYfLZzQ5NMhY-dzcUgiKHpw2vkh8ko3OpUpFSqU5WZ_gj9N8Chl9-EAey2ACQEsc234WFdI
supabase secrets set VAPID_PRIVATE_KEY=<LA_TUA_CHIAVE_PRIVATA>
supabase secrets set VAPID_SUBJECT=mailto:domenico.giacobino@enginius.com
```
(`SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` sono iniettati in automatico.)

> Se in futuro rigeneri le chiavi, DEVONO combaciare client (public) e
> Edge Function (public+private), altrimenti il push viene rifiutato.

## 3) Deploy della Edge Function
```
supabase functions deploy send-push --no-verify-jwt
```
`--no-verify-jwt` serve perché la chiama un webhook del database, non un utente.

## 4) Collega i messaggi alla funzione
Se nella tua dashboard esiste **Database → Webhooks**, puoi usare quello
(Insert su `messages` → POST a `functions/v1/send-push` con header
`Authorization: Bearer <ANON_KEY>`).

Se **NON** vedi "Webhooks" (dashboard recenti), usa il modo via SQL — più
affidabile: apri **SQL Editor**, incolla `supabase/push_webhook.sql` DOPO aver
sostituito `<REF>` (sigla progetto dall'URL) e `<ANON_KEY>` (Project Settings →
API, o il file locale `bruma.env.json`), poi **Run**. Crea un trigger che
chiama la funzione a ogni nuovo messaggio (chiamata asincrona via pg_net).

## 5) Prova
1. Sul telefono apri la PWA installata → **Attiva notifiche** → consenti.
2. (Verifica: in `push_subscriptions` deve comparire una riga per il tuo utente.)
3. Metti la PWA in background o chiudila.
4. Dall'altro account manda un messaggio → deve arrivare la notifica 🌙.

## Note
- Il payload è **anonimo** (solo 🌙): il servizio push non vede mittente né contenuto.
- iOS: funziona solo con PWA **installata** (Aggiungi a schermata Home), iOS 16.4+.
- Le subscription scadute (404/410) vengono ripulite in automatico dalla funzione.
- Per l'APK nativo (futuro) si aggiungerà FCM, riusando la stessa tabella/logica.
