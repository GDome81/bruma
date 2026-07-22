import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notify_platform.dart';

/// Notifiche locali. Contenuto ANONIMO: solo una luna 🌙, nessun mittente,
/// testo o nome di chat, per non esporre nulla al sistema di notifiche.
///
/// - Mobile/desktop: flutter_local_notifications (mentre il processo è vivo).
/// - Web/PWA: Notification API del browser (mentre la scheda/PWA è viva, anche
///   in background non sospeso).
///
/// Notifiche ad app COMPLETAMENTE chiusa → serviranno FCM/Push (fase 2).
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
    );
    _ready = true;
  }

  static Future<void> requestPermission() async {
    if (kIsWeb) {
      await requestWebPermission();
      return;
    }
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> showGenericMessage() async {
    if (kIsWeb) {
      // Titolo/corpo volutamente anonimi: solo la luna.
      showWebNotification('Bruma', '🌙');
      return;
    }
    if (!_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'bruma_messages',
        'Aggiornamenti',
        channelDescription: 'Notifiche anonime di Bruma',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    // Nessun nome né testo: solo la luna.
    await _plugin.show(0, 'Bruma', '🌙', details);
  }
}
