import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// Richieste del destinatario di riavere un contenuto (rinnovo limiti /
/// reinvio). Il mittente approva.
class RequestsRepository {
  RequestsRepository(this._client);
  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  /// Il destinatario chiede al mittente [ownerId] di riaprire [messageId].
  Future<void> createRequest({
    required String messageId,
    required String ownerId,
  }) async {
    await _client.from('content_requests').insert({
      'message_id': messageId,
      'requester_id': _uid,
      'owner_id': ownerId,
    });
  }

  Future<void> resolve(String requestId, String status) async {
    await _client.from('content_requests').update({
      'status': status,
      'resolved_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', requestId);
  }

  /// Rinnova i limiti (mittente) sulla riga del destinatario.
  Future<void> renew(String messageId) async {
    await _client.rpc('renew_access', params: {'p_message_id': messageId});
  }

  /// Richieste in arrivo per me (mittente), ancora da gestire — live.
  Stream<List<ContentRequest>> watchIncoming() {
    return _client
        .from('content_requests')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows
            .map(ContentRequest.fromMap)
            .where((r) =>
                r.ownerId == _uid && r.status == RequestStatus.pending)
            .toList());
  }

  /// Le MIE richieste (lato destinatario) — per aggiornarsi dal vivo quando il
  /// mittente le gestisce (rinnovo/reinvio).
  Stream<List<ContentRequest>> watchMine() {
    return _client
        .from('content_requests')
        .stream(primaryKey: ['id'])
        .map((rows) => rows
            .map(ContentRequest.fromMap)
            .where((r) => r.requesterId == _uid)
            .toList());
  }
}
