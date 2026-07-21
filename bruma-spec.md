# Bruma — documento di specifica prodotto

> Documento di sviluppo destinato a Claude Code. Descrive un'app Android (Flutter) per lo
> scambio privato di messaggi e foto effimere, con controlli di accesso applicati lato server.
> È scritto per essere eseguibile: leggi le sezioni nell'ordine, e usa la sezione "Fasi di
> sviluppo" come piano di lavoro incrementale.

---

## 1. Concetto in una riga

Bruma è una chat privata dove le foto scattate in-app non finiscono mai nella galleria, sono
cifrate end-to-end, e possono essere aperte dal destinatario solo un numero limitato di volte,
per un tempo limitato, e solo finché il mittente non revoca la condivisione — con statistiche
di apertura visibili al mittente.

---

## 2. Visione e principi guida

- **Privacy reale, non estetica.** La cifratura è end-to-end: il server custodisce dati
  illeggibili. Nessun contenuto in chiaro deve mai toccare il server.
- **I contenuti sono ospiti, non residenti.** Le foto vivono cifrate sul dispositivo e/o
  temporaneamente sullo storage; il contenuto in chiaro esiste solo in RAM durante la
  visualizzazione e viene scartato subito dopo.
- **Il controllo resta al mittente.** Il mittente può revocare in qualsiasi momento; da quel
  momento il contenuto diventa inservibile per il destinatario.
- **Onestà sui limiti.** L'app applica deterrenti forti ma non promette l'impossibile (vedi
  sezione 11). Le limitazioni vanno comunicate all'utente, non nascoste.

---

## 3. Ambito v1 e non-obiettivi

### Nell'ambito (v1)
- Registrazione/identità utente (Supabase Auth).
- Aggiunta contatti tramite codice invito condivisibile + QR.
- Lista chat in stile WhatsApp semplificato.
- Chat 1-a-1 con messaggi di testo e foto.
- Fotocamera in-app; le foto non entrano mai nella galleria di sistema.
- Cifratura end-to-end (testo e foto).
- Impostazioni di protezione **configurabili per singola chat**, valide per tutti i contenuti
  di quella chat.
- Apertura controllata (X aperture, Y tempo dalla prima apertura, revoca).
- Statistiche di apertura per il mittente, anche in tempo reale.
- Blocco screenshot/registrazione schermo durante la visualizzazione (best-effort).
- Distribuzione come APK (nessuna pubblicazione su Play Store richiesta in v1).

### Fuori ambito (v1)
- Video (rinviati a versione futura).
- Chat di gruppo.
- Chiamate audio/video.
- Backup cloud dei contenuti in chiaro.
- iOS (il target è Android; l'architettura resta comunque portabile).

---

## 4. Stack tecnologico

- **Client:** Flutter (Dart), target Android, output APK.
- **Backend:** Supabase
  - Postgres (dati relazionali, con Row Level Security).
  - Auth (identità utente).
  - Storage (blob delle foto cifrate).
  - Realtime (consegna messaggi live + notifiche di apertura).
  - Edge Functions / RPC Postgres `SECURITY DEFINER` (logica di rilascio chiave).
- **Crittografia lato client:** pacchetto `cryptography` (o `libsodium`/`sodium`).
  - Coppia di chiavi asimmetriche per utente (curve X25519 per il key-wrapping).
  - Cifratura simmetrica dei contenuti (XChaCha20-Poly1305 o AES-GCM).

### Pacchetti Flutter previsti
- `supabase_flutter` — client Supabase (auth, db, storage, realtime).
- `camera` — fotocamera in-app.
- `path_provider` — accesso allo storage interno privato dell'app.
- `cryptography` (o `sodium`) — cifratura E2E.
- `sqflite` — indice/metadati locali e cache.
- `qr_flutter` — generazione del QR del codice invito.
- `mobile_scanner` — scansione del QR.
- `screen_protector` — blocco screenshot / registrazione schermo (FLAG_SECURE).
- `flutter_secure_storage` — custodia della chiave privata dell'utente sul dispositivo.

---

## 5. Modello di sicurezza (leggere con attenzione)

### 5.1 Identità e chiavi
- Alla registrazione, il client genera **localmente** una coppia di chiavi (pubblica/privata).
- La **chiave privata** viene salvata solo sul dispositivo (`flutter_secure_storage`) e non
  lascia mai il telefono.
- La **chiave pubblica** viene caricata nel profilo su Supabase.

### 5.2 Scambio chiavi = aggiunta contatto
Aggiungere un contatto tramite codice invito è anche il momento dello scambio delle chiavi
pubbliche. Quando B usa il codice di A, il client di B recupera e memorizza la chiave pubblica
di A (e viceversa alla conferma). Da quel momento i due possono cifrare l'uno per l'altro.

### 5.3 Cifratura dei contenuti (testo e foto, stesso schema)
Ogni messaggio (di qualsiasi tipo) è cifrato con una **chiave simmetrica `K` monouso**:
1. Il client genera `K` casuale.
2. Cifra il contenuto con `K`:
   - **testo** → ciphertext salvato nella colonna del messaggio;
   - **foto** → ciphertext caricato su Supabase Storage, nel messaggio si salva solo il path.
3. `K` viene **incapsulata (wrapped) con la chiave pubblica del destinatario** e salvata come
   `wrapped_key`. Il server custodisce `wrapped_key` ma **non può leggerla**: solo la chiave
   privata del destinatario la apre.

### 5.4 Apertura controllata
Il destinatario **non riceve mai `K` liberamente**. Per aprire un contenuto chiama la RPC
`request_key(message_id)` sul server, che esegue in **un'unica transazione atomica**:
1. `active == true` ? (condivisione non revocata)
2. Se `expires_at` è già impostato: `now < expires_at` ? (dentro la finestra di tempo Y)
3. `open_count < max_opens` ? (aperture residue X)

Se tutti i controlli passano:
- se è la **prima apertura**, imposta `expires_at = now + max_duration_seconds` (avvia il
  conto alla rovescia Y);
- incrementa `open_count`;
- registra un evento `granted` in `open_events`;
- restituisce `wrapped_key`.

Altrimenti registra l'evento con l'esito (`denied_revoked` / `denied_expired` /
`denied_limit`) e nega. In caso di scadenza, imposta anche `active = false`.

L'atomicità è obbligatoria: senza di essa due tap ravvicinati potrebbero superare entrambi il
controllo `open_count < max_opens` prima dell'incremento.

### 5.5 Visualizzazione
- Il client scarica il ciphertext, ottiene `wrapped_key` dalla RPC, la apre con la chiave
  privata, decifra **in RAM**.
- Il contenuto in chiaro **non viene mai scritto su disco**.
- Durante la visualizzazione è attivo `screen_protector` (FLAG_SECURE): niente screenshot né
  registrazione schermo.
- Allo scadere della finestra o all'uscita, la chiave e il buffer in chiaro vengono scartati.

### 5.6 Revoca
Revocare (per singolo messaggio o per intera chat) imposta `active = false` sulle righe di
accesso interessate. Da quel momento ogni `request_key` viene negata: sul dispositivo del
destinatario resta solo ciphertext inservibile.

---

## 6. Impostazioni di protezione per chat

Le regole di protezione sono una proprietà della **conversazione** e fanno da modello per ogni
nuovo messaggio.

Campi configurabili per chat:
- `protection_enabled` (bool) — se attivo, i contenuti seguono le regole; se disattivo, i
  contenuti sono cifrati E2E ma apribili senza limiti e senza scadenza.
- `max_opens` (int) — numero massimo di aperture (X).
- `max_duration_seconds` (int) — durata della finestra di visualizzazione dalla prima
  apertura (Y).
- `applies_to` — in v1 sempre `all` (testo + foto).

Comportamento:
- Le impostazioni vengono **"stampate" (snapshot) su ogni messaggio al momento dell'invio**,
  in una riga `message_access`. Modificare le impostazioni della chat influisce solo sui
  messaggi **futuri**; i messaggi già inviati mantengono la policy con cui sono partiti. Questo
  rende il comportamento prevedibile.
- La revoca è un'azione separata e agisce anche sui messaggi già inviati (imposta
  `active = false`), sia per singolo messaggio sia con un'azione "revoca tutto" a livello di
  chat.

---

## 7. Modello dati (Postgres / Supabase)

> Schema iniziale di partenza. Attivare Row Level Security su tutte le tabelle: ogni utente può
> leggere/scrivere solo i propri dati. La RPC `request_key` è `SECURITY DEFINER` per eseguire
> il controllo privilegiato in modo atomico.

```sql
-- Profilo utente (id coincide con auth.uid())
create table profiles (
  id           uuid primary key references auth.users(id),
  display_name text not null,
  public_key   text not null,
  created_at   timestamptz not null default now()
);

-- Codici invito condivisibili
create table invite_codes (
  code       text primary key,
  owner      uuid not null references profiles(id),
  created_at timestamptz not null default now()
);

-- Relazione di contatto (una riga per direzione)
create table contacts (
  id         uuid primary key default gen_random_uuid(),
  owner      uuid not null references profiles(id),
  contact    uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  unique (owner, contact)
);

-- Conversazione 1-a-1 + impostazioni di protezione (modello per i messaggi)
create table conversations (
  id                    uuid primary key default gen_random_uuid(),
  user_a                uuid not null references profiles(id),
  user_b                uuid not null references profiles(id),
  protection_enabled    boolean not null default true,
  max_opens             int not null default 3,
  max_duration_seconds  int not null default 30,
  applies_to            text not null default 'all',
  created_at            timestamptz not null default now(),
  unique (user_a, user_b)
);

-- Messaggi (testo o foto)
create table messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id),
  sender_id       uuid not null references profiles(id),
  type            text not null check (type in ('text','photo')),
  ciphertext      text,          -- per il testo cifrato
  storage_path    text,          -- per la foto cifrata su Storage
  created_at      timestamptz not null default now()
);

-- Policy di accesso + contatore, uno per (messaggio, destinatario)
create table message_access (
  id                    uuid primary key default gen_random_uuid(),
  message_id            uuid not null references messages(id),
  recipient_id          uuid not null references profiles(id),
  wrapped_key           text not null,   -- K incapsulata per il destinatario
  max_opens             int not null,
  max_duration_seconds  int not null,
  expires_at            timestamptz,     -- null finché non avviene la prima apertura
  open_count            int not null default 0,
  active                boolean not null default true,
  unique (message_id, recipient_id)
);

-- Registro eventi di apertura (fonte delle statistiche)
create table open_events (
  id           uuid primary key default gen_random_uuid(),
  message_id   uuid not null references messages(id),
  recipient_id uuid not null references profiles(id),
  opened_at    timestamptz not null default now(),
  outcome      text not null  -- granted | denied_revoked | denied_expired | denied_limit
);
```

### RPC di rilascio chiave (atomica)

```sql
create or replace function request_key(p_message_id uuid)
returns text
language plpgsql
security definer
as $$
declare
  a message_access;
begin
  select * into a
  from message_access
  where message_id = p_message_id
    and recipient_id = auth.uid()
  for update;   -- lock di riga: garantisce l'atomicità del check-and-increment

  if not found then
    raise exception 'not_found';
  end if;

  if not a.active then
    insert into open_events(message_id, recipient_id, outcome)
      values (p_message_id, auth.uid(), 'denied_revoked');
    raise exception 'revoked';
  end if;

  if a.expires_at is not null and now() > a.expires_at then
    update message_access set active = false where id = a.id;
    insert into open_events(message_id, recipient_id, outcome)
      values (p_message_id, auth.uid(), 'denied_expired');
    raise exception 'expired';
  end if;

  if a.open_count >= a.max_opens then
    insert into open_events(message_id, recipient_id, outcome)
      values (p_message_id, auth.uid(), 'denied_limit');
    raise exception 'limit_reached';
  end if;

  update message_access
    set open_count = open_count + 1,
        expires_at = coalesce(expires_at, now() + make_interval(secs => a.max_duration_seconds))
    where id = a.id;

  insert into open_events(message_id, recipient_id, outcome)
    values (p_message_id, auth.uid(), 'granted');

  return a.wrapped_key;
end;
$$;
```

---

## 8. Flussi principali

### 8.1 Registrazione / onboarding
1. L'utente si registra (Supabase Auth).
2. Il client genera la coppia di chiavi; salva la privata in `flutter_secure_storage`.
3. Crea il profilo con `display_name` e `public_key`.
4. Genera un `invite_code` personale.

### 8.2 Aggiunta contatto (con scambio chiavi)
1. A condivide il proprio codice (testo o QR).
2. B inserisce/scansiona il codice → lookup in `invite_codes` → recupera profilo e chiave
   pubblica di A.
3. Si creano le righe in `contacts` e la `conversations` relativa (con impostazioni di
   protezione di default).

### 8.3 Invio di un contenuto
1. Il client genera `K`, cifra il contenuto.
2. Foto → carica ciphertext su Storage; testo → salva ciphertext nel messaggio.
3. Incapsula `K` con la chiave pubblica del destinatario → `wrapped_key`.
4. Inserisce il messaggio e la relativa `message_access`, copiando `max_opens` e
   `max_duration_seconds` dalle impostazioni della conversazione (snapshot).

### 8.4 Apertura di un contenuto (destinatario)
1. Tap su "apri" → chiama `request_key(message_id)`.
2. Se concessa, ottiene `wrapped_key`, la apre con la chiave privata, decifra in RAM.
3. Mostra il contenuto con `screen_protector` attivo; avvia il conto alla rovescia Y.
4. Alla fine scarta chiave e buffer.

### 8.5 Revoca
- Il mittente revoca un messaggio o l'intera chat → `active = false` sulle righe interessate.

### 8.6 Statistiche
- Il mittente legge `open_events` per le proprie foto (quando, quante volte, tentativi falliti).
- Con Supabase Realtime riceve notifica live all'apertura (subscribe agli insert su
  `open_events` dei propri messaggi).

---

## 9. Schermate (UI stile WhatsApp semplificato)

1. **Autenticazione** — login/registrazione.
2. **Lista chat** — elenco conversazioni con anteprima ultimo messaggio; i contenuti protetti
   mostrano un'icona lucchetto invece dell'anteprima.
3. **Conversazione** — bolle testo (dx/sx); i contenuti protetti appaiono come bolla "Tocca per
   aprire" con "N aperture rimaste"; barra input con pulsante fotocamera.
4. **Aggiungi contatto** — mostra il proprio codice + QR + pulsante "Condividi"; campo per
   inserire il codice di un altro (o scansione QR).
5. **Fotocamera in-app** — scatto che salva solo nello storage privato cifrato.
6. **Visualizzatore contenuto** — decifrazione in RAM, FLAG_SECURE attivo, conto alla rovescia.
7. **Impostazioni chat** — toggle protezione, `max_opens`, `max_duration`, azione "revoca
   tutto".
8. **Statistiche** (accessibile dal mittente) — eventi di apertura per messaggio/chat.

---

## 10. Struttura di progetto suggerita (Flutter)

```
lib/
  main.dart
  core/
    crypto/          # generazione chiavi, wrap/unwrap, cifratura simmetrica
    supabase/        # client, auth, repository (profiles, contacts, messages...)
    secure_store/    # gestione chiave privata locale
  features/
    auth/
    contacts/        # codice invito, QR, scambio chiavi
    chats/           # lista chat
    conversation/    # bolle, invio, apertura
    camera/          # fotocamera in-app
    viewer/          # visualizzatore RAM-only + FLAG_SECURE
    settings/        # impostazioni protezione per chat
    stats/           # statistiche apertura
  shared/            # widget comuni, tema, utili
```

---

## 11. Limiti noti (da comunicare all'utente, non nascondere)

- **Foto dello schermo con un altro dispositivo.** `FLAG_SECURE` blocca screenshot e
  registrazione schermo digitali, ma non impedisce di fotografare lo schermo con un secondo
  telefono. Nessuna app può chiudere questo buco.
- **Client manomesso.** Una volta che il destinatario ha ottenuto `K` e decifrato anche una
  sola volta, un client modificato potrebbe conservarla e ignorare il contatore. Il limite "X
  aperture" vincola solo i client onesti (l'app non manomessa). È lo stesso limite di tutte le
  app effimere (Snapchat inclusa).
- **La revoca non riscrive il passato istantaneo.** La revoca rende inservibili i contenuti
  non ancora aperti/riaperti; non può recuperare ciò che è già stato visto e memorizzato
  fuori dall'app.

Questi limiti vanno resi espliciti nell'interfaccia (es. una nota nelle impostazioni di
protezione), così l'utente ha aspettative corrette.

---

## 12. Note sul piano gratuito Supabase

Il free tier copre bene un progetto di questa scala (Postgres, Auth, Storage ~1 GB, Realtime).
Due avvertenze pratiche:
- i progetti gratuiti vengono messi in pausa dopo un periodo di inattività (riattivabili con un
  click);
- i limiti esatti cambiano nel tempo: verificare i valori attuali sul sito di Supabase prima di
  dimensionare.

Le foto vengono cancellate dallo Storage dopo l'ultima apertura utile / alla revoca, per
mantenere l'occupazione bassa e coerente con lo spirito "i contenuti non risiedono online".

---

## 13. Fasi di sviluppo (piano incrementale per Claude Code)

**Fase 0 — Setup**
- Progetto Flutter + integrazione `supabase_flutter`.
- Creazione schema Postgres (sezione 7) + RLS + RPC.

**Fase 1 — Identità e chiavi**
- Auth, generazione coppia di chiavi, salvataggio chiave privata locale, creazione profilo.

**Fase 2 — Contatti**
- Generazione codice invito + QR, inserimento/scansione, scambio chiavi pubbliche, lista
  contatti.

**Fase 3 — Chat testuale E2E**
- Lista chat, conversazione, invio/ricezione testo cifrato, consegna live via Realtime.

**Fase 4 — Foto in-app**
- Fotocamera in-app, salvataggio in storage privato, cifratura, upload su Storage, bolla foto.

**Fase 5 — Apertura controllata**
- Impostazioni protezione per chat, `message_access`, RPC `request_key`, visualizzatore
  RAM-only + `screen_protector`, conto alla rovescia.

**Fase 6 — Revoca e statistiche**
- Revoca singola/totale, cancellazione blob, lettura `open_events`, notifiche live di apertura.

**Fase 7 — Rifinitura**
- Gestione errori, stati vuoti, note sui limiti in UI, build APK.

---

## Appendice — Nome del prodotto

Proposta principale: **Bruma** (foschia che appare e si dissolve).

Alternative:
- **Velo** — ciò che copre e si toglie.
- **Effimera** — dichiaratamente "che dura poco".
- **Sfumo** — dall'italiano "sfumare/svanire".
