import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs.dart';

/// Risultato della cifratura di un contenuto: il blob da salvare/caricare
/// (nonce anteposto al ciphertext) + la chiave simmetrica monouso `K`.
///
/// `key` e' una [SecureKey] (memoria protetta): va sempre `dispose()` dopo
/// l'uso — di norma dopo averla incapsulata (wrap) per il destinatario.
class EncryptedContent {
  EncryptedContent(this.blob, this.key);
  final Uint8List blob; // nonce || ciphertext
  final SecureKey key; // K (XChaCha20-Poly1305)
}

/// Identità importata: coppia di chiavi + tag dell'account d'origine (vuoto se
/// l'export non lo conteneva — formato vecchio).
class ImportedIdentity {
  ImportedIdentity(this.keyPair, this.originUid);
  final KeyPair keyPair;
  final String originUid;
}

/// Errore d'import con messaggio UNICO: dati non validi, password errata o
/// identità legata a un ALTRO account danno tutti lo STESSO messaggio (non si
/// rivela la causa).
class IdentityException implements Exception {
  const IdentityException(
      [this.message = 'Identità non valida o password errata.']);
  final String message;
  @override
  String toString() => message;
}

/// Wrapper attorno a libsodium con lo schema crittografico di Bruma.
///
/// Identita': coppia di chiavi X25519 (crypto_box).
/// Key-wrapping: sealed box (crypto_box_seal) — solo la chiave privata del
///   destinatario puo' aprire la `K` incapsulata.
/// Contenuti: XChaCha20-Poly1305 IETF con chiave `K` monouso.
class CryptoService {
  CryptoService(this._sodium);

  final Sodium _sodium;

  Sodium get sodium => _sodium;

  // --- Identita' (X25519) --------------------------------------------------

  /// Genera una nuova coppia di chiavi di identita'.
  KeyPair generateIdentityKeyPair() => _sodium.crypto.box.keyPair();

  /// Ricostruisce una [KeyPair] a partire dai byte serializzati.
  KeyPair keyPairFromRaw(Uint8List publicKey, Uint8List secretKey) => KeyPair(
        publicKey: publicKey,
        secretKey: SecureKey.fromList(_sodium, secretKey),
      );

  String encodePublicKey(Uint8List publicKey) => base64Encode(publicKey);
  Uint8List decodePublicKey(String b64) => base64Decode(b64);

  /// Impronta breve e leggibile di una chiave pubblica, per confrontare a
  /// occhio se due dispositivi hanno la STESSA identità (es. "A1B2 C3D4 E5F6
  /// 7890"). Non è segreta.
  String fingerprint(Uint8List publicKey) {
    // BLAKE2b (genericHash) ha un minimo di 16 byte in output: usarne meno
    // lancia un'eccezione. Prendo i primi 8 byte del digest per la stringa.
    final full = _sodium.crypto.genericHash(message: publicKey, outLen: 16);
    final h = full.take(8);
    final hex = h
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    final groups = <String>[];
    for (var i = 0; i < hex.length; i += 4) {
      groups.add(hex.substring(i, i + 4));
    }
    return groups.join(' ');
  }

  // --- Cifratura dei contenuti (K monouso) --------------------------------

  /// Cifra [plaintext] con una nuova chiave simmetrica monouso.
  EncryptedContent encryptContent(Uint8List plaintext) {
    final aead = _sodium.crypto.aeadXChaCha20Poly1305IETF;
    final key = aead.keygen();
    final nonce = _sodium.randombytes.buf(aead.nonceBytes);
    final cipher = aead.encrypt(message: plaintext, nonce: nonce, key: key);
    final blob = Uint8List(nonce.length + cipher.length)
      ..setAll(0, nonce)
      ..setAll(nonce.length, cipher);
    return EncryptedContent(blob, key);
  }

  /// Cifra [plaintext] con una chiave GIÀ esistente (stesso formato blob:
  /// `nonce || ciphertext`). Usata per la cache locale cifrata a riposo, dove
  /// la chiave vive nel Keystore e viene riusata per tutte le scritture.
  Uint8List encryptWithKey(Uint8List plaintext, SecureKey key) {
    final aead = _sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = _sodium.randombytes.buf(aead.nonceBytes);
    final cipher = aead.encrypt(message: plaintext, nonce: nonce, key: key);
    return Uint8List(nonce.length + cipher.length)
      ..setAll(0, nonce)
      ..setAll(nonce.length, cipher);
  }

  /// Hash CON CHIAVE (BLAKE2b keyed), base64. Serve a rendere opachi gli
  /// identificatori usati come chiavi di riga nel database locale: senza la
  /// chiave non si risale né all'id del messaggio né all'account, quindi dal
  /// file su disco non si legge nulla oltre al numero di righe.
  /// Deterministico: lo stesso input dà sempre la stessa chiave di riga.
  String keyedHashB64(String data, SecureKey key) {
    final out = _sodium.crypto.genericHash(
      message: Uint8List.fromList(utf8.encode(data)),
      key: key,
      outLen: 32,
    );
    return base64Encode(out);
  }

  /// Nuova chiave simmetrica (cache locale).
  SecureKey newSymmetricKey() =>
      _sodium.crypto.aeadXChaCha20Poly1305IETF.keygen();

  /// Ricostruisce una chiave simmetrica dai byte salvati nel Keystore.
  SecureKey symmetricKeyFromBytes(Uint8List raw) =>
      SecureKey.fromList(_sodium, raw);

  /// Decifra un blob `nonce || ciphertext` con la chiave [key].
  Uint8List decryptContent(Uint8List blob, SecureKey key) {
    final aead = _sodium.crypto.aeadXChaCha20Poly1305IETF;
    final n = aead.nonceBytes;
    final nonce = Uint8List.sublistView(blob, 0, n);
    final cipher = Uint8List.sublistView(blob, n);
    return aead.decrypt(cipherText: cipher, nonce: nonce, key: key);
  }

  // --- Key wrapping (sealed box) ------------------------------------------

  /// Incapsula la chiave [key] per il destinatario con chiave pubblica
  /// [recipientPublicKey]. Il risultato (base64) e' `message_access.wrapped_key`.
  String wrapKey(SecureKey key, Uint8List recipientPublicKey) {
    final raw = key.extractBytes();
    try {
      final sealed = _sodium.crypto.box
          .seal(message: raw, publicKey: recipientPublicKey);
      return base64Encode(sealed);
    } finally {
      // Azzeramento best-effort della copia in memoria dart.
      for (var i = 0; i < raw.length; i++) {
        raw[i] = 0;
      }
    }
  }

  /// Apre una `wrapped_key` (base64) con la propria coppia di chiavi.
  /// Restituisce `K` come [SecureKey] (ricordarsi di `dispose()`).
  SecureKey unwrapKey(String wrappedKeyB64, KeyPair myKeyPair) {
    final sealed = base64Decode(wrappedKeyB64);
    final raw = _sodium.crypto.box.sealOpen(
      cipherText: sealed,
      publicKey: myKeyPair.publicKey,
      secretKey: myKeyPair.secretKey,
    );
    try {
      // SecureKey.fromList copia i byte in memoria protetta.
      return SecureKey.fromList(_sodium, raw);
    } finally {
      for (var i = 0; i < raw.length; i++) {
        raw[i] = 0;
      }
    }
  }

  // --- Esporta / importa identità (backup cifrato con password) -----------

  static const _exportPrefix = 'BRUMA1:';
  static const _kdfIterations = 100000;
  static const _saltBytes = 16;

  /// Deriva una chiave a 32 byte dalla password (BLAKE2b iterato + salt).
  SecureKey _deriveKey(String password, Uint8List salt) {
    final keyLen = _sodium.crypto.secretBox.keyBytes;
    var acc = Uint8List.fromList([...utf8.encode(password), ...salt]);
    for (var i = 0; i < _kdfIterations; i++) {
      acc = _sodium.crypto.genericHash(message: acc, outLen: keyLen);
    }
    final key = SecureKey.fromList(_sodium, acc);
    for (var i = 0; i < acc.length; i++) {
      acc[i] = 0;
    }
    return key;
  }

  /// Esporta la coppia di chiavi come stringa cifrata con [password]. [tag] è
  /// l'id dell'account d'origine, incorporato per rifiutare l'import su un
  /// account diverso.
  String exportIdentity(KeyPair kp, String password, {String tag = ''}) {
    final salt = _sodium.randombytes.buf(_saltBytes);
    final key = _deriveKey(password, salt);
    final sk = kp.secretKey.extractBytes();
    final tagBytes = utf8.encode(tag);
    final payload = Uint8List(kp.publicKey.length + sk.length + tagBytes.length)
      ..setAll(0, kp.publicKey)
      ..setAll(kp.publicKey.length, sk)
      ..setAll(kp.publicKey.length + sk.length, tagBytes);
    try {
      final nonce = _sodium.randombytes.buf(_sodium.crypto.secretBox.nonceBytes);
      final cipher =
          _sodium.crypto.secretBox.easy(message: payload, nonce: nonce, key: key);
      final blob = Uint8List(1 + salt.length + nonce.length + cipher.length);
      blob[0] = 1;
      blob.setAll(1, salt);
      blob.setAll(1 + salt.length, nonce);
      blob.setAll(1 + salt.length + nonce.length, cipher);
      return '$_exportPrefix${base64Encode(blob)}';
    } finally {
      key.dispose();
      for (var i = 0; i < payload.length; i++) {
        payload[i] = 0;
      }
      for (var i = 0; i < sk.length; i++) {
        sk[i] = 0;
      }
    }
  }

  /// Importa da una stringa esportata + [password]. Ritorna la coppia di chiavi
  /// e il tag dell'account d'origine. Su QUALSIASI fallimento (formato, password
  /// errata, ecc.) lancia sempre [IdentityException] con lo stesso messaggio.
  ImportedIdentity importIdentity(String data, String password) {
    SecureKey? key;
    try {
      var s = data.trim();
      if (s.startsWith(_exportPrefix)) s = s.substring(_exportPrefix.length);
      final blob = base64Decode(s);
      final nonceLen = _sodium.crypto.secretBox.nonceBytes;
      if (blob.isEmpty ||
          blob[0] != 1 ||
          blob.length < 1 + _saltBytes + nonceLen) {
        throw const IdentityException();
      }
      final salt = Uint8List.fromList(blob.sublist(1, 1 + _saltBytes));
      final nonce = Uint8List.fromList(
          blob.sublist(1 + _saltBytes, 1 + _saltBytes + nonceLen));
      final cipher = Uint8List.fromList(blob.sublist(1 + _saltBytes + nonceLen));
      key = _deriveKey(password, salt);
      final payload = _sodium.crypto.secretBox
          .openEasy(cipherText: cipher, nonce: nonce, key: key);
      try {
        if (payload.length < 64) throw const IdentityException();
        final pk = Uint8List.fromList(payload.sublist(0, 32));
        final sk = Uint8List.fromList(payload.sublist(32, 64));
        final tag = payload.length > 64
            ? utf8.decode(payload.sublist(64), allowMalformed: true)
            : '';
        final kp = keyPairFromRaw(pk, sk);
        for (var i = 0; i < sk.length; i++) {
          sk[i] = 0;
        }
        return ImportedIdentity(kp, tag);
      } finally {
        for (var i = 0; i < payload.length; i++) {
          payload[i] = 0;
        }
      }
    } catch (_) {
      // Messaggio unico: non distinguere dati non validi / password errata.
      throw const IdentityException();
    } finally {
      key?.dispose();
    }
  }

  // --- Hash del PIN di blocco (locale) ------------------------------------

  Uint8List randomSalt() => _sodium.randombytes.buf(16);

  /// Hash del PIN (BLAKE2b iterato + salt) → base64. Deterministico per salt.
  String hashPin(String pin, Uint8List salt) {
    var acc = Uint8List.fromList([...utf8.encode(pin), ...salt]);
    for (var i = 0; i < 20000; i++) {
      acc = _sodium.crypto.genericHash(message: acc, outLen: 32);
    }
    return base64Encode(acc);
  }

  // --- Base64 helpers per il testo ----------------------------------------

  String encodeBlob(Uint8List blob) => base64Encode(blob);
  Uint8List decodeBlob(String b64) => base64Decode(b64);
}
