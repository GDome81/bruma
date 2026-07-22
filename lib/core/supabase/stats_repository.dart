import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// Statistiche di apertura (fonte: open_events). Visibili al mittente per i
/// propri messaggi (garantito dalla RLS lato server).
class StatsRepository {
  StatsRepository(this._client);
  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  /// Vero se il DESTINATARIO ha aperto (outcome 'granted') il messaggio almeno
  /// una volta. Usato per la terza spunta "letto": vale anche per i testi, che
  /// hanno protezione off e quindi non incrementano `open_count`, ma registrano
  /// comunque un evento 'granted'.
  Future<bool> wasReadByRecipient(String messageId) async {
    final rows = await _client
        .from('open_events')
        .select('id')
        .eq('message_id', messageId)
        .eq('outcome', 'granted')
        .neq('recipient_id', _uid) // escludi le riletture del mittente
        .limit(1);
    return rows.isNotEmpty;
  }

  Future<List<OpenEvent>> eventsForMessage(String messageId) async {
    final rows = await _client
        .from('open_events')
        .select()
        .eq('message_id', messageId)
        .neq('recipient_id', _uid) // escludi le riletture del mittente stesso
        .order('opened_at', ascending: false);
    return rows.map(OpenEvent.fromMap).toList();
  }

  /// Eventi per tutti i messaggi che io ho inviato nella conversazione.
  Future<List<OpenEvent>> eventsForConversation(String conversationId) async {
    final myMsgs = await _client
        .from('messages')
        .select('id')
        .eq('conversation_id', conversationId)
        .eq('sender_id', _uid);
    final ids = myMsgs.map((r) => r['id'] as String).toList();
    if (ids.isEmpty) return [];
    final rows = await _client
        .from('open_events')
        .select()
        .inFilter('message_id', ids)
        .neq('recipient_id', _uid) // escludi le riletture del mittente stesso
        .order('opened_at', ascending: false);
    return rows.map(OpenEvent.fromMap).toList();
  }

  /// Stream realtime degli eventi di apertura. La RLS fa passare solo gli
  /// eventi dei messaggi inviati dall'utente corrente.
  Stream<List<OpenEvent>> watchMyOpenEvents() {
    return _client
        .from('open_events')
        .stream(primaryKey: ['id'])
        .order('opened_at', ascending: false)
        .map((rows) => rows.map(OpenEvent.fromMap).toList());
  }
}
