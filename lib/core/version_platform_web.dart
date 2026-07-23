// Controllo versione sul web: legge `version.json` (scritto dalla CI col SHA
// del commit) SENZA cache e ricarica la pagina quando l'utente lo chiede.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

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

/// Ricarica l'app per prendere la nuova versione. Prima chiede al browser di
/// aggiornare i service worker registrati (best-effort: NON li deregistra, per
/// non toccare quello delle push), poi ricarica.
Future<void> platformReloadApp() async {
  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw != null) {
      final regs = await sw.getRegistrations();
      for (final r in regs) {
        try {
          await r.update();
        } catch (_) {}
      }
    }
  } catch (_) {}
  html.window.location.reload();
}
