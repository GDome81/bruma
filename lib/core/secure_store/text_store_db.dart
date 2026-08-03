import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sodium_libs/sodium_libs.dart';
import 'package:sqflite/sqflite.dart';

import '../crypto/crypto_service.dart';

/// Archivio PERSISTENTE dei testi già decifrati, su SQLite, con righe OPACHE.
///
/// Perché SQLite e non più un unico blob: il blob andava ri-serializzato e
/// ri-cifrato per intero a ogni salvataggio (a 10.000 messaggi oltre un MB per
/// scrittura, sul thread della UI) ed era limitato a 4.000 voci — superate le
/// quali i messaggi più vecchi sparivano dalla ricerca senza avvisare. Qui le
/// scritture sono incrementali (una riga per messaggio) e non c'è tetto.
///
/// Cosa si vede sul disco: NIENTE, a parte il numero di righe.
///  * `u` = hash con chiave dell'uid  → account non risalibile
///  * `k` = hash con chiave dell'id   → messaggio non risalibile
///  * `v` = AEAD(id + testo)          → contenuto illeggibile
/// Nessun id in chiaro, nessun timestamp: per un'app che si traveste, un
/// database con id e orari leggibili sarebbe già una confessione.
///
/// La chiave sta nello storage sicuro (Keystore Android). Senza quella il file
/// è inservibile.
class TextStore {
  TextStore(this._crypto);

  final CryptoService _crypto;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Stessa chiave già usata dalla precedente cache a blob: i vecchi dati non
  // sono migrati (era una cache), ma non serve generare una chiave nuova.
  static const _keyName = 'bruma_textcache_key';

  // Nome neutro: non deve suggerire messaggi.
  static const _dbFile = 'bruma_t.db';

  SecureKey? _key;
  Database? _db;

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

  Future<Database> _open() async {
    final cached = _db;
    if (cached != null) return cached;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      '$dir/$_dbFile',
      version: 1,
      onCreate: (d, _) async {
        await d.execute(
          'create table texts ('
          '  u text not null,'
          '  k text not null,'
          '  v text not null,'
          '  primary key (u, k)'
          ')',
        );
      },
    );
    _db = db;
    return db;
  }

  Future<String> _uidKey(String uid, SecureKey key) async =>
      _crypto.keyedHashB64('u:$uid', key);

  String _rowKey(String uid, String messageId, SecureKey key) =>
      _crypto.keyedHashB64('m:$uid:$messageId', key);

  /// Tutti i testi salvati per [uid] (id messaggio → testo). Le righe
  /// illeggibili vengono ignorate: è un archivio di comodo, non la verità.
  Future<Map<String, String>> load(String uid) async {
    try {
      final key = await _aeadKey();
      final db = await _open();
      final rows = await db.query('texts',
          columns: ['v'], where: 'u = ?', whereArgs: [await _uidKey(uid, key)]);
      final out = <String, String>{};
      for (final r in rows) {
        try {
          final blob = base64Decode(r['v'] as String);
          final plain = utf8.decode(_crypto.decryptContent(blob, key));
          final j = jsonDecode(plain) as Map<String, dynamic>;
          final id = j['i'] as String?;
          final t = j['t'] as String?;
          if (id != null && t != null) out[id] = t;
        } catch (_) {
          // riga corrotta / chiave diversa → salta
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Inserisce/aggiorna SOLO i messaggi passati (scrittura incrementale).
  Future<void> put(String uid, Map<String, String> entries) async {
    if (entries.isEmpty) return;
    try {
      final key = await _aeadKey();
      final db = await _open();
      final u = await _uidKey(uid, key);
      final batch = db.batch();
      for (final e in entries.entries) {
        final payload = jsonEncode({'i': e.key, 't': e.value});
        final blob = _crypto.encryptWithKey(
            Uint8List.fromList(utf8.encode(payload)), key);
        batch.insert(
          'texts',
          {'u': u, 'k': _rowKey(uid, e.key, key), 'v': base64Encode(blob)},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (_) {
      // Archivio best-effort: un errore di scrittura non deve rompere la chat.
    }
  }

  /// Rimuove i testi indicati (revoca, eliminazione, modifica).
  Future<void> removeIds(String uid, Iterable<String> messageIds) async {
    final ids = messageIds.toList();
    if (ids.isEmpty) return;
    try {
      final key = await _aeadKey();
      final db = await _open();
      final u = await _uidKey(uid, key);
      final batch = db.batch();
      for (final id in ids) {
        batch.delete('texts',
            where: 'u = ? and k = ?', whereArgs: [u, _rowKey(uid, id, key)]);
      }
      await batch.commit(noResult: true);
    } catch (_) {}
  }

  /// Cancella tutto ciò che appartiene a [uid] (logout, cambio identità).
  Future<void> clear(String uid) async {
    try {
      final key = await _aeadKey();
      final db = await _open();
      await db.delete('texts',
          where: 'u = ?', whereArgs: [await _uidKey(uid, key)]);
    } catch (_) {}
  }
}
