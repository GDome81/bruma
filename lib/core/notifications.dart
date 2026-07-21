import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifiche locali (fase 1). Contenuto GENERICO: nessun mittente né testo,
/// per non esporre metadati sensibili al sistema notifiche.
///
/// Limite noto: mostrate solo mentre il processo dell'app è vivo
/// (foreground/background non ucciso). Le notifiche ad app chiusa arriveranno
/// con FCM (fase 2).
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
    if (kIsWeb) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> showGenericMessage() async {
    if (kIsWeb || !_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'bruma_messages',
        'Messaggi',
        channelDescription: 'Nuovi messaggi in Bruma',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(0, 'Bruma', 'Nuovo messaggio', details);
  }
}
