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
/// {endpoint, p256dh, auth} da salvare sul server. LANCIA un'eccezione con un
/// messaggio specifico a ogni possibile punto di fallimento (per diagnostica).
Future<Map<String, String>> subscribeWebPush(String vapidPublicKey) async {
  if (!html.Notification.supported) {
    throw Exception('Notifiche non supportate dal browser');
  }
  final perm = html.Notification.permission;
  if (perm != 'granted') {
    throw Exception('permesso = ${perm ?? "sconosciuto"}');
  }
  final sw = html.window.navigator.serviceWorker;
  if (sw == null) throw Exception('serviceWorker non disponibile');

  // SW dedicato al push, scope "push/" per non sostituire quello di Flutter.
  final html.ServiceWorkerRegistration reg;
  try {
    reg = await sw.register('push-sw.js', {'scope': 'push/'});
  } catch (e) {
    throw Exception('registrazione SW fallita: $e');
  }

  // Attendi che il worker sia attivo prima di sottoscrivere (max ~5s).
  for (var i = 0; i < 50 && reg.active == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final pm = reg.pushManager;
  if (pm == null) throw Exception('pushManager non disponibile');

  final html.PushSubscription sub;
  try {
    sub = await pm.subscribe({
      'userVisibleOnly': true,
      'applicationServerKey': _vapidKeyToBytes(vapidPublicKey),
    });
  } catch (e) {
    throw Exception('subscribe: $e');
  }

  final endpoint = sub.endpoint;
  final p256dh = _keyToBase64Url(sub.getKey('p256dh'));
  final auth = _keyToBase64Url(sub.getKey('auth'));
  if (endpoint == null || p256dh == null || auth == null) {
    throw Exception('chiavi subscription mancanti');
  }
  return {'endpoint': endpoint, 'p256dh': p256dh, 'auth': auth};
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
