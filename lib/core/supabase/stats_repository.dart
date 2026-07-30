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

  /// Ids dei MIEI messaggi in questa conversazione già aperti dal destinatario,
  /// in UNA sola query. Prima ogni bolla ne faceva una per conto proprio: con
  /// una schermata di messaggi erano decine di richieste (scroll a scatti).
  /// Filtra via inner join (niente elenco di id nell'URL, che oltre una certa
  /// lunghezza fa fallire la richiesta con 400).
  Future<Set<String>> readMessageIds(String conversationId) async {
    try {
      // RPC con `distinct`: una riga per messaggio, non per apertura.
      final rows = await _client.rpc('read_message_ids',
          params: {'p_conversation_id': conversationId}) as List<dynamic>;
      return rows.map((e) => e as String).toSet();
    } catch (_) {
      // Migration non ancora applicata: percorso tabella. Qui una riga per
      // APERTURA, quindi ordino dalle più recenti e limito: oltre il tetto di
      // righe la risposta sarebbe troncata in modo arbitrario.
      final rows = await _client
          .from('open_events')
          .select('message_id, messages!inner(conversation_id)')
          .eq('messages.conversation_id', conversationId)
          .eq('outcome', 'granted')
          .neq('recipient_id', _uid) // escludi le mie riletture
          .order('opened_at', ascending: false)
          .limit(1000);
      return rows.map((r) => r['message_id'] as String).toSet();
    }
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
  ///
  /// Filtro via INNER JOIN su `messages` (FK message_id → messages.id) invece
  /// di un enorme `message_id=in.(...)`: in chat lunghe quella lista rendeva
  /// l'URL troppo lungo → 400 Bad Request. La RLS di open_events limita già ai
  /// messaggi inviati da me, quindi restano solo i miei.
  Future<List<OpenEvent>> eventsForConversation(String conversationId) async {
    final rows = await _client
        .from('open_events')
        .select('*, messages!inner(conversation_id)')
        .eq('messages.conversation_id', conversationId)
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
