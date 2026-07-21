# Bruma — Guida al completamento

Questa guida elenca **solo ciò che manca** per avere l'app funzionante sul tuo
telefono. Il codice, lo schema del database e gli script sono già pronti.

---

## Stato attuale (già fatto)

- ✅ Progetto Flutter completo (fasi 0–7 della spec), `flutter analyze` pulito, test verdi.
- ✅ Flutter SDK installato in `C:\src\flutter` (stable 3.44, Dart 3.12).
- ✅ Dipendenze risolte (`flutter pub get` ok).
- ✅ Schema Supabase completo (tabelle + RLS + grant di colonna + RPC atomiche + Storage + Realtime) in
  [`supabase/migrations/20260720000000_init.sql`](supabase/migrations/20260720000000_init.sql).
- ✅ Crittografia E2E con libsodium (sealed box + XChaCha20-Poly1305).

## Cosa manca (serve il tuo intervento — richiede il PC e il telefono)

1. Installare la toolchain Android (Android Studio + SDK + licenze).
2. Creare il progetto Supabase cloud e applicare lo schema.
3. Incollare URL + anon key in `bruma.env.json`.
4. Collegare il telefono ed eseguire.

---

## 1) Toolchain Android

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup-toolchain.ps1
```

Lo script aggiunge Flutter al PATH e installa Android Studio via winget. Poi, **manualmente**:

1. Apri **Android Studio** una volta e completa il primo avvio (installa *Android SDK* e *platform-tools* dal SDK Manager).
2. Accetta le licenze:
   ```powershell
   flutter doctor --android-licenses
   ```
3. Verifica che sia tutto a posto (Android verde; Chrome/Visual Studio non servono):
   ```powershell
   flutter doctor
   ```

---

## 2) Supabase (cloud, free tier)

1. Vai su **https://supabase.com** → registrati → **New project**.
   - Scegli una regione vicina (es. *West EU*), imposta una password DB robusta.
   - Attendi ~2 minuti il provisioning.

2. **Applica lo schema** (una volta sola).
   - **Opzione A — consigliata (nessun tool):** Dashboard → **SQL Editor** → *New query* →
     incolla **tutto** il contenuto di `supabase/migrations/20260720000000_init.sql` → **Run**.
   - **Opzione B — CLI:** installa la [Supabase CLI](https://supabase.com/docs/guides/cli), poi:
     ```powershell
     powershell -ExecutionPolicy Bypass -File scripts\apply-supabase.ps1 -ProjectRef <IL-TUO-REF>
     ```

3. **Verifica** nel dashboard:
   - *Table Editor*: esistono `profiles`, `invite_codes`, `contacts`, `conversations`,
     `messages`, `message_access`, `open_events`.
   - *Storage*: esiste il bucket **`photos`** (privato).
   - *Database → Publications*: `supabase_realtime` include `messages` e `open_events`.

4. **Auth email.** Dashboard → *Authentication → Providers → Email* deve essere abilitato.
   - Per un test rapido, disattiva **"Confirm email"** (*Authentication → Sign In / Providers*):
     così la registrazione effettua subito l'accesso. In produzione lascialo attivo.

5. **Chiavi.** Dashboard → *Project Settings → API*:
   - copia **Project URL**
   - copia la **anon public key** (nelle versioni nuove si chiama *publishable key*).

---

## 3) Configura l'app

Copia il template e incolla i valori del passo 2.5:

```powershell
Copy-Item bruma.env.example.json bruma.env.json
notepad bruma.env.json
```

```json
{
  "SUPABASE_URL": "https://xxxxxxxx.supabase.co",
  "SUPABASE_ANON_KEY": "eyJhbGciOi..."
}
```

> `bruma.env.json` è già in `.gitignore`: non finirà nel controllo versione.

---

## 4) Esegui sul telefono

1. Sul telefono: *Impostazioni → Opzioni sviluppatore → Debug USB* attivo; collega via USB e autorizza il PC.
2. Verifica che Flutter lo veda:
   ```powershell
   flutter devices
   ```
3. Avvia:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\run.ps1
   ```
4. APK di release (per installarlo altrove):
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\build-apk.ps1
   ```

---

## Prova end-to-end (servono 2 account)

1. **Utente A**: registrati → scegli il nome → *Aggiungi contatto* → copia/condividi il codice `BRU-XXXX-XXXX`.
2. **Utente B** (secondo telefono o secondo account): registrati → *Aggiungi contatto* → inserisci o scansiona il codice di A.
3. Si crea la chat per entrambi. Provate:
   - messaggio di testo (protetto → "Tocca per aprire");
   - foto in-app (non entra in galleria);
   - apertura controllata + conto alla rovescia + blocco screenshot;
   - *Impostazioni protezione* (aperture / durata / revoca tutto);
   - *Statistiche* (aperture in tempo reale, lato mittente).

---

## Troubleshooting

| Sintomo | Causa / rimedio |
|---|---|
| Schermata "Configurazione Supabase mancante" | `bruma.env.json` assente o vuoto. |
| Errori *permission denied* / RLS | Lo script SQL non è stato eseguito per intero. Rilancialo. |
| Il login non entra dopo la registrazione | "Confirm email" attivo su Supabase: verifica l'email o disattivalo per i test. |
| Realtime non aggiorna in tempo reale | Controlla che la publication includa `messages`/`open_events` (lo script lo fa). |
| Fotocamera nera | Usa un **dispositivo fisico** (l'emulatore ha camera simulata). |
| `flutter` non riconosciuto | Riavvia il terminale dopo `setup-toolchain.ps1`, oppure usa gli script in `scripts\`. |

Per i dettagli su architettura, sicurezza e limiti noti vedi [`README.md`](README.md).
