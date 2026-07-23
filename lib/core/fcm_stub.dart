// Nessun FCM fuori da Android (web/desktop): no-op.

Future<void> initFcm() async {}

/// Chiede il permesso notifiche e ritorna il token FCM (null se non disponibile).
Future<String?> requestAndGetFcmToken() async => null;

/// Token FCM corrente senza chiedere permessi (null se non disponibile).
Future<String?> currentFcmToken() async => null;

/// Stream dei refresh del token.
Stream<String> fcmTokenRefresh() => const Stream.empty();
