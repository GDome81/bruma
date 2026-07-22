import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/crypto_service.dart';
import '../models/models.dart';
import 'storage_repository.dart';

/// Invio/ricezione dei messaggi cifrati end-to-end.
///
/// Ogni invio: genera K monouso, cifra il contenuto, incapsula K per il
/// destinatario (sealed box) e crea la riga `message_access` copiando
/// (snapshot) le impostazioni di protezione della conversazione.
class MessagesRepository {
  MessagesRepository(this._client, this._crypto, this._storage);
  final SupabaseClient _client;
  final CryptoService _crypto;
  final StorageRepository _storage;

  String get _uid => _client.auth.currentUser!.id;

  /// Stream realtime dei messaggi di una conversazione (ordine cronologico).
  Stream<List<Message>> watchMessages(String conversationId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .map((rows) => rows.map(Message.fromMap).toList());
  }

  /// Numero di messaggi dell'ALTRO non letti (creati dopo [since]), fino a un
  /// tetto per non caricare troppo. Se [since] è null la chat non è mai stata
  /// aperta: conta tutti i messaggi ricevuti (fino al tetto).
  Future<int> unreadCount(String conversationId, DateTime? since,
      {int cap = 99}) async {
    var q = _client
        .from('messages')
        .select('id')
        .eq('conversation_id', conversationId)
        .neq('sender_id', _uid)
        .filter('deleted_at', 'is', null);
    if (since != null) {
      q = q.gt('created_at', since.toUtc().toIso8601String());
    }
    final rows = await q.limit(cap + 1);
    return rows.length;
  }

  Future<Message?> lastMessage(String conversationId) async {
    final row = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : Message.fromMap(row);
  }

  Future<Message> sendText({
    required Conversation conversation,
    required Profile recipient,
    required Uint8List senderPublicKey,
    required String text,
    String? replyTo,
  }) async {
    final enc = _crypto.encryptContent(
        Uint8List.fromList(utf8.encode(text)));
    late final String wrappedForRecipient;
    late final String wrappedForSelf;
    try {
      wrappedForRecipient = _crypto.wrapKey(
          enc.key, _crypto.decodePublicKey(recipient.publicKey));
      wrappedForSelf = _crypto.wrapKey(enc.key, senderPublicKey);
    } finally {
      enc.key.dispose();
    }

    final inserted = await _client
        .from('messages')
        .insert({
          'conversation_id': conversation.id,
          'sender_id': _uid,
          'type': messageTypeToString(MessageType.text),
          'ciphertext': _crypto.encodeBlob(enc.blob),
          'reply_to': ?replyTo,
        })
        .select()
        .single();
    final messageId = inserted['id'] as String;

    // Il TESTO è sempre visibile (come su WhatsApp): E2E ma senza limiti né
    // scadenza, per il destinatario E per il mittente (copia della chiave).
    await _client.from('message_access').insert([
      _accessRow(messageId, recipient.id, wrappedForRecipient, false, 0, 0),
      _accessRow(messageId, _uid, wrappedForSelf, false, 0, 0),
    ]);
    return Message.fromMap(inserted);
  }

  Future<Message> sendPhoto({
    required Conversation conversation,
    required Profile recipient,
    required Uint8List senderPublicKey,
    required Uint8List imageBytes,
    String? replyTo,
  }) async {
    final enc = _crypto.encryptContent(imageBytes);
    late final String wrappedForRecipient;
    late final String wrappedForSelf;
    try {
      wrappedForRecipient = _crypto.wrapKey(
          enc.key, _crypto.decodePublicKey(recipient.publicKey));
      wrappedForSelf = _crypto.wrapKey(enc.key, senderPublicKey);
    } finally {
      enc.key.dispose();
    }

    // Nome oggetto: "<conversation_id>/<random>.bin" (le policy Storage
    // controllano il primo segmento come conversation_id).
    final rand = _crypto.sodium.randombytes.buf(16);
    final objectName = '${conversation.id}/${_hex(rand)}.bin';

    await _storage.upload(objectName, enc.blob);

    final inserted = await _client
        .from('messages')
        .insert({
          'conversation_id': conversation.id,
          'sender_id': _uid,
          'type': messageTypeToString(MessageType.photo),
          'storage_path': objectName,
          'reply_to': ?replyTo,
        })
        .select()
        .single();
    final messageId = inserted['id'] as String;

    // Destinatario: foto protetta (snapshot delle regole). Mittente: copia
    // libera (protezione off) per rivedere la propria foto senza consumare il
    // contatore del destinatario.
    await _client.from('message_access').insert([
      _accessRow(messageId, recipient.id, wrappedForRecipient,
          conversation.protectionEnabled, conversation.maxOpens,
          conversation.maxDurationSeconds),
      _accessRow(messageId, _uid, wrappedForSelf, false, 0, 0),
    ]);
    return Message.fromMap(inserted);
  }

  Future<Message?> getMessage(String id) async {
    final row =
        await _client.from('messages').select().eq('id', id).maybeSingle();
    return row == null ? null : Message.fromMap(row);
  }

  Future<Uint8List> downloadPhotoCipher(String storagePath) =>
      _storage.download(storagePath);

  // --- Paginazione + realtime ---------------------------------------------

  /// Carica una pagina di messaggi (dal più recente), opzionalmente più
  /// vecchi di [before]. Ritorna in ordine DECRESCENTE (recenti prima).
  Future<List<Message>> fetchPage({
    required String conversationId,
    DateTime? before,
    int limit = 30,
  }) async {
    var q =
        _client.from('messages').select().eq('conversation_id', conversationId);
    if (before != null) {
      q = q.lt('created_at', before.toUtc().toIso8601String());
    }
    final rows =
        await q.order('created_at', ascending: false).limit(limit);
    return rows.map(Message.fromMap).toList();
  }

  /// Sottoscrive INSERT/UPDATE dei messaggi di una conversazione (realtime).
  RealtimeChannel subscribeConversation(
    String conversationId, {
    required void Function(Message) onInsert,
    required void Function(Message) onUpdate,
  }) {
    final channel = _client.channel('conv:$conversationId');
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'conversation_id',
      value: conversationId,
    );
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: (p) => onInsert(Message.fromMap(p.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: (p) => onUpdate(Message.fromMap(p.newRecord)),
        )
        .subscribe();
    return channel;
  }

  /// Sottoscrive TUTTI i messaggi in arrivo per l'utente (tutte le sue
  /// conversazioni, grazie alla RLS) — usata per le notifiche locali.
  RealtimeChannel subscribeInbox(void Function(Message) onMessage) {
    final channel = _client.channel('inbox:$_uid');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (p) => onMessage(Message.fromMap(p.newRecord)),
    ).subscribe();
    return channel;
  }

  // --- Modifica / eliminazione --------------------------------------------

  Future<void> editText({
    required Message message,
    required Profile recipient,
    required Uint8List senderPublicKey,
    required String newText,
  }) async {
    final enc =
        _crypto.encryptContent(Uint8List.fromList(utf8.encode(newText)));
    late final String wrappedRecipient;
    late final String wrappedSelf;
    try {
      wrappedRecipient = _crypto.wrapKey(
          enc.key, _crypto.decodePublicKey(recipient.publicKey));
      wrappedSelf = _crypto.wrapKey(enc.key, senderPublicKey);
    } finally {
      enc.key.dispose();
    }
    await _client.rpc('edit_text_message', params: {
      'p_message_id': message.id,
      'p_ciphertext': _crypto.encodeBlob(enc.blob),
      'p_wrapped_recipient': wrappedRecipient,
      'p_wrapped_self': wrappedSelf,
    });
  }

  Future<void> deleteMessage(Message m) async {
    if (m.type == MessageType.photo && m.storagePath != null) {
      try {
        await _storage.remove(m.storagePath!);
      } catch (_) {}
    }
    await _client.rpc('delete_message', params: {'p_message_id': m.id});
  }

  // --- Reactions -----------------------------------------------------------

  Future<void> setReaction(String messageId, String emoji) async {
    await _client.from('message_reactions').upsert(
      {'message_id': messageId, 'user_id': _uid, 'emoji': emoji},
      onConflict: 'message_id,user_id',
    );
  }

  Future<void> removeReaction(String messageId) async {
    await _client
        .from('message_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', _uid);
  }

  Future<List<Reaction>> reactionsForMessages(List<String> messageIds) async {
    if (messageIds.isEmpty) return [];
    final rows = await _client
        .from('message_reactions')
        .select()
        .inFilter('message_id', messageIds);
    return rows.map(Reaction.fromMap).toList();
  }

  /// Sottoscrive qualunque cambio di reaction visibile (RLS limita ai messaggi
  /// delle mie conversazioni). Il chiamante ricarica il set.
  RealtimeChannel subscribeReactions(void Function() onChange) {
    final channel = _client.channel('reactions:$_uid');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'message_reactions',
      callback: (_) => onChange(),
    ).subscribe();
    return channel;
  }

  /// Conteggi generici per le statistiche: messaggi/foto inviati e ricevuti
  /// (esclusi i messaggi eliminati).
  Future<({int sent, int received, int sentPhotos, int receivedPhotos})>
      conversationCounts(String conversationId) async {
    final rows = await _client
        .from('messages')
        .select('sender_id,type')
        .eq('conversation_id', conversationId)
        .filter('deleted_at', 'is', null);
    int sent = 0, received = 0, sentPhotos = 0, receivedPhotos = 0;
    for (final r in rows) {
      final mine = r['sender_id'] == _uid;
      final isPhoto = r['type'] == 'photo';
      if (mine) {
        sent++;
        if (isPhoto) sentPhotos++;
      } else {
        received++;
        if (isPhoto) receivedPhotos++;
      }
    }
    return (
      sent: sent,
      received: received,
      sentPhotos: sentPhotos,
      receivedPhotos: receivedPhotos
    );
  }

  /// Le foto inviate da me nella conversazione (per la classifica statistiche),
  /// più recenti prima. Esclude le eliminate.
  Future<List<Message>> myPhotoMessages(String conversationId) async {
    final rows = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .eq('sender_id', _uid)
        .eq('type', 'photo')
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: false);
    return rows.map(Message.fromMap).toList();
  }

  /// Path Storage delle foto inviate da me in una conversazione (per la
  /// cancellazione dei blob alla revoca — sezione 12 della spec).
  Future<List<String>> myPhotoStoragePaths(String conversationId) async {
    final rows = await _client
        .from('messages')
        .select('storage_path')
        .eq('conversation_id', conversationId)
        .eq('sender_id', _uid)
        .eq('type', 'photo');
    return rows
        .map((r) => r['storage_path'] as String?)
        .whereType<String>()
        .toList();
  }

  Map<String, dynamic> _accessRow(
    String messageId,
    String recipientId,
    String wrappedKey,
    bool protectionEnabled,
    int maxOpens,
    int maxDurationSeconds,
  ) =>
      {
        'message_id': messageId,
        'recipient_id': recipientId,
        'wrapped_key': wrappedKey,
        'protection_enabled': protectionEnabled,
        'max_opens': maxOpens,
        'max_duration_seconds': maxDurationSeconds,
      };

  String _hex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
