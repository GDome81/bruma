import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/local_prefs.dart';
import '../../core/models/models.dart';
import '../../shared/widgets.dart';

/// Messaggi salvati nei preferiti di UNA chat (solo locali su questo
/// dispositivo). Toccandone uno si torna alla chat e si salta al suo punto.
/// Non decifra nulla: l'anteprima appare solo se il contenuto è già in RAM
/// (così aprire la lista non consuma "aperture" né segna come letto).
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({
    super.key,
    required this.conversationId,
    required this.other,
    required this.onJump,
  });

  final String conversationId;
  final Profile other;

  /// Chiamata (dopo aver chiuso questa schermata) per saltare al messaggio
  /// nella chat sottostante, senza aprire una seconda copia della chat.
  final void Function(String messageId) onJump;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late Future<List<Message>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Message>> _load() async {
    final favs = LocalPrefs.favorites()
        .where((f) => f.conversationId == widget.conversationId)
        .toList(); // recenti prima
    if (favs.isEmpty) return [];
    final ids = favs.map((f) => f.messageId).toList();
    final msgs = await AppServices.instance.messages.getByIds(ids);
    final byId = {for (final m in msgs) m.id: m};
    // Mantieni l'ordine dei preferiti (recenti prima); salta quelli spariti.
    return [
      for (final f in favs)
        if (byId[f.messageId] != null) byId[f.messageId]!,
    ];
  }

  void _reload() => setState(() => _future = _load());

  void _open(Message m) {
    // Chiudi la lista e chiedi alla chat sottostante di saltare al messaggio.
    Navigator.of(context).pop();
    widget.onJump(m.id);
  }

  Future<void> _remove(Message m) async {
    await AppServices.instance
        .setFavorite(m.conversationId, m.id, false);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Preferiti · ${widget.other.displayName}')),
      body: FutureBuilder<List<Message>>(
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

  Widget _tile(Message m) {
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
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '${mine ? 'Tu' : widget.other.displayName} · ${formatTimestamp(m.createdAt)}'),
      trailing: IconButton(
        icon: const Icon(Icons.star, color: Colors.amber),
        tooltip: 'Rimuovi dai preferiti',
        onPressed: () => _remove(m),
      ),
      onTap: () => _open(m),
    );
  }
}
