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

  // --- Notifiche: suono, vibrazione, chat silenziate ----------------------
  static bool get notifSound => _p?.getBool('notif_sound') ?? true;
  static Future<void> setNotifSound(bool v) async =>
      _p?.setBool('notif_sound', v);

  static bool get notifVibrate => _p?.getBool('notif_vibrate') ?? true;
  static Future<void> setNotifVibrate(bool v) async =>
      _p?.setBool('notif_vibrate', v);

  static List<String> get mutedChats =>
      _p?.getStringList('muted_chats') ?? const [];

  static bool isChatMuted(String conversationId) =>
      mutedChats.contains(conversationId);

  static Future<void> setChatMuted(String conversationId, bool muted) async {
    final set = mutedChats.toSet();
    if (muted) {
      set.add(conversationId);
    } else {
      set.remove(conversationId);
    }
    await _p?.setStringList('muted_chats', set.toList());
  }

  // --- Tutorial primo accesso (mostrato una volta) ------------------------
  static bool get tutorialSeen => _p?.getBool('tutorial_seen') ?? false;
  static Future<void> setTutorialSeen(bool v) async =>
      _p?.setBool('tutorial_seen', v);

  // --- Ultimo messaggio letto per conversazione ----------------------------
  static DateTime? lastRead(String conversationId) {
    final s = _p?.getString('lastread_$conversationId');
    return s == null ? null : DateTime.tryParse(s);
  }

  static Future<void> setLastRead(String conversationId, DateTime t) async =>
      _p?.setString('lastread_$conversationId', t.toIso8601String());
}
