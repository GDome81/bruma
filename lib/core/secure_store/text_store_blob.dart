import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sodium_libs/sodium_libs.dart';

import '../crypto/crypto_service.dart';

/// Variante WEB dell'archivio testi: `sqflite` non è disponibile nella PWA,
/// quindi qui si resta su un unico blob cifrato in SharedPreferences.
///
/// Limite noto (accettato): ogni scrittura ri-serializza e ri-cifra tutto, e le
/// voci sono limitate a [maxEntries]. Sull'APK invece si usa SQLite con
/// scritture incrementali e senza tetto (vedi text_store_db.dart).
class TextStore {
  TextStore(this._crypto);

  final CryptoService _crypto;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyName = 'bruma_textcache_key';
  static String _blobKey(String uid) => 'bruma_textcache_$uid';

  /// Tetto di voci: il blob va riscritto per intero, quindi non può crescere
  /// senza limite.
  static const maxEntries = 4000;

  SecureKey? _key;

  /// Copia in memoria per poter fare `put` incrementali verso l'esterno pur
  /// riscrivendo tutto il blob sotto.
  final Map<String, String> _all = {};
  bool _loaded = false;

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

  Future<Map<String, String>> load(String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      final b64 = p.getString(_blobKey(uid));
      _all.clear();
      _loaded = true;
      if (b64 == null || b64.isEmpty) return {};
      final key = await _aeadKey();
      final plain = _crypto.decryptContent(base64Decode(b64), key);
      final map = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      for (final e in map.entries) {
        if (e.value is String) _all[e.key] = e.value as String;
      }
      return Map<String, String>.from(_all);
    } catch (_) {
      return {};
    }
  }

  Future<bool> put(String uid, Map<String, String> entries) async {
    if (entries.isEmpty) return true;
    if (!_loaded) await load(uid);
    _all.addAll(entries);
    return _write(uid);
  }

  Future<bool> removeIds(String uid, Iterable<String> messageIds) async {
    if (!_loaded) await load(uid);
    var changed = false;
    for (final id in messageIds) {
      if (_all.remove(id) != null) changed = true;
    }
    if (!changed) return true;
    return _write(uid);
  }

  /// Qui il "blob legacy" È l'archivio corrente: niente da purgare.
  /// Esiste solo perché l'API deve combaciare con quella su SQLite.
  Future<void> purgeLegacyBlob(String uid) async {}

  Future<bool> _write(String uid) async {
    try {
      var data = _all;
      if (data.length > maxEntries) {
        final keys = data.keys.toList();
        final keep = keys.sublist(keys.length - maxEntries);
        data = {for (final k in keep) k: data[k]!};
        _all
          ..clear()
          ..addAll(data);
      }
      final key = await _aeadKey();
      final blob = _crypto.encryptWithKey(
          Uint8List.fromList(utf8.encode(jsonEncode(data))), key);
      final p = await SharedPreferences.getInstance();
      await p.setString(_blobKey(uid), base64Encode(blob));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear(String uid) async {
    try {
      _all.clear();
      final p = await SharedPreferences.getInstance();
      await p.remove(_blobKey(uid));
    } catch (_) {}
  }
}
