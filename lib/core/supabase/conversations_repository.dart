import 'package:supabase_flutter/supabase_flutter.dart';

import '../local_prefs.dart';
import '../models/models.dart';
import 'messages_repository.dart';
import 'profile_repository.dart';

class ConversationsRepository {
  ConversationsRepository(this._client, this._profiles, this._messages);
  final SupabaseClient _client;
  final ProfileRepository _profiles;
  final MessagesRepository _messages;

  String get _uid => _client.auth.currentUser!.id;

  Future<Conversation> getConversation(String id) async {
    final row =
        await _client.from('conversations').select().eq('id', id).single();
    return Conversation.fromMap(row);
  }

  /// Conversazione 1-a-1 con [otherId] (in una delle due orientazioni).
  Future<Conversation?> getWithUser(String otherId) async {
    final row = await _client
        .from('conversations')
        .select()
        .or('and(user_a.eq.$_uid,user_b.eq.$otherId),'
            'and(user_a.eq.$otherId,user_b.eq.$_uid)')
        .maybeSingle();
    return row == null ? null : Conversation.fromMap(row);
  }

  Future<List<Conversation>> listRaw() async {
    final rows = await _client
        .from('conversations')
        .select()
        .or('user_a.eq.$_uid,user_b.eq.$_uid');
    return rows.map(Conversation.fromMap).toList();
  }

  /// Lista chat pronta per la UI: profilo dell'altro + ultimo messaggio,
  /// ordinata per attivita' piu' recente. Con timeout: se il server è lento la
  /// schermata chat mostra un errore con "Riprova" invece di girare a vuoto.
  Future<List<ConversationView>> listConversationViews() {
    return _listConversationViews().timeout(const Duration(seconds: 25));
  }

  Future<List<ConversationView>> _listConversationViews() async {
    final convs = await listRaw();
    if (convs.isEmpty) return [];

    final otherIds =
        convs.map((c) => c.otherUserId(_uid)).toSet().toList();
    final profiles = await _profiles.getProfilesByIds(otherIds);

    // Percorso rapido: ultimo messaggio + non letti di TUTTE le chat in una
    // sola RPC (prima erano 2 richieste per conversazione, in sequenza).
    try {
      return await _viewsViaRpc(convs, profiles);
    } catch (_) {
      // Migration chat_list non ancora applicata (o errore): ripiega sul
      // percorso vecchio, più lento ma sempre funzionante.
    }

    // In parallelo per ogni conversazione: ultimo messaggio + conteggio non letti.
    final views = await Future.wait(convs.map((c) async {
      final otherId = c.otherUserId(_uid);
      final other = profiles[otherId] ??
          Profile(id: otherId, displayName: 'Sconosciuto', publicKey: '');
      final last = await _messages.lastMessage(c.id);
      final unread =
          await _messages.unreadCount(c.id, LocalPrefs.lastRead(c.id));
      return ConversationView(
        conversation: c,
        other: other,
        lastMessage: last,
        unread: unread,
      );
    }));

    _sortByRecent(views);
    return views;
  }

  /// Costruisce le viste con la RPC `chat_list`: una sola richiesta per tutte le
  /// conversazioni. Le soglie di lettura sono locali al dispositivo, quindi
  /// vengono passate come parametro.
  Future<List<ConversationView>> _viewsViaRpc(
    List<Conversation> convs,
    Map<String, Profile> profiles,
  ) async {
    final lastRead = <String, String>{};
    for (final c in convs) {
      final t = LocalPrefs.lastRead(c.id);
      if (t != null) lastRead[c.id] = t.toUtc().toIso8601String();
    }
    final rows = await _client
        .rpc('chat_list', params: {'p_last_read': lastRead}) as List<dynamic>;
    final byConv = <String, ({Message? last, int unread})>{};
    for (final r in rows) {
      final row = r as Map<String, dynamic>;
      final lm = row['last_message'];
      byConv[row['conversation_id'] as String] = (
        last: lm == null
            ? null
            : Message.fromMap(Map<String, dynamic>.from(lm as Map)),
        unread: (row['unread'] as num?)?.toInt() ?? 0,
      );
    }
    final views = [
      for (final c in convs)
        ConversationView(
          conversation: c,
          other: profiles[c.otherUserId(_uid)] ??
              Profile(
                  id: c.otherUserId(_uid),
                  displayName: 'Sconosciuto',
                  publicKey: ''),
          lastMessage: byConv[c.id]?.last,
          unread: byConv[c.id]?.unread ?? 0,
        ),
    ];
    _sortByRecent(views);
    return views;
  }

  void _sortByRecent(List<ConversationView> views) {
    views.sort((a, b) {
      final ta = a.lastMessage?.createdAt;
      final tb = b.lastMessage?.createdAt;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
  }

  Future<void> updateProtection(
    String id, {
    required bool enabled,
    required int maxOpens,
    required int maxDurationSeconds,
  }) async {
    await _client.from('conversations').update({
      'protection_enabled': enabled,
      'max_opens': maxOpens,
      'max_duration_seconds': maxDurationSeconds,
    }).eq('id', id);
  }

  /// Stream leggero per aggiornare la lista quando arrivano nuovi messaggi.
  Stream<List<Message>> watchAllMyMessages() {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(Message.fromMap).toList());
  }
}
