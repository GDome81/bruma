// Selezione per piattaforma del controllo versione (come notify_platform).
export 'version_platform_stub.dart'
    if (dart.library.html) 'version_platform_web.dart';
