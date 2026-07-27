import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models/models.dart';
import '../../core/secure_screen.dart';
import '../../shared/widgets.dart';
import '../viewer/viewer_screen.dart';

/// Galleria per-chat: le foto "senza limiti" che l'utente ha salvato in questa
/// conversazione. Sono segnalibri: la foto resta cifrata su Storage e si apre
/// al volo; se il mittente la revoca, appare "non più disponibile".
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  final String conversationId;
  final String title;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late Future<List<Message>> _future;

  @override
  void initState() {
    super.initState();
    // Contenuti protetti a schermo → blocco screenshot (APK).
    SecureScreenGuard.acquire();
    _future = AppServices.instance.gallery.listMessages(widget.conversationId);
  }

  @override
  void dispose() {
    SecureScreenGuard.release();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future =
          AppServices.instance.gallery.listMessages(widget.conversationId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Galleria · ${widget.title}')),
      body: FutureBuilder<List<Message>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return ErrorView(message: 'Errore: ${snap.error}', onRetry: _reload);
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const EmptyView(
              icon: Icons.collections_outlined,
              title: 'Galleria vuota',
              subtitle:
                  'Le foto "senza limiti" che salvi in questa chat compaiono '
                  'qui. Tieni premuto su una foto in chat per aggiungerla.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: GridView.builder(
              padding: const EdgeInsets.all(3),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => _GalleryTile(
                message: items[i],
                otherName: widget.title,
                onRemoved: _reload,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GalleryTile extends StatefulWidget {
  const _GalleryTile({
    required this.message,
    required this.otherName,
    required this.onRemoved,
  });
  final Message message;
  final String otherName;
  final VoidCallback onRemoved;

  @override
  State<_GalleryTile> createState() => _GalleryTileState();
}

class _GalleryTileState extends State<_GalleryTile> {
  Uint8List? _bytes;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes =
          await AppServices.instance.openContentBytes(widget.message);
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  void _openFull() {
    final b = _bytes;
    if (b == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ViewerScreen(bytes: b, secure: true),
    ));
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovere dalla galleria?'),
        content: const Text(
            'La rimuovi solo dalla TUA galleria; il messaggio in chat resta.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Rimuovi')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AppServices.instance.removeFromGallery(widget.message.id);
      widget.onRemoved();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_error) {
      return Container(
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.image_not_supported_outlined,
              color: cs.onSurfaceVariant),
        ),
      );
    }
    if (_bytes == null) {
      return Container(
        color: cs.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    final mine = widget.message.senderId == AppServices.instance.uid;
    return GestureDetector(
      onTap: _openFull,
      onLongPress: _remove,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(_bytes!, fit: BoxFit.cover, cacheWidth: 360),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              color: Colors.black54,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(mine ? Icons.person : Icons.person_outline,
                      size: 12, color: Colors.white70),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      mine ? 'Tu' : widget.otherName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
