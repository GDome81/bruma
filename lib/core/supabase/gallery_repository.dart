import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// Galleria per-chat: ogni utente salva (segnalibro) le foto "senza limiti"
/// offerte nella conversazione. Salvare non copia il file: la foto resta
/// cifrata su Storage e riapribile finché il mittente non la revoca.
class GalleryRepository {
  GalleryRepository(this._client);
  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Future<void> add(String messageId, String conversationId) async {
    await _client.from('gallery_items').upsert({
      'user_id': _uid,
      'message_id': messageId,
      'conversation_id': conversationId,
    }, onConflict: 'user_id,message_id');
  }

  Future<void> remove(String messageId) async {
    await _client
        .from('gallery_items')
        .delete()
        .eq('user_id', _uid)
        .eq('message_id', messageId);
  }

  Future<bool> isSaved(String messageId) async {
    final rows = await _client
        .from('gallery_items')
        .select('message_id')
        .eq('user_id', _uid)
        .eq('message_id', messageId)
        .limit(1);
    return rows.isNotEmpty;
  }

  /// Id dei messaggi che l'utente ha salvato in galleria in [conversationId].
  Future<Set<String>> savedIds(String conversationId) async {
    final rows = await _client
        .from('gallery_items')
        .select('message_id')
        .eq('user_id', _uid)
        .eq('conversation_id', conversationId);
    return rows.map((r) => r['message_id'] as String).toSet();
  }

  /// Foto salvate in galleria per la conversazione (dal più recente).
  Future<List<Message>> listMessages(String conversationId) async {
    final saved = await _client
        .from('gallery_items')
        .select('message_id')
        .eq('user_id', _uid)
        .eq('conversation_id', conversationId);
    final ids = saved.map((r) => r['message_id'] as String).toList();
    if (ids.isEmpty) return [];
    final rows = await _client
        .from('messages')
        .select()
        .inFilter('id', ids)
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: false);
    return rows.map(Message.fromMap).toList();
  }
}
