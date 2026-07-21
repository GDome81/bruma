# Bruma

App Android (Flutter) per lo scambio privato di **messaggi e foto effimere**,
cifrati end-to-end, con **apertura controllata** (X aperture, Y tempo, revoca) e
controlli applicati **lato server** in modo atomico.

> **Per completare setup ed esecuzione vai a [`SETUP.md`](SETUP.md).**
> Questo README descrive architettura, sicurezza e stato del progetto.

---

## Concetto

Chat privata dove le foto scattate in-app non entrano mai nella galleria, sono
cifrate E2E, e sono apribili dal destinatario solo un numero limitato di volte,
per un tempo limitato, finché il mittente non revoca — con statistiche di
apertura in tempo reale per il mittente.

## Stack

- **Client:** Flutter (Dart), target Android.
- **Backend:** Supabase — Postgres + RLS, Auth, Storage, Realtime, RPC `SECURITY DEFINER`.
- **Crittografia:** libsodium (`sodium` / `sodium_libs`).
  - Identità: coppia **X25519** per utente (privata solo sul device).
  - Key-wrapping: **sealed box** (`crypto_box_seal`).
  - Contenuti: **XChaCha20-Poly1305** con chiave `K` monouso.

## Modello crittografico

1. Ogni messaggio è cifrato con una chiave simmetrica `K` monouso
   (`nonce || ciphertext`; per il testo salvato in colonna, per la foto caricato su Storage).
2. `K` è **incapsulata con la chiave pubblica del destinatario** (sealed box) e salvata in
   `message_access.wrapped_key`. Il server la custodisce ma **non può leggerla**.
3. Per aprire, il destinatario chiama la RPC atomica **`request_key(message_id)`** che, in
   un'unica transazione con lock di riga, verifica *non revocato → dentro la finestra Y →
   aperture residue*, alla prima apertura imposta `expires_at`, incrementa il contatore,
   registra l'evento e **solo allora** restituisce `wrapped_key`.
4. Il client apre `K` con la chiave privata locale e **decifra in RAM**; il contenuto in
   chiaro non tocca mai il disco; durante la visione è attivo `FLAG_SECURE`.

### Scelte di sicurezza rilevanti (oltre la spec)

- **`wrapped_key` non è leggibile in `SELECT`**: `GRANT` a livello di colonna esclude
  quella colonna per il ruolo `authenticated`. Esce solo dalla RPC `request_key`. Così il
  destinatario non può bypassare il contatore leggendo la chiave direttamente.
- **Mutazioni protette**: `message_access` e `open_events` non hanno policy di
  `UPDATE`/`INSERT` per i client; cambiano solo tramite le funzioni `SECURITY DEFINER`
  (`request_key`, `revoke_*`). Gli eventi di apertura non sono falsificabili.
- **Scambio contatti atomico** via `redeem_invite` (crea le righe `contacts` bidirezionali
  e la `conversations` canonicalizzata, restituisce la chiave pubblica del contatto).
- **Eco in memoria del mittente**: poiché `K` è incapsulata solo per il destinatario, il
  mittente non potrebbe rileggere i propri invii; teniamo un'eco **solo in RAM** (mai su
  disco) così vede ciò che ha mandato nella sessione corrente, senza consumare il contatore
  del destinatario.

## Struttura del progetto

```
lib/
  main.dart              # bootstrap: sodium, Supabase, AppServices, AuthGate
  app.dart               # MaterialApp, AuthGate, IdentityGate (onboarding/recovery/home)
  core/
    config.dart          # SUPABASE_URL / ANON_KEY da --dart-define
    crypto/              # CryptoService (sealed box + XChaCha20)
    secure_store/        # KeyStore (chiave privata in flutter_secure_storage)
    models/              # modelli dati + parsing
    supabase/            # repository (auth, profile, contacts, conversations,
                         #   messages, access, stats, storage) + RPC atomiche
    app_services.dart    # service locator + identità + apertura/decifratura in RAM
  features/
    auth/  contacts/  chats/  conversation/  camera/  viewer/  settings/  stats/
  shared/                # tema, widget comuni, note sui limiti
supabase/
  migrations/20260720000000_init.sql   # schema completo (applicare su Supabase)
scripts/                 # setup-toolchain, run, build-apk, apply-supabase (PowerShell)
```

## Mappa fasi (spec §13) → implementazione

| Fase | Stato |
|---|---|
| 0 Setup (Flutter + schema) | ✅ |
| 1 Identità e chiavi | ✅ auth, keygen, secure storage, profilo |
| 2 Contatti | ✅ codice invito + QR + scan + `redeem_invite` |
| 3 Chat testo E2E | ✅ lista chat, conversazione, invio/ricezione, Realtime |
| 4 Foto in-app | ✅ camera in-app, cifratura, upload Storage |
| 5 Apertura controllata | ✅ `message_access`, `request_key`, viewer RAM-only, FLAG_SECURE, countdown |
| 6 Revoca e statistiche | ✅ revoca singola/totale + cancellazione blob, `open_events`, notifiche live |
| 7 Rifinitura | ✅ errori, stati vuoti, note sui limiti in UI, script build APK |

## Limiti noti (comunicati anche in-app, sezione 11 della spec)

- **FLAG_SECURE** blocca screenshot/registrazione schermo digitali, non la foto dello
  schermo fatta con un altro dispositivo.
- Un **client manomesso**, dopo una singola apertura, potrebbe conservare `K`: il limite di
  aperture vincola solo il client onesto (come tutte le app effimere).
- La **revoca** rende inservibile ciò che non è ancora stato aperto; non recupera ciò che è
  già stato visto/memorizzato fuori dall'app.

## Note di progettazione emerse dalla review

- **Impostazioni di protezione condivise.** Come da spec (§6, `conversations`), le regole sono
  una proprietà della conversazione ed entrambi i partecipanti possono modificarle. Di
  conseguenza la protezione dei messaggi *futuri* riflette l'ultima impostazione condivisa: un
  controparte potrebbe indebolirla. Le regole restano comunque **snapshot** sui messaggi già
  inviati (non modificabili a posteriori) e la **revoca** è sempre applicata lato server. Una
  versione più rigida renderebbe le impostazioni per-mittente.
- **`wrapped_key` e Realtime.** La chiave incapsulata **non** transita mai su Realtime (la
  tabella `message_access` non è pubblicata): Realtime applica solo la RLS di riga e non i
  grant di colonna, quindi pubblicarla vanificherebbe `request_key`.

## Miglioramenti futuri (non nell'ambito v1)

- Cancellazione automatica dei blob foto **dopo l'ultima apertura utile** (oggi la
  cancellazione avviene alla **revoca**; per l'ultima apertura servirebbe una Edge Function
  o un trigger). La revoca già cancella i blob delle proprie foto.
- Aggiornamento della lista chat più efficiente (oggi `watchAllMyMessages` usa un singolo
  stream ampio; si può filtrare/debouncare) e cache locale (`sqflite`) per l'uso offline.
- Video, chat di gruppo, iOS.
