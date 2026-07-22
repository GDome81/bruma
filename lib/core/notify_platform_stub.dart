// Implementazione no-op per mobile/desktop: le notifiche lì passano da
// flutter_local_notifications.
Future<void> requestWebPermission() async {}

bool webNotificationsGranted() => false;

Future<Map<String, String>> subscribeWebPush(String vapidPublicKey) async =>
    throw UnsupportedError('Web Push disponibile solo sul web');

Future<void> showWebNotification(String title, String body) async {}
