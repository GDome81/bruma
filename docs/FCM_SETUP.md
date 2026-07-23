# Notifiche push Android (FCM) — setup

Codice già pronto nel repo (client + server). Restano i passi su **Firebase**
(li fai tu: servono i tuoi account Google) e su **Supabase**.

Il contenuto resta E2E: viaggia solo un 🌙 anonimo, senza mittente né testo.

## 1) Progetto Firebase
1. Vai su https://console.firebase.google.com → **Aggiungi progetto** (gratis).
2. Dentro il progetto → **Aggiungi app** → **Android**.
   - **Nome pacchetto**: `com.gdome.bruma` (deve combaciare, esatto).
   - (SHA-1 non serve per le notifiche.)
3. Scarica **`google-services.json`**.
   → **Passa a me questo file**: lo metto in `android/app/` e ricompilo l'APK.
   (Non è segreto — è la config client — ma lo teniamo fuori dal repo pubblico.)

## 2) Chiave service-account (per il server)
1. Firebase Console → ⚙️ **Impostazioni progetto** → **Account di servizio**.
2. **Genera nuova chiave privata** → scarica un file JSON.
   ⚠️ **QUESTO È SEGRETO** (contiene una chiave privata): non condividerlo, non
   committarlo. Va SOLO nei secret di Supabase (passo 4).
3. Verifica che l'API **Cloud Messaging (v1)** sia attiva (nei progetti nuovi
   lo è di default).

## 3) Migration Supabase
Dashboard → **SQL Editor** → incolla e lancia:
- `supabase/migrations/20260723000000_fcm.sql` (tabella `fcm_tokens`).

## 4) Secret della Edge Function
Dashboard → **Project Settings → Edge Functions → Secrets** (o via CLI), aggiungi:
- `FCM_SERVICE_ACCOUNT` = **tutto il contenuto** del JSON del passo 2.

Via CLI (in alternativa):
```
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat percorso/service-account.json)"
```

## 5) Ri-deploy della funzione
```
supabase functions deploy send-push --no-verify-jwt
```
(La stessa funzione gestisce ora sia Web Push sia FCM. Il webhook su INSERT di
`messages` è lo stesso già configurato — vedi `PUSH_SETUP.md`.)

## 6) Prova
1. Sull'APK: **Impostazioni → Attiva notifiche** → concedi il permesso (registra
   il token in `fcm_tokens`).
2. **Chiudi** l'app (anche swipe via).
3. Dall'altro account manda un messaggio → deve arrivare la notifica 🌙.

## Note
- Il payload è anonimo (🌙): FCM di Google fa da tramite, vede il token del
  dispositivo e i tempi, ma NON il mittente né il contenuto.
- I token scaduti (UNREGISTERED / 404) vengono ripuliti in automatico.
- In foreground le notifiche le gestisce già il realtime in-app (nessun
  doppione): FCM copre app in background/chiusa.
- Senza `google-services.json` l'APK **non compila** (il plugin Google Services
  lo richiede): è l'unico blocco finché non me lo passi.
