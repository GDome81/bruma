// Notifiche del browser.
//  * DESKTOP: il costruttore `Notification` funziona ed è affidabile.
//  * MOBILE (Android Chrome): quel costruttore è vietato ("Illegal
//    constructor") → si usa il Service Worker (registration.showNotification).
// Proviamo prima il costruttore (se lancia, siamo su mobile) e poi il SW, con
// un timeout su `ready` per non restare MAI appesi quando non c'è un SW attivo
// (es. `flutter run` in locale o una semplice scheda del browser).
//
// Restano visibili solo mentre la scheda/PWA è viva; per notifiche ad app
// completamente chiusa serve la Push API/FCM (fase 2).
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;

Future<void> requestWebPermission() async {
  try {
    if (html.Notification.supported &&
        html.Notification.permission != 'granted' &&
        html.Notification.permission != 'denied') {
      await html.Notification.requestPermission();
    }
  } catch (_) {}
}

bool webNotificationsGranted() {
  try {
    return html.Notification.supported &&
        html.Notification.permission == 'granted';
  } catch (_) {
    return false;
  }
}

Future<void> showWebNotification(String title, String body) async {
  if (!webNotificationsGranted()) return;

  // 1) Costruttore diretto (desktop). Su Android lancia → cadiamo nel SW.
  try {
    html.Notification(title, body: body, icon: 'icons/Icon-192.png');
    return;
  } catch (_) {
    // continua col Service Worker
  }

  // 2) Service Worker (necessario su Android Chrome).
  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw == null) return;
    final reg = await sw.ready.timeout(const Duration(seconds: 3));
    await reg.showNotification(title, <String, dynamic>{
      'body': body,
      'icon': 'icons/Icon-192.png',
      'badge': 'icons/Icon-192.png',
      'tag': 'bruma',
      'renotify': true,
    });
  } catch (_) {}
}
