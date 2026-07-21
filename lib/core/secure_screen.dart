import 'package:flutter/services.dart';

/// Attiva/disattiva FLAG_SECURE sulla finestra Android (blocco screenshot e
/// registrazione schermo, best-effort). Implementato nativamente in
/// MainActivity.kt tramite MethodChannel — nessuna dipendenza esterna.
class SecureScreen {
  static const _channel = MethodChannel('bruma/secure_screen');

  static Future<void> on() async {
    try {
      await _channel.invokeMethod<void>('secureOn');
    } catch (_) {
      // best-effort: su piattaforme non supportate non fa nulla
    }
  }

  static Future<void> off() async {
    try {
      await _channel.invokeMethod<void>('secureOff');
    } catch (_) {}
  }
}

/// FLAG_SECURE con conteggio dei riferimenti: resta attivo finché almeno un
/// contenuto protetto è a schermo (anteprima in chat e/o fullscreen).
class SecureScreenGuard {
  static int _count = 0;

  static void acquire() {
    _count++;
    if (_count == 1) SecureScreen.on();
  }

  static void release() {
    if (_count == 0) return;
    _count--;
    if (_count == 0) SecureScreen.off();
  }
}

