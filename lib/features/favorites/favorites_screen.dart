import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/local_prefs.dart';
import '../../core/models/models.dart';
import '../../core/secure_store/favorite_notes.dart';
import '../../shared/widgets.dart';

/// Dialog per aggiungere/modificare la nota promemoria di un preferito.
/// La nota è locale e cifrata a riposo (vedi [FavoriteNotes]).
Future<void> editFavoriteNote(BuildContext context, String messageId) async {
  final existing = await FavoriteNotes.get(messageId);
  if (!context.mounted) return;
  final controller = TextEditingController(text: existing ?? '');
  final note = await showDialog<String?>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nota promemoria'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Es. "il tramonto" — per ricordarti quale contenuto è',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Salva')),
      ],
    ),
  );
  if (note == null) return; // annullato
  await FavoriteNotes.set(messageId, note);
}

/// Messaggi salvati nei preferiti di UNA chat (solo locali su questo
/// dispositivo). Toccandone uno si torna alla chat e si salta al suo punto.
/// Ogni preferito può avere una nota promemoria (utile per i contenuti
/// protetti che non si possono rivedere). Da qui si può anche chiedere la
/// riapertura di una foto ricevuta.
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

class _FavItem {
  _FavItem(this.message, this.note);
  final Message message;
  final String? note;
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late Future<List<_FavItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_FavItem>> _load() async {
    final favs = LocalPrefs.favorites()
        .where((f) => f.conversationId == widget.conversationId)
        .toList(); // recenti prima
    if (favs.isEmpty) return [];
    final ids = favs.map((f) => f.messageId).toList();
    final msgs = await AppServices.instance.messages.getByIds(ids);
    final byId = {for (final m in msgs) m.id: m};
    final out = <_FavItem>[];
    for (final f in favs) {
      final m = byId[f.messageId];
      if (m == null) continue; // messaggio sparito → salto
      final note = await FavoriteNotes.get(m.id);
      out.add(_FavItem(m, note));
    }
    return out;
  }

  void _reload() => setState(() => _future = _load());

  void _open(Message m) {
    // Chiudi la lista e chiedi alla chat sottostante di saltare al messaggio.
    Navigator.of(context).pop();
    widget.onJump(m.id);
  }

  Future<void> _editNote(Message m) async {
    await editFavoriteNote(context, m.id);
    _reload();
  }

  Future<void> _requestReopen(Message m) async {
    try {
      await AppServices.instance.requestReopen(
        photoMessageId: m.id,
        conversationId: widget.conversationId,
        ownerId: m.senderId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Richiesta di riapertura inviata.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impossibile inviare la richiesta.')));
      }
    }
  }

  Future<void> _remove(Message m) async {
    await AppServices.instance.setFavorite(m.conversationId, m.id, false);
    await FavoriteNotes.set(m.id, null); // pulisci anche la nota
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Preferiti · ${widget.other.displayName}')),
      body: FutureBuilder<List<_FavItem>>(
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
                  'Puoi aggiungere una nota per ricordartelo e, da qui, chiedere '
                  'di riaprire una foto.',
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

  Widget _tile(_FavItem item) {
    final m = item.message;
    final mine = m.senderId == AppServices.instance.uid;
    final isPhoto = m.type == MessageType.photo;
    final canRequest = !mine && isPhoto; // foto ricevuta → posso chiederne la riapertura
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

    // Titolo: la nota se c'è (è il promemoria migliore per i contenuti che non
    // si rivedono), altrimenti l'anteprima testo, altrimenti il tipo.
    String title;
    if (item.note != null && item.note!.isNotEmpty) {
      title = item.note!;
    } else if (cachedText != null && cachedText.trim().isNotEmpty) {
      title = cachedText.trim();
    } else if (isPhoto) {
      title = 'Foto';
    } else {
      title = 'Messaggio di testo';
    }
    final author = mine ? 'Tu' : widget.other.displayName;

    return ListTile(
      leading: leading,
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('$author · ${formatTimestamp(m.createdAt)}'),
      onTap: () => _open(m),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (v) {
          switch (v) {
            case 'note':
              _editNote(m);
            case 'reopen':
              _requestReopen(m);
            case 'remove':
              _remove(m);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'note',
            child: ListTile(
                leading: Icon(Icons.edit_note),
                title: Text('Modifica nota'),
                contentPadding: EdgeInsets.zero),
          ),
          if (canRequest)
            const PopupMenuItem(
              value: 'reopen',
              child: ListTile(
                  leading: Icon(Icons.lock_open_outlined),
                  title: Text('Richiedi riapertura'),
                  contentPadding: EdgeInsets.zero),
            ),
          const PopupMenuItem(
            value: 'remove',
            child: ListTile(
                leading: Icon(Icons.star, color: Colors.amber),
                title: Text('Rimuovi dai preferiti'),
                contentPadding: EdgeInsets.zero),
          ),
        ],
      ),
    );
  }
}
