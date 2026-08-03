import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_services.dart';
import '../../core/models/models.dart';
import '../../core/secure_screen.dart';
import '../../shared/watermark.dart';
import '../../shared/widgets.dart';
import 'gallery_help.dart';

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
  int _visible = 5; // paginazione: quante foto mostrare (decifra solo queste)

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
      appBar: AppBar(
        title: Text('Galleria · ${widget.title}'),
        actions: [
          IconButton(
            tooltip: 'Come funziona',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showGalleryHelp(
              context,
              title: 'Le raccolte di Bruma',
              intro: GalleryHelp.intro,
              sections: [
                ...GalleryHelp.collections,
                ...GalleryHelp.galleryStates,
                ...GalleryHelp.actions,
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.collections_bookmark_outlined),
            tooltip: 'Le mie foto disponibili',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MyAvailablePhotosScreen(
                conversationId: widget.conversationId,
                title: widget.title,
              ),
            )),
          ),
        ],
      ),
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
    // Mostro solo le prime _visible foto: solo queste vengono decifrate, così
    // aprire una chat con tante foto non scatena una raffica di decifrature.
    final count = items.length < _visible ? items.length : _visible;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        // Sempre scrollabile: il pull-to-refresh funziona anche con poche foto.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(3),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _GalleryTile(
                  key: ValueKey(items[i].id),
                  message: items[i],
                  otherName: widget.title,
                  onOpen: () => _openViewer(i),
                  onUnavailable: () => _hide(items[i].id),
                  onRemoved: _load,
                ),
                childCount: count,
              ),
            ),
          ),
          if (_visible < items.length)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _visible += 5),
                  icon: const Icon(Icons.expand_more),
                  label: Text('Carica altro (${items.length - _visible})'),
                ),
              ),
            ),
        ],
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
    this.onLongPress,
  });
  final Message message;
  final String otherName;
  final VoidCallback onOpen;
  final VoidCallback onUnavailable;
  final VoidCallback onRemoved;

  /// Se fornito, sostituisce l'azione di default (rimuovi dalla galleria) sul
  /// long-press: usato dalla sezione "Le mie foto disponibili".
  final VoidCallback? onLongPress;

  @override
  State<_GalleryTile> createState() => _GalleryTileState();
}

class _GalleryTileState extends State<_GalleryTile> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    // Se i byte sono già in cache (foto vista prima, o dopo uno scroll) li
    // mostro all'istante: niente spinner, niente ri-download/ri-decifra.
    final cached = AppServices.instance.cachedPhotoBytes(widget.message.id);
    if (cached != null) {
      _bytes = cached;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes =
          await AppServices.instance.openPhotoBytesCached(widget.message);
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
      onLongPress: widget.onLongPress ?? _remove,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WatermarkOverlay(
            dense: true,
            child: Image.memory(_bytes!,
                fit: BoxFit.cover, cacheWidth: 360, gaplessPlayback: true),
          ),
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

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.messages.length) return;
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _go(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _go(1);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.messages;
    final m = msgs[_index];
    final mine = m.senderId == AppServices.instance.uid;
    final hasPrev = _index > 0;
    final hasNext = _index < msgs.length - 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
            '${_index + 1} / ${msgs.length}  ·  ${mine ? 'Tu' : widget.otherName}'),
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: msgs.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => _ViewerPage(message: msgs[i]),
            ),
            if (hasPrev)
              _NavArrow(
                alignment: Alignment.centerLeft,
                icon: Icons.chevron_left,
                onTap: () => _go(-1),
              ),
            if (hasNext)
              _NavArrow(
                alignment: Alignment.centerRight,
                icon: Icons.chevron_right,
                onTap: () => _go(1),
              ),
          ],
        ),
      ),
    );
  }
}

/// Freccia di navigazione semitrasparente (utile soprattutto da PC/mouse,
/// dove lo swipe non è ovvio).
class _NavArrow extends StatelessWidget {
  const _NavArrow({
    required this.alignment,
    required this.icon,
    required this.onTap,
  });

  final Alignment alignment;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          color: Colors.black45,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, color: Colors.white, size: 34),
            ),
          ),
        ),
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
  final TransformationController _tc = TransformationController();
  bool _zoomed = false;

  @override
  bool get wantKeepAlive => true; // non ri-decifrare tornando indietro

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onTransform);
    _load();
  }

  @override
  void dispose() {
    _tc.removeListener(_onTransform);
    _tc.dispose();
    super.dispose();
  }

  // Con panEnabled sempre true, InteractiveViewer mangia il drag orizzontale e
  // il PageView non scorre più (soprattutto col mouse da PC). Abilito il pan
  // solo quando la foto è ingrandita: da non-ingrandita lo swipe passa al pager.
  void _onTransform() {
    final zoomed = _tc.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  Future<void> _load() async {
    // Byte già in cache (miniatura in galleria) → mostra subito, niente
    // ri-download/ri-decifra.
    final cached = AppServices.instance.cachedPhotoBytes(widget.message.id);
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    try {
      final b = await AppServices.instance.openPhotoBytesCached(widget.message);
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
    return WatermarkOverlay(
      child: InteractiveViewer(
        transformationController: _tc,
        panEnabled: _zoomed,
        maxScale: 5,
        child: Center(
          child:
              Image.memory(_bytes!, fit: BoxFit.contain, gaplessPlayback: true),
        ),
      ),
    );
  }
}

/// Le MIE foto rese disponibili (senza limiti) in questa chat ma che NON sono
/// più nella mia galleria. Serve a ricordare cosa ho condiviso: la foto resta
/// accessibile all'altro anche dopo che l'ho tolta dalla mia galleria. Da qui
/// posso ri-aggiungerla alla mia galleria o toglierla dalla disponibilità.
class MyAvailablePhotosScreen extends StatefulWidget {
  const MyAvailablePhotosScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  final String conversationId;
  final String title;

  @override
  State<MyAvailablePhotosScreen> createState() =>
      _MyAvailablePhotosScreenState();
}

class _MyAvailablePhotosScreenState extends State<MyAvailablePhotosScreen> {
  List<Message>? _items; // null = in caricamento
  Object? _error;
  int _visible = 5;

  @override
  void initState() {
    super.initState();
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
      final items = await AppServices.instance
          .myAvailablePhotosNotSaved(widget.conversationId);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _hide(String messageId) {
    if (!mounted || _items == null) return;
    setState(
        () => _items = _items!.where((m) => m.id != messageId).toList());
  }

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

  Future<void> _actions(Message m) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('Aggiungi alla mia galleria'),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Togli dalla disponibilità'),
              subtitle: const Text(
                  'Torna protetta e sparisce dalla galleria dell\'altro. Non '
                  'viene cancellata.'),
              onTap: () => Navigator.pop(ctx, 'unoffer'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'save') {
      try {
        await AppServices.instance.addToGallery(m.id, widget.conversationId);
        _hide(m.id); // ora è nella mia galleria → esce da questa sezione
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Aggiunta alla tua galleria.')));
        }
      } catch (_) {}
    } else if (action == 'unoffer') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Togliere dalla disponibilità?'),
          content: const Text(
              'La foto torna protetta (limiti della chat) e sparisce dalla '
              'galleria dell\'altro. NON viene cancellata.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annulla')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Togli')),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await AppServices.instance.unofferPhotoFromGallery(m.id);
        _hide(m.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Tolta dalla disponibilità (ora protetta).')));
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Mie foto disponibili · ${widget.title}')),
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
        icon: Icons.collections_bookmark_outlined,
        title: 'Niente qui',
        subtitle:
            'Le foto che hai reso disponibili e poi tolto dalla tua galleria '
            'compaiono qui, così ricordi cosa hai condiviso con l\'altro.',
      );
    }
    final count = items.length < _visible ? items.length : _visible;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(3),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _GalleryTile(
                  key: ValueKey(items[i].id),
                  message: items[i],
                  otherName: widget.title,
                  onOpen: () => _openViewer(i),
                  onUnavailable: () => _hide(items[i].id),
                  onRemoved: _load,
                  onLongPress: () => _actions(items[i]),
                ),
                childCount: count,
              ),
            ),
          ),
          if (_visible < items.length)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _visible += 5),
                  icon: const Icon(Icons.expand_more),
                  label: Text('Carica altro (${items.length - _visible})'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
