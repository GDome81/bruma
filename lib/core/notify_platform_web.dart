// Notifiche del browser (Notification API). Funzionano mentre la PWA/scheda è
// viva (anche in background non sospeso). Per notifiche ad app CHIUSA serve un
// service worker + Push API/FCM (fase 2).
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

void showWebNotification(String title, String body) {
  try {
    if (webNotificationsGranted()) {
      html.Notification(title, body: body);
    }
  } catch (_) {}
}
