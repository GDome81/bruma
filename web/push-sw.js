// Service worker DEDICATO alle Web Push di Bruma (separato da quello di
// caching generato da Flutter). Registrato con scope "push/" così non
// sostituisce flutter_service_worker.js.
//
// Riceve il push dal server (Edge Function `send-push`) e mostra una notifica
// ANONIMA: solo 🌙, nessun nome/contenuto.

self.addEventListener('push', function (event) {
  let title = 'Bruma';
  let body = '🌙';
  try {
    if (event.data) {
      const data = event.data.json();
      if (data && data.title) title = data.title;
      if (data && data.body) body = data.body;
    }
  } catch (e) {
    // payload non-JSON o vuoto: restiamo sul generico
  }
  event.waitUntil(
    self.registration.showNotification(title, {
      body: body,
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      tag: 'bruma',
      renotify: true,
    })
  );
});

// Al tocco della notifica: porta in primo piano la finestra di Bruma (o la apre).
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
      for (const client of list) {
        if ('focus' in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow('../');
    })
  );
});
