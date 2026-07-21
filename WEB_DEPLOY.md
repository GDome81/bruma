# Bruma Web — deploy + PWA

La versione web di Bruma è un insieme di **file statici** (in `build/web`) ed è
**già una PWA installabile** (manifest + service worker generati da Flutter).

## 1. Compila

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-web.ps1
```

Output: `build/web`. **Pubblica quella cartella** su un host statico in **HTTPS**
(obbligatorio per fotocamera e PWA; `localhost` è l'unica eccezione).

> La **anon key** finisce nel bundle: è normale e sicuro — è pubblica per design,
> i dati sono protetti dalla Row Level Security di Supabase.

## 2. Dove pubblicare (opzioni gratuite, con HTTPS e SPA)

| Host | Come | Note |
|---|---|---|
| **Cloudflare Pages** | Carica `build/web` (drag&drop) o collega la repo; build command vuoto, output `build/web` | Veloce, HTTPS automatico |
| **Netlify** | Trascina `build/web` su app.netlify.com/drop | Zero config |
| **Firebase Hosting** | `firebase init hosting` (public = `build/web`, SPA = yes) → `firebase deploy` | Comodo se poi usi Firebase per le push FCM |
| **GitHub Pages** | Pubblica `build/web` sul branch `gh-pages` | Serve sottocartella → ricompila con `-BaseHref /nome-repo/` |
| **Vercel** | Import repo, output dir `build/web` | HTTPS automatico |

Per un host servito in **sottocartella** (es. GitHub Pages di progetto):
```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-web.ps1 -BaseHref /nome-repo/
```

## 3. Configurazione Supabase per il dominio pubblico
- **Authentication → URL Configuration → Site URL**: metti il dominio pubblicato
  (es. `https://bruma.pages.dev`) e aggiungilo ai **Redirect URLs**, se usi la
  conferma email.
- CORS: l'API Supabase con anon key accetta qualsiasi origine — nessuna azione.

## 4. Installare come app (PWA)
- **Android/Chrome**: menu ⋮ → "Installa app" / "Aggiungi a schermata Home".
- **Desktop Chrome/Edge**: icona "installa" nella barra indirizzi.
- **iOS/Safari**: Condividi → "Aggiungi a Home". (Su iOS le PWA hanno limiti noti.)

## Limiti della versione web/PWA (rispetto all'app Android)
- **Blocco biometrico**: non disponibile su web (bypassato).
- **Notifiche**: le notifiche locali non funzionano su web; servirà FCM Web (fase 2).
- **Chiave privata**: su web è custodita nel `localStorage`/IndexedDB del browser,
  meno sicuro del Keystore Android — evita browser condivisi.
- **Fotocamera**: usa la webcam (meno affidabile del mobile); l'allega-da-galleria
  usa il file picker del browser.
- **Icone PWA**: sono ancora quelle di default di Flutter — sostituibili in
  `web/icons/` con icone Bruma quando vuoi.
