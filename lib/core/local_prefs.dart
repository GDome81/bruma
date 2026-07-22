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

  // --- Modalità panic (mostra il decoy finché non si sblocca) --------------
  static bool get panic => _p?.getBool('panic_mode') ?? false;
  static Future<void> setPanic(bool v) async => _p?.setBool('panic_mode', v);

  // --- Tipo di maschera (calculator | moonPhase | gallery) -----------------
  static String get decoyType => _p?.getString('decoy_type') ?? 'calculator';
  static Future<void> setDecoyType(String v) async =>
      _p?.setString('decoy_type', v);

  // --- Blocco app con PIN (+ biometria su APK) -----------------------------
  static bool get appLockEnabled => _p?.getBool('app_lock_enabled') ?? false;
  static Future<void> setAppLockEnabled(bool v) async =>
      _p?.setBool('app_lock_enabled', v);

  static bool get lockUseBiometric => _p?.getBool('lock_biometric') ?? false;
  static Future<void> setLockUseBiometric(bool v) async =>
      _p?.setBool('lock_biometric', v);

  static String? get pinSalt => _p?.getString('pin_salt');
  static String? get pinHash => _p?.getString('pin_hash');
  static Future<void> setPin(String salt, String hash) async {
    await _p?.setString('pin_salt', salt);
    await _p?.setString('pin_hash', hash);
  }

  static Future<void> clearPin() async {
    await _p?.remove('pin_salt');
    await _p?.remove('pin_hash');
    await _p?.setBool('app_lock_enabled', false);
  }

  // --- Ultimo messaggio letto per conversazione ----------------------------
  static DateTime? lastRead(String conversationId) {
    final s = _p?.getString('lastread_$conversationId');
    return s == null ? null : DateTime.tryParse(s);
  }

  static Future<void> setLastRead(String conversationId, DateTime t) async =>
      _p?.setString('lastread_$conversationId', t.toIso8601String());
}
