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
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

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

/// Registra un Web Push su questo dispositivo e ritorna
/// {endpoint, p256dh, auth} da salvare sul server, oppure null se non è
/// possibile (permesso negato, niente Push API, ecc.).
Future<Map<String, String>?> subscribeWebPush(String vapidPublicKey) async {
  try {
    if (!webNotificationsGranted()) return null;
    final sw = html.window.navigator.serviceWorker;
    if (sw == null) return null;

    // SW dedicato al push, con scope "push/" per non sostituire quello di
    // Flutter (caching), che vive su "./".
    final reg = await sw.register('push-sw.js', {'scope': 'push/'});

    // Attendi che il worker sia attivo prima di sottoscrivere (max ~3s).
    for (var i = 0; i < 30 && reg.active == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final pm = reg.pushManager;
    if (pm == null) return null;

    final sub = await pm.subscribe({
      'userVisibleOnly': true,
      'applicationServerKey': _vapidKeyToBytes(vapidPublicKey),
    });

    final endpoint = sub.endpoint;
    final p256dh = _keyToBase64Url(sub.getKey('p256dh'));
    final auth = _keyToBase64Url(sub.getKey('auth'));
    if (endpoint == null || p256dh == null || auth == null) return null;
    return {'endpoint': endpoint, 'p256dh': p256dh, 'auth': auth};
  } catch (_) {
    return null;
  }
}

Uint8List _vapidKeyToBytes(String base64Url) {
  final pad = '=' * ((4 - base64Url.length % 4) % 4);
  final normalized =
      (base64Url + pad).replaceAll('-', '+').replaceAll('_', '/');
  return base64Decode(normalized);
}

String? _keyToBase64Url(ByteBuffer? buffer) {
  if (buffer == null) return null;
  return base64Url.encode(buffer.asUint8List()).replaceAll('=', '');
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
