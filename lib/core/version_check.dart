import 'dart:async';

import 'package:flutter/foundation.dart';

import 'config.dart';
import 'version_platform.dart';

/// Rende l'aggiornamento della PWA immediato e robusto, senza dover "killare"
/// l'app sperando che il service worker si accorga della nuova versione.
///
/// Come funziona: la CI scrive `version.json` col SHA del commit; l'app in
/// esecuzione conosce il proprio [AppConfig.buildTag] (iniettato allo stesso
/// modo). Periodicamente (all'avvio, al rientro in primo piano e ogni pochi
/// minuti) confronta i due valori letti SENZA cache: se differiscono, mostra
/// il banner "Aggiorna". Sul web soltanto (l'APK si aggiorna diversamente).
class VersionCheck {
  VersionCheck._();

  /// Diventa true quando il server espone una versione diversa da quella in
  /// esecuzione. La UI mostra un banner con "Aggiorna".
  static final ValueNotifier<bool> updateAvailable = ValueNotifier(false);

  static Timer? _timer;

  /// Avvia il polling (idempotente). No-op fuori dal web o in build locale.
  static void start() {
    if (!kIsWeb) return;
    unawaited(checkNow());
    _timer ??= Timer.periodic(
        const Duration(minutes: 5), (_) => unawaited(checkNow()));
  }

  /// Controllo immediato (usato anche al ritorno in primo piano).
  static Future<void> checkNow() async {
    if (!kIsWeb) return;
    // In sviluppo il buildTag è "dev": niente confronto, evita falsi positivi.
    if (AppConfig.buildTag == 'dev') return;
    final live = await platformFetchLiveBuild('version.json');
    if (live == null || live.isEmpty) return;
    if (live != AppConfig.buildTag) {
      updateAvailable.value = true;
    }
  }

  /// Ricarica per prendere la nuova versione.
  static Future<void> reload() => platformReloadApp();
}
