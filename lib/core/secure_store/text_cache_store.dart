import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sodium_libs/sodium_libs.dart';

import '../crypto/crypto_service.dart';

/// Cache PERSISTENTE dei testi già decifrati, CIFRATA A RIPOSO.
///
/// Perché: i testi vivevano solo in RAM, quindi a ogni riavvio l'app doveva
/// ri-chiedere al server la chiave di OGNI messaggio e ri-decifrarlo — un giro
/// di rete per messaggio. Era la causa principale dello scroll a scatti e della
/// ricerca lenta. Persistendoli, riaprire una chat è immediato.
///
/// Come: la chiave AEAD sta nello storage sicuro (Keystore Android /
/// EncryptedSharedPreferences), mentre il blob cifrato — che può essere di
/// diverse decine di KB — sta in SharedPreferences: scrivere blob grandi nello
/// storage sicuro a ogni messaggio sarebbe lento.
///
/// COMPROMESSO DI SICUREZZA (scelta esplicita): la cronologia dei testi ora
/// risiede sul dispositivo. È illeggibile senza la chiave nel Keystore, ma non
/// è più vero che "nessun testo tocca il disco". Le foto restano solo in RAM.
class TextCacheStore {
  TextCacheStore(this._crypto);

  final CryptoService _crypto;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyName = 'bruma_textcache_key';
  static String _blobKey(String uid) => 'bruma_textcache_$uid';

  /// Tetto di voci conservate (le più recenti): impedisce che il blob cresca
  /// senza limite su chat molto lunghe.
  static const maxEntries = 4000;

  SecureKey? _key;

  Future<SecureKey> _aeadKey() async {
    final cached = _key;
    if (cached != null) return cached;
    final existing = await _storage.read(key: _keyName);
    if (existing != null) {
      final k = _crypto.symmetricKeyFromBytes(base64Decode(existing));
      _key = k;
      return k;
    }
    final k = _crypto.newSymmetricKey();
    final raw = k.extractBytes();
    try {
      await _storage.write(key: _keyName, value: base64Encode(raw));
    } finally {
      for (var i = 0; i < raw.length; i++) {
        raw[i] = 0;
      }
    }
    _key = k;
    return k;
  }

  /// Testi persistiti per [uid]. Se il blob non è leggibile (chiave nuova,
  /// dati corrotti) riparte da vuoto: è solo una cache.
  Future<Map<String, String>> load(String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      final b64 = p.getString(_blobKey(uid));
      if (b64 == null || b64.isEmpty) return {};
      final key = await _aeadKey();
      final plain = _crypto.decryptContent(base64Decode(b64), key);
      final map = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          if (e.value is String) e.key: e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> save(String uid, Map<String, String> entries) async {
    try {
      var data = entries;
      if (data.length > maxEntries) {
        // Conserva le ultime inserite (Map di Dart mantiene l'ordine).
        final keys = data.keys.toList();
        final keep = keys.sublist(keys.length - maxEntries);
        data = {for (final k in keep) k: data[k]!};
      }
      final key = await _aeadKey();
      final blob = _crypto.encryptWithKey(
          Uint8List.fromList(utf8.encode(jsonEncode(data))), key);
      final p = await SharedPreferences.getInstance();
      await p.setString(_blobKey(uid), base64Encode(blob));
    } catch (_) {
      // Cache best-effort: un errore di scrittura non deve rompere la chat.
    }
  }

  /// Cancella la cache di [uid] (logout, cambio identità).
  Future<void> clear(String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_blobKey(uid));
    } catch (_) {}
  }
}
