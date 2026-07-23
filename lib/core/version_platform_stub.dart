// Controllo versione: no-op fuori dal web (l'APK si aggiorna dallo store /
// installando un nuovo pacchetto, non serve il polling di version.json).

Future<String?> platformFetchLiveBuild(String path) async => null;

Future<void> platformReloadApp() async {}
