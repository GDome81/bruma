// Notifiche web (browser Notification API). Su mobile/desktop è tutto no-op:
// lì usiamo flutter_local_notifications. Selezione per piattaforma via import
// condizionato (come temp_file).
export 'notify_platform_stub.dart'
    if (dart.library.html) 'notify_platform_web.dart';
