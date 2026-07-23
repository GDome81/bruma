// Service worker DEDICATO alle Web Push di Bruma (separato da quello di
// caching generato da Flutter). Registrato con scope "push/" così non
// sostituisce flutter_service_worker.js.
//
// Riceve il push dal server (Edge Function `send-push`) e mostra una notifica
// ANONIMA: solo 🌙, nessun nome/contenuto.

self.addEventListener('push', function (event) {
  let title = 'Bruma';
  let body = '🌙';
  let silent = false;
  let vibrate = true;
  try {
    if (event.data) {
      const data = event.data.json();
      if (data && data.title) title = data.title;
      if (data && data.body) body = data.body;
      if (data && data.silent === true) silent = true;
      if (data && data.vibrate === false) vibrate = false;
    }
  } catch (e) {
    // payload non-JSON o vuoto: restiamo sul generico
  }
  const opts = {
    body: body,
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    tag: 'bruma',
    renotify: true,
    silent: silent,
    vibrate: silent || !vibrate ? [] : [200, 100, 200],
  };
  event.waitUntil(self.registration.showNotification(title, opts));
});

// Al tocco della notifica: porta in primo piano la finestra di Bruma (o la apre).
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  // URL dell'app = cartella del service worker (`.../bruma/`). Attenzione:
  // '../' risolveva alla RADICE del dominio (fuori scope) → apriva il browser
  // invece della PWA installata. './' resta dentro /bruma/.
  const appUrl = new URL('./', self.location.href).href;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
      // Riporta in primo piano una finestra dell'app già aperta (dentro scope).
      for (const client of list) {
        if (client.url && client.url.indexOf(appUrl) === 0 && 'focus' in client) {
          return client.focus();
        }
      }
      // Altrimenti apri l'app: con l'URL dentro scope Chrome apre la PWA
      // installata (standalone), non una scheda del browser.
      if (self.clients.openWindow) return self.clients.openWindow(appUrl);
    })
  );
});
