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

  // --- Base64 helpers per il testo ----------------------------------------

  String encodeBlob(Uint8List blob) => base64Encode(blob);
  Uint8List decodeBlob(String b64) => base64Decode(b64);
}
