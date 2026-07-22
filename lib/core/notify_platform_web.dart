// Notifiche del browser. Su DESKTOP funziona il costruttore `Notification`;
// su MOBILE (Android Chrome) quel costruttore è vietato ("Illegal
// constructor"): bisogna usare il Service Worker
// (registration.showNotification). Proviamo prima il SW e poi il fallback.
//
// Restano visibili solo mentre la scheda/PWA è viva; per notifiche ad app
// completamente chiusa serve la Push API/FCM (fase 2).
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
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
  final options = <String, dynamic>{
    'body': body,
    'icon': 'icons/Icon-192.png',
    'badge': 'icons/Icon-192.png',
    'tag': 'bruma',
    'renotify': true,
  };
  // 1) Service Worker (indispensabile su Android Chrome).
  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw != null) {
      final reg = await sw.ready;
      await reg.showNotification(title, options);
      return;
    }
  } catch (_) {
    // cade nel fallback qui sotto
  }
  // 2) Fallback desktop: costruttore Notification.
  try {
    html.Notification(title, body: body, icon: 'icons/Icon-192.png');
  } catch (_) {}
}
