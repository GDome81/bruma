import 'package:shared_preferences/shared_preferences.dart';

/// Preferenze locali NON sensibili (ultimo messaggio letto per chat, blocco
/// biometrico). Nessun contenuto in chiaro qui.
class LocalPrefs {
  static SharedPreferences? _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  // --- Blocco biometrico ---------------------------------------------------
  static bool get biometricEnabled => _p?.getBool('biometric_enabled') ?? false;
  static Future<void> setBiometricEnabled(bool v) async =>
      _p?.setBool('biometric_enabled', v);

  // --- Ultimo messaggio letto per conversazione ----------------------------
  static DateTime? lastRead(String conversationId) {
    final s = _p?.getString('lastread_$conversationId');
    return s == null ? null : DateTime.tryParse(s);
  }

  static Future<void> setLastRead(String conversationId, DateTime t) async =>
      _p?.setString('lastread_$conversationId', t.toIso8601String());
}
