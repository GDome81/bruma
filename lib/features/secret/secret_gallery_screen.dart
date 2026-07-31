import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models/models.dart';
import '../../core/secure_screen.dart';
import '../../shared/watermark.dart';
import '../../shared/widgets.dart';
import '../viewer/viewer_screen.dart';

/// Galleria "segreta" di UNA chat: raccoglie AUTOMATICAMENTE tutte le foto che
/// HO INVIATO in questa conversazione e che sono ancora "sotto controllo"
/// (protette/limitate, cioè non rese senza limiti in galleria). Serve al
/// mittente per rivedere tutto ciò che ha condiviso.
///
/// Di default le anteprime sono NASCOSTE (placeholder + data); un tasto
/// "scopri/nascondi" le rivela. Sono foto mie → si decifrano dalla mia copia
/// senza consumare aperture.
class SecretGalleryScreen extends StatefulWidget {
  const SecretGalleryScreen({
    super.key,
    required this.conversationId,
    required this.other,
    required this.onJump,
  });

  final String conversationId;
  final Profile other;

  /// Chiamata (dopo aver chiuso questa schermata) per saltare al punto della
  /// chat dove sta quella foto, senza aprire una seconda copia della chat.
  final void Function(String messageId) onJump;

  @override
  State<SecretGalleryScreen> createState() => _SecretGalleryScreenState();
}

class _SecretGalleryScreenState extends State<SecretGalleryScreen> {
  late Future<List<Message>> _future;
  bool _revealed = false;
  final Set<String> _reopened = {}; // evita avvisi doppi in chat

  @override
  void initState() {
    super.initState();
    SecureScreenGuard.acquire();
    _future = _load();
  }

  @override
  void dispose() {
    SecureScreenGuard.release();
    super.dispose();
  }

  Future<List<Message>> _load() async {
    final mine = await AppServices.instance.messages
        .myPhotoMessages(widget.conversationId); // già dal più recente
    // Solo quelle ancora sotto controllo di visualizzazioni: le foto rese
    // "senza limiti" in galleria stanno nella galleria normale.
    return mine.where((m) => !m.galleryOffered).toList();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _actions(Message m) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: const Text('Vai al messaggio in chat'),
              subtitle:
                  const Text('Apre la chat nel punto in cui hai inviato la foto.'),
              onTap: () => Navigator.pop(ctx, 'jump'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_open_outlined),
              title: const Text('Rendi di nuovo apribile'),
              subtitle: const Text(
                  'Riabilita QUESTA foto nella chat, senza inviarne una copia.'),
              onTap: () => Navigator.pop(ctx, 'reopen'),
            ),
            ListTile(
              leading: Icon(Icons.delete_forever,
                  color: Theme.of(ctx).colorScheme.error),
              title: const Text('Cancella definitivamente'),
              subtitle: const Text(
                  'Rimuove la foto dallo Storage e la elimina dalla chat per '
                  'entrambi. Irreversibile.'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'jump') {
      // Chiudi la galleria e chiedi alla chat sottostante di saltare alla foto.
      Navigator.of(context).pop();
      widget.onJump(m.id);
    } else if (action == 'reopen') {
      await _reopen(m);
    } else if (action == 'delete') {
      await _delete(m);
    }
  }

  Future<void> _delete(Message m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancellare definitivamente?'),
        content: const Text(
            'La foto viene rimossa dallo Storage ed eliminata dalla chat per '
            'entrambi. L\'operazione è irreversibile.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancella'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppServices.instance.deleteMessageForEveryone(m);
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto cancellata definitivamente.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cancellazione non riuscita: $e')));
      }
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Riabilita la STESSA foto (rinnovo dei limiti), senza inviarne una copia.
  Future<void> _reopen(Message m) async {
    if (_reopened.contains(m.id)) {
      _snack('Foto già riabilitata poco fa.');
      return;
    }
    final access = AppServices.instance.access;
    // Revocata? revoke_message disattiva TUTTE le copie e cancella il blob:
    // rinnovare non la riporterebbe in vita (il file cifrato non c'è più).
    try {
      final mineAccess = await access.getMyAccess(m.id);
      if (mineAccess != null && !mineAccess.active) {
        _snack('Foto revocata: il file cifrato è stato cancellato, non può '
            'essere riabilitata. Puoi solo inviarne una nuova.');
        return;
      }
      // Già apribile dall'altro → nessun rinnovo necessario (evita un avviso
      // "foto riaperta" inutile in chat).
      final theirs = await access.getRecipientAccess(m.id);
      if (theirs != null && theirs.isOpenable) {
        _snack('Questa foto è già apribile: nessun rinnovo necessario.');
        return;
      }
    } catch (_) {
      // Controlli best-effort: se falliscono si prosegue col rinnovo.
    }
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rendere di nuovo apribile?'),
        content: const Text(
            'La STESSA foto già inviata torna apribile: il contatore di '
            'aperture si azzera e la scadenza viene rimossa. Non viene creata '
            'nessuna copia e non cambiano le statistiche. In chat comparirà un '
            'avviso "foto riaperta".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Riabilita')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppServices.instance.reopenPhotoInChat(m);
      _reopened.add(m.id);
      _snack('Foto di nuovo apribile nella chat.');
    } catch (e) {
      _snack('Riabilitazione non riuscita: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Segreti · ${widget.other.displayName}'),
        actions: [
          IconButton(
            tooltip: _revealed ? 'Nascondi' : 'Scopri',
            icon: Icon(_revealed
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            onPressed: () => setState(() => _revealed = !_revealed),
          ),
        ],
      ),
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
              icon: Icons.lock_outline,
              title: 'Niente di segreto',
              subtitle:
                  'Qui appaiono automaticamente le foto che hai inviato in '
                  'questa chat e che sono ancora sotto controllo di '
                  'visualizzazioni. Tocca "scopri" per vederle.',
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(3),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _SecretTile(
              key: ValueKey(items[i].id),
              message: items[i],
              revealed: _revealed,
              onLongPress: () => _actions(items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _SecretTile extends StatefulWidget {
  const _SecretTile({
    super.key,
    required this.message,
    required this.revealed,
    required this.onLongPress,
  });

  final Message message;
  final bool revealed;
  final VoidCallback onLongPress;

  @override
  State<_SecretTile> createState() => _SecretTileState();
}

class _SecretTileState extends State<_SecretTile> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    if (widget.revealed) _load();
  }

  @override
  void didUpdateWidget(covariant _SecretTile old) {
    super.didUpdateWidget(old);
    if (widget.revealed && !old.revealed) _load();
  }

  Future<void> _load() async {
    if (_bytes != null) return;
    try {
      // Foto mia: si decifra dalla mia copia (protezione off) senza consumare.
      final b = await AppServices.instance.openPhotoBytesCached(widget.message);
      if (mounted) setState(() => _bytes = b);
    } catch (_) {
      // resta il placeholder
    }
  }

  void _open() {
    final b = _bytes;
    if (b == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ViewerScreen(bytes: b, secure: true),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showImage = widget.revealed && _bytes != null;
    return GestureDetector(
      onTap: showImage ? _open : null,
      onLongPress: widget.onLongPress, // tieni premuto → reinvia / cancella
      child: showImage
          ? WatermarkOverlay(
              dense: true,
              child: Image.memory(_bytes!,
                  fit: BoxFit.cover, cacheWidth: 360, gaplessPlayback: true),
            )
          : Container(
              color: cs.surfaceContainerHighest,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      widget.revealed ? Icons.hourglass_empty : Icons.lock,
                      color: cs.onSurfaceVariant,
                      size: 22),
                  const SizedBox(height: 4),
                  Text(
                    formatTimestamp(widget.message.createdAt),
                    style:
                        TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
                  ),
                ],
              ),
            ),
    );
  }
}
