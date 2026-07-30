import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Note personali sui messaggi salvati nei preferiti. Solo locali su questo
/// dispositivo e CIFRATE a riposo (Keystore Android / EncryptedSharedPreferences),
/// perché una nota può descrivere un contenuto nascosto ("il tramonto").
class FavoriteNotes {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _k(String messageId) => 'bruma_favnote_$messageId';

  static Future<String?> get(String messageId) =>
      _storage.read(key: _k(messageId));

  /// Legge le note di più messaggi con UN SOLO accesso allo storage cifrato.
  /// N letture separate sul canale nativo erano la causa della lentezza della
  /// lista preferiti.
  static Future<Map<String, String>> getMany(Iterable<String> messageIds) async {
    final all = await _storage.readAll();
    final out = <String, String>{};
    for (final id in messageIds) {
      final v = all[_k(id)];
      if (v != null && v.isNotEmpty) out[id] = v;
    }
    return out;
  }

  static Future<void> set(String messageId, String? note) async {
    final v = note?.trim();
    if (v == null || v.isEmpty) {
      await _storage.delete(key: _k(messageId));
    } else {
      await _storage.write(key: _k(messageId), value: v);
    }
  }
}
