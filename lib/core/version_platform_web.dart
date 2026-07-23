// Controllo versione sul web: legge `version.json` (scritto dalla CI col SHA
// del commit) SENZA cache e ricarica la pagina quando l'utente lo chiede.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

/// Scarica il build "live" dal server, bypassando la cache (query anti-cache +
/// header no-cache). Ritorna null se non disponibile o su errore.
Future<String?> platformFetchLiveBuild(String path) async {
  try {
    final bust = DateTime.now().millisecondsSinceEpoch;
    final resp = await html.HttpRequest.request(
      '$path?t=$bust',
      method: 'GET',
      requestHeaders: const {'cache-control': 'no-cache'},
    );
    final text = resp.responseText;
    if (text == null || text.isEmpty) return null;
    final data = jsonDecode(text);
    if (data is Map && data['build'] is String) {
      return data['build'] as String;
    }
  } catch (_) {}
  return null;
}

/// Ricarica l'app prendendo DAVVERO la nuova versione. Il solo reload non
/// basta: il vecchio service worker "cache-first" di Flutter continua a servire
/// la shell dalla cache, quindi il codice (col BUILD_TAG vecchio) resta invariato
/// e il banner non sparisce mai. Qui svuoto la Cache Storage e deregistro i
/// service worker (tranne quello delle push), poi ricarico.
Future<void> platformReloadApp() async {
  await _clearCaches();
  await _unregisterServiceWorkers();
  html.window.location.reload();
}

Future<void> _clearCaches() async {
  try {
    final caches = js_util.getProperty<Object?>(html.window, 'caches');
    if (caches == null) return;
    final keysJs =
        await js_util.promiseToFuture<Object?>(js_util.callMethod(caches, 'keys', const []));
    if (keysJs == null) return;
    final len = js_util.getProperty<int>(keysJs, 'length');
    for (var i = 0; i < len; i++) {
      final key = js_util.getProperty<Object?>(keysJs, i);
      await js_util.promiseToFuture<Object?>(js_util.callMethod(caches, 'delete', [key]));
    }
  } catch (_) {}
}

Future<void> _unregisterServiceWorkers() async {
  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw == null) return;
    final regs = await sw.getRegistrations();
    for (final r in regs) {
      try {
        // Conserva il service worker delle push (scope .../push/).
        if ((r.scope ?? '').endsWith('push/')) continue;
        await r.unregister();
      } catch (_) {}
    }
  } catch (_) {}
}
