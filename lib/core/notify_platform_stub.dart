// Implementazione no-op per mobile/desktop: le notifiche lì passano da
// flutter_local_notifications.
Future<void> requestWebPermission() async {}

bool webNotificationsGranted() => false;

void showWebNotification(String title, String body) {}
