import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models/models.dart';
import '../../core/secure_screen.dart';
import '../../shared/widgets.dart';

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
  List<Message>? _items; // null = in caricamento
  Object? _error;

  @override
  void initState() {
    super.initState();
    // Contenuti protetti a schermo → blocco screenshot (APK).
    SecureScreenGuard.acquire();
    _load();
  }

  @override
  void dispose() {
    SecureScreenGuard.release();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _items = null;
        _error = null;
      });
    }
    try {
      final items =
          await AppServices.instance.gallery.listMessages(widget.conversationId);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Toglie dalla VISTA una foto non più disponibile (es. revocata): niente
  /// riquadro "immagine rotta". Il segnalibro resta (verrà rifiltrato al
  /// prossimo caricamento) ma non si vede.
  void _hide(String messageId) {
    if (!mounted || _items == null) return;
    setState(() =>
        _items = _items!.where((m) => m.id != messageId).toList());
  }

  /// Apre il visualizzatore a schermo intero scorrevole (swipe avanti/indietro).
  void _openViewer(int index) {
    final items = _items;
    if (items == null || items.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GalleryViewerScreen(
        messages: List<Message>.from(items),
        initialIndex: index,
        otherName: widget.title,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Galleria · ${widget.title}')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ErrorView(message: 'Errore: $_error', onRetry: _load);
    }
    final items = _items;
    if (items == null) return const LoadingView();
    if (items.isEmpty) {
      return const EmptyView(
        icon: Icons.collections_outlined,
        title: 'Galleria vuota',
        subtitle:
            'Le foto "senza limiti" che salvi in questa chat compaiono qui. '
            'Tieni premuto su una foto in chat per aggiungerla.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(3),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _GalleryTile(
          key: ValueKey(items[i].id),
          message: items[i],
          otherName: widget.title,
          onOpen: () => _openViewer(i),
          onUnavailable: () => _hide(items[i].id),
          onRemoved: _load,
        ),
      ),
    );
  }
}

class _GalleryTile extends StatefulWidget {
  const _GalleryTile({
    super.key,
    required this.message,
    required this.otherName,
    required this.onOpen,
    required this.onUnavailable,
    required this.onRemoved,
  });
  final Message message;
  final String otherName;
  final VoidCallback onOpen;
  final VoidCallback onUnavailable;
  final VoidCallback onRemoved;

  @override
  State<_GalleryTile> createState() => _GalleryTileState();
}

class _GalleryTileState extends State<_GalleryTile> {
  Uint8List? _bytes;

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
      // Non disponibile (es. revocata) → togli dalla vista: niente riquadro rotto.
      if (mounted) widget.onUnavailable();
    }
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
      onTap: widget.onOpen,
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

/// Visualizzatore a schermo intero scorrevole: swipe sinistra/destra per
/// scorrere le foto della galleria. FLAG_SECURE attivo mentre è aperto.
class GalleryViewerScreen extends StatefulWidget {
  const GalleryViewerScreen({
    super.key,
    required this.messages,
    required this.initialIndex,
    required this.otherName,
  });

  final List<Message> messages;
  final int initialIndex;
  final String otherName;

  @override
  State<GalleryViewerScreen> createState() => _GalleryViewerScreenState();
}

class _GalleryViewerScreenState extends State<GalleryViewerScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    SecureScreenGuard.acquire();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    SecureScreenGuard.release();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.messages;
    final m = msgs[_index];
    final mine = m.senderId == AppServices.instance.uid;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
            '${_index + 1} / ${msgs.length}  ·  ${mine ? 'Tu' : widget.otherName}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: msgs.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => _ViewerPage(message: msgs[i]),
      ),
    );
  }
}

class _ViewerPage extends StatefulWidget {
  const _ViewerPage({required this.message});
  final Message message;

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage>
    with AutomaticKeepAliveClientMixin {
  Uint8List? _bytes;
  bool _error = false;

  @override
  bool get wantKeepAlive => true; // non ri-decifrare tornando indietro

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await AppServices.instance.openContentBytes(widget.message);
      if (mounted) setState(() => _bytes = b);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error) {
      return const Center(
        child: Text('Non più disponibile',
            style: TextStyle(color: Colors.white70)),
      );
    }
    if (_bytes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return InteractiveViewer(
      maxScale: 5,
      child: Center(
        child: Image.memory(_bytes!, fit: BoxFit.contain, gaplessPlayback: true),
      ),
    );
  }
}
