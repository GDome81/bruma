import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/local_prefs.dart';
import '../../core/models/models.dart';
import '../../shared/widgets.dart';
import '../conversation/conversation_screen.dart';

/// Messaggi salvati nei preferiti (SOLO locali su questo dispositivo), di tutte
/// le chat. Toccandone uno si apre la relativa chat nel punto del messaggio.
/// Non decifra nulla: l'anteprima appare solo se il contenuto è già in RAM
/// (così aprire questa lista non consuma "aperture" né segna come letto).
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavEntry {
  _FavEntry(this.message, this.other);
  final Message message;
  final Profile other;
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late Future<List<_FavEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_FavEntry>> _load() async {
    final favs = LocalPrefs.favorites(); // (convId, msgId), recenti prima
    if (favs.isEmpty) return [];
    final ids = favs.map((f) => f.messageId).toList();
    final msgs = await AppServices.instance.messages.getByIds(ids);
    final byId = {for (final m in msgs) m.id: m};
    // Nomi contatto (e Profile per aprire la chat) senza query extra: riuso la
    // lista chat che già associa conversazione → altro utente.
    final views =
        await AppServices.instance.conversations.listConversationViews();
    final otherByConv = {for (final v in views) v.conversation.id: v.other};
    final out = <_FavEntry>[];
    for (final f in favs) {
      final m = byId[f.messageId];
      final other = otherByConv[f.conversationId];
      if (m != null && other != null) out.add(_FavEntry(m, other));
    }
    return out;
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _open(_FavEntry e) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationScreen(
        conversationId: e.message.conversationId,
        other: e.other,
        jumpToMessageId: e.message.id,
      ),
    ));
    if (mounted) _reload(); // al ritorno: potrei aver tolto un preferito
  }

  Future<void> _remove(_FavEntry e) async {
    await LocalPrefs.setFavorite(
        e.message.conversationId, e.message.id, false);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Preferiti')),
      body: FutureBuilder<List<_FavEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return ErrorView(message: 'Errore: ${snap.error}', onRetry: _reload);
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const EmptyView(
              icon: Icons.star_border,
              title: 'Nessun preferito',
              subtitle:
                  'Tieni premuto un messaggio e scegli "Salva nei preferiti". '
                  'Lo ritrovi qui e, toccandolo, torni al suo punto nella chat.',
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => _tile(items[i]),
          );
        },
      ),
    );
  }

  Widget _tile(_FavEntry e) {
    final m = e.message;
    final mine = m.senderId == AppServices.instance.uid;
    final isPhoto = m.type == MessageType.photo;
    // Anteprima SOLO da cache in RAM: non fa richieste né consuma aperture.
    final cachedText = m.type == MessageType.text
        ? AppServices.instance.cachedText(m.id)
        : null;
    final cachedBytes =
        isPhoto ? AppServices.instance.cachedPhotoBytes(m.id) : null;

    Widget leading;
    if (cachedBytes != null) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(cachedBytes,
            width: 44, height: 44, fit: BoxFit.cover),
      );
    } else {
      leading = CircleAvatar(
        child:
            Icon(isPhoto ? Icons.photo_outlined : Icons.chat_bubble_outline),
      );
    }

    String title;
    if (cachedText != null && cachedText.trim().isNotEmpty) {
      title = cachedText.trim();
    } else if (isPhoto) {
      title = 'Foto';
    } else {
      title = 'Messaggio di testo';
    }

    return ListTile(
      leading: leading,
      title: Text('${mine ? 'Tu: ' : ''}$title',
          maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle:
          Text('${e.other.displayName} · ${formatTimestamp(m.createdAt)}'),
      trailing: IconButton(
        icon: const Icon(Icons.star, color: Colors.amber),
        tooltip: 'Rimuovi dai preferiti',
        onPressed: () => _remove(e),
      ),
      onTap: () => _open(e),
    );
  }
}
