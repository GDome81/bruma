import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
/// Cosa NON si vede sul disco:
///  * `u` = hash con chiave dell'uid  → account non risalibile
///  * `k` = hash con chiave dell'id   → messaggio non risalibile
///  * `v` = AEAD(id + testo), riempito a multipli di 256 byte → contenuto
///    illeggibile e lunghezza del messaggio nascosta
/// Nessun id in chiaro, nessun timestamp: per un'app che si traveste, un
/// database con id e orari leggibili sarebbe già una confessione.
///
/// Cosa RESTA visibile senza la chiave (limiti noti, non nascondibili qui):
/// il NUMERO di righe, quante ne ha ciascun account (valori `u` distinti) e la
/// dimensione del file. Non il contenuto, non chi, non quando.
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
      var i = 0;
      for (final r in rows) {
        // Ogni tanto restituisce il controllo al loop degli eventi: con
        // migliaia di righe, decifrarle tutte di fila bloccava i frame.
        if (++i % 200 == 0) await Future<void>.delayed(Duration.zero);
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

  /// Riempie il testo fino al multiplo di [_pad] byte: senza, la LUNGHEZZA del
  /// valore cifrato rivelerebbe quella del messaggio (un "ok" e un paragrafo
  /// sono distinguibili a occhio anche senza la chiave).
  static const _pad = 256;

  String _padded(String id, String text) {
    final base = jsonEncode({'i': id, 't': text});
    final target = ((base.length ~/ _pad) + 1) * _pad;
    return jsonEncode({'i': id, 't': text, 'p': ' ' * (target - base.length)});
  }

  /// Inserisce/aggiorna SOLO i messaggi passati (scrittura incrementale).
  /// Ritorna false se la scrittura non è andata a buon fine, così chi chiama
  /// può rimettere gli id in coda invece di perderli.
  Future<bool> put(String uid, Map<String, String> entries) async {
    if (entries.isEmpty) return true;
    try {
      final key = await _aeadKey();
      final db = await _open();
      final u = await _uidKey(uid, key);
      final batch = db.batch();
      for (final e in entries.entries) {
        final blob = _crypto.encryptWithKey(
            Uint8List.fromList(utf8.encode(_padded(e.key, e.value))), key);
        batch.insert(
          'texts',
          {'u': u, 'k': _rowKey(uid, e.key, key), 'v': base64Encode(blob)},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      return true;
    } catch (_) {
      // Archivio best-effort: un errore di scrittura non deve rompere la chat.
      return false;
    }
  }

  /// Rimuove i testi indicati (revoca, eliminazione, modifica).
  /// Ritorna false se la cancellazione è fallita: chi chiama deve riprovare,
  /// perché un contenuto revocato non può restare sul disco.
  Future<bool> removeIds(String uid, Iterable<String> messageIds) async {
    final ids = messageIds.toList();
    if (ids.isEmpty) return true;
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
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cancella il vecchio archivio a blob (SharedPreferences) rimasto dai
  /// rilasci precedenti. Senza questo resterebbe sul dispositivo, ancora
  /// decifrabile con la stessa chiave, e nemmeno il logout lo toccherebbe.
  Future<void> purgeLegacyBlob(String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('bruma_textcache_$uid');
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
