import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'key_request_exception.dart';

/// Stato di accesso di una foto più il contesto che serve alle gallerie:
/// se l'ho inviata io e se è stata offerta come "senza limiti".
/// Le regole (aperture rimaste, scadenza, apribilità) restano quelle di
/// [MessageAccess]: qui non si duplica nulla.
class PhotoAccess {
  PhotoAccess({
    required this.access,
    required this.mine,
    required this.galleryOffered,
  });

  final MessageAccess access;

  /// Vero se la foto l'ho inviata io (quindi `access` è la riga dell'altro).
  final bool mine;
  final bool galleryOffered;

  String get messageId => access.messageId;

  /// Etichetta dello stato EFFETTIVO. Il solo numero di aperture ingannerebbe:
  /// 3 aperture su una foto scaduta o revocata valgono zero.
  String get statusLabel {
    if (!access.active) return 'Revocata';
    if (galleryOffered || !access.protectionEnabled) return 'Senza limiti';
    if (access.isExpired) return 'Scaduta';
    if (access.unlimitedOpens) return 'Aperture illimitate';
    final left = access.remainingOpens;
    if (left <= 0) return 'Aperture esaurite';
    return left == 1 ? '1 apertura rimasta' : '$left aperture rimaste';
  }

  factory PhotoAccess.fromMap(Map<String, dynamic> m) => PhotoAccess(
        access: MessageAccess.fromMap(m),
        mine: (m['mine'] ?? false) as bool,
        galleryOffered: (m['gallery_offered'] ?? false) as bool,
      );
}

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

  /// Stato di accesso di tutte le foto della conversazione, in UNA query:
  /// per le mie foto la riga della CONTROPARTE (quante aperture le restano),
  /// per quelle ricevute la MIA riga (quante ne restano a me).
  Future<List<PhotoAccess>> galleryAccess(String conversationId) async {
    final res = await _client.rpc('gallery_access',
        params: {'p_conversation_id': conversationId});
    final list = (res as List<dynamic>?) ?? const [];
    return [
      for (final r in list)
        PhotoAccess.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Ids dei messaggi di questa conversazione che per ME non sono più apribili
  /// (revocati dal mittente o scaduti: `active = false`), in UNA query.
  ///
  /// Serve a far valere la REVOCA anche sulla cache persistente dei testi: il
  /// contenuto già decifrato va rimosso dal dispositivo, altrimenti resterebbe
  /// leggibile dalla cache anche dopo la revoca.
  Future<Set<String>> inactiveMessageIds(String conversationId) async {
    final rows = await _client
        .from('message_access')
        .select('message_id, messages!inner(conversation_id)')
        .eq('messages.conversation_id', conversationId)
        .eq('recipient_id', _uid)
        .eq('active', false);
    return rows.map((r) => r['message_id'] as String).toSet();
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
