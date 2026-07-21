import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'key_request_exception.dart';

/// Gestione dell'apertura controllata e della revoca.
class AccessRepository {
  AccessRepository(this._client);
  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  // Colonne leggibili di message_access: ESCLUDE wrapped_key (il ruolo
  // authenticated non ha il GRANT su quella colonna, quindi un `select *`
  // verrebbe rifiutato con permission denied).
  static const _cols =
      'id,message_id,recipient_id,protection_enabled,max_opens,'
      'max_duration_seconds,expires_at,open_count,active,created_at';

  /// Riga di accesso vista dal destinatario (per mostrare "N aperture rimaste").
  /// Non include mai `wrapped_key` (non leggibile via SELECT).
  Future<MessageAccess?> getMyAccess(String messageId) async {
    final row = await _client
        .from('message_access')
        .select(_cols)
        .eq('message_id', messageId)
        .eq('recipient_id', _uid)
        .maybeSingle();
    return row == null ? null : MessageAccess.fromMap(row);
  }

  /// Riga di accesso del DESTINATARIO di un messaggio, letta lato mittente (per
  /// le statistiche/ricevute). Esclude la riga "self" del mittente (ogni
  /// messaggio ha due righe: destinatario + copia del mittente).
  Future<MessageAccess?> getRecipientAccess(String messageId) async {
    final row = await _client
        .from('message_access')
        .select(_cols)
        .eq('message_id', messageId)
        .neq('recipient_id', _uid)
        .maybeSingle();
    return row == null ? null : MessageAccess.fromMap(row);
  }

  /// Righe di accesso lato mittente (per le statistiche), su piu' messaggi.
  Future<Map<String, MessageAccess>> getAccessForMessages(
      List<String> messageIds) async {
    if (messageIds.isEmpty) return {};
    final rows = await _client
        .from('message_access')
        .select(_cols)
        .inFilter('message_id', messageIds);
    final map = <String, MessageAccess>{};
    for (final r in rows) {
      final a = MessageAccess.fromMap(r);
      map[a.messageId] = a;
    }
    return map;
  }

  /// Richiede la chiave incapsulata per aprire un contenuto (check atomico
  /// lato server). Lancia [KeyRequestException] se negata.
  Future<String> requestKey(String messageId) async {
    try {
      final res = await _client
          .rpc('request_key', params: {'p_message_id': messageId});
      return res as String;
    } on PostgrestException catch (e) {
      throw KeyRequestException.fromMessage(e.message);
    }
  }

  Future<void> revokeMessage(String messageId) async {
    await _client.rpc('revoke_message', params: {'p_message_id': messageId});
  }

  Future<void> revokeConversation(String conversationId) async {
    await _client.rpc('revoke_conversation',
        params: {'p_conversation_id': conversationId});
  }
}
