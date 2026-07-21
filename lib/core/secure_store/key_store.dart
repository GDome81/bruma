import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sodium_libs/sodium_libs.dart';

import '../crypto/crypto_service.dart';

/// Custodia della coppia di chiavi di identita' dell'utente sul dispositivo.
///
/// La chiave PRIVATA non lascia mai il telefono: e' salvata in
/// `flutter_secure_storage` (Keystore Android / EncryptedSharedPreferences).
/// Le chiavi sono indicizzate per user id, cosi' account diversi sullo stesso
/// dispositivo restano separati.
class KeyStore {
  KeyStore(this._crypto);

  final CryptoService _crypto;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _skKey(String uid) => 'bruma_sk_$uid';
  String _pkKey(String uid) => 'bruma_pk_$uid';

  /// Salva la coppia di chiavi per [uid].
  Future<void> save(String uid, KeyPair keyPair) async {
    final sk = keyPair.secretKey.extractBytes();
    try {
      await _storage.write(key: _skKey(uid), value: base64Encode(sk));
      await _storage.write(
        key: _pkKey(uid),
        value: base64Encode(keyPair.publicKey),
      );
    } finally {
      for (var i = 0; i < sk.length; i++) {
        sk[i] = 0;
      }
    }
  }

  /// Carica la coppia di chiavi per [uid], oppure null se assente.
  Future<KeyPair?> load(String uid) async {
    final skB64 = await _storage.read(key: _skKey(uid));
    final pkB64 = await _storage.read(key: _pkKey(uid));
    if (skB64 == null || pkB64 == null) return null;
    final sk = base64Decode(skB64);
    try {
      // keyPairFromRaw copia sk in una SecureKey: azzeriamo la copia sull'heap.
      return _crypto.keyPairFromRaw(base64Decode(pkB64), sk);
    } finally {
      for (var i = 0; i < sk.length; i++) {
        sk[i] = 0;
      }
    }
  }

  Future<bool> exists(String uid) async {
    final sk = await _storage.read(key: _skKey(uid));
    return sk != null;
  }

  Future<void> delete(String uid) async {
    await _storage.delete(key: _skKey(uid));
    await _storage.delete(key: _pkKey(uid));
  }
}
