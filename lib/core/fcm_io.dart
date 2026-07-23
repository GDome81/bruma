import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// FCM solo su Android (l'APK). Le notifiche sono messaggi "notification":
// Android le mostra dal system tray anche ad app chiusa, senza bisogno di un
// handler in background. In foreground non le mostriamo (ci pensa il realtime
// in-app), così non ci sono doppioni.

bool _ready = false;

Future<void> initFcm() async {
  if (!Platform.isAndroid) return;
  try {
    await Firebase.initializeApp();
    _ready = true;
  } catch (_) {
    _ready = false; // google-services.json mancante o init fallito
  }
}

/// Chiede il permesso notifiche (Android 13+) e ritorna il token FCM.
Future<String?> requestAndGetFcmToken() async {
  if (!Platform.isAndroid || !_ready) return null;
  try {
    final m = FirebaseMessaging.instance;
    await m.requestPermission();
    return await m.getToken();
  } catch (_) {
    return null;
  }
}

/// Token corrente SENZA chiedere permessi (il token esiste anche prima del
/// permesso di visualizzazione; serve al server per indirizzare il push).
Future<String?> currentFcmToken() async {
  if (!Platform.isAndroid || !_ready) return null;
  try {
    return await FirebaseMessaging.instance.getToken();
  } catch (_) {
    return null;
  }
}

Stream<String> fcmTokenRefresh() {
  if (!Platform.isAndroid || !_ready) return const Stream.empty();
  return FirebaseMessaging.instance.onTokenRefresh;
}
