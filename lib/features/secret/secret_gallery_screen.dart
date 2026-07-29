import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/local_prefs.dart';
import '../../core/models/models.dart';
import '../../core/secure_screen.dart';
import '../../shared/watermark.dart';
import '../../shared/widgets.dart';
import '../viewer/viewer_screen.dart';

/// Galleria "segreta": raccolta personale (SOLO locale su questo dispositivo)
/// dei contenuti che l'utente ha marcato come segreti, di tutte le chat.
/// Di default le anteprime sono NASCOSTE (placeholder + data); un tasto
/// "scopri/nascondi" le rivela. Rivelare NON consuma aperture: si mostrano solo
/// le foto proprie o senza limiti (o già in cache); le altre restano un
/// lucchetto (apribili dalla chat).
class SecretGalleryScreen extends StatefulWidget {
  const SecretGalleryScreen({super.key});

  @override
  State<SecretGalleryScreen> createState() => _SecretGalleryScreenState();
}

class _SecretGalleryScreenState extends State<SecretGalleryScreen> {
  late Future<List<Message>> _future;
  bool _revealed = false;

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
    final ids = LocalPrefs.secrets().map((s) => s.messageId).toList();
    if (ids.isEmpty) return [];
    final msgs = await AppServices.instance.messages.getByIds(ids);
    final photos =
        msgs.where((m) => m.type == MessageType.photo).toList();
    photos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return photos;
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _remove(Message m) async {
    await LocalPrefs.setSecret(m.conversationId, m.id, false);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Galleria segreta'),
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
                  'Tieni premuto una foto e scegli "Aggiungi ai segreti". '
                  'Qui restano nascoste dietro placeholder finché non tocchi '
                  '"scopri".',
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
              onRemove: () => _remove(items[i]),
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
    required this.onRemove,
  });

  final Message message;
  final bool revealed;
  final VoidCallback onRemove;

  @override
  State<_SecretTile> createState() => _SecretTileState();
}

class _SecretTileState extends State<_SecretTile> {
  Uint8List? _bytes;

  // Anteprima mostrabile senza consumare aperture: foto mia, oppure senza
  // limiti (offerta), oppure già decifrata in cache.
  bool get _previewable {
    final m = widget.message;
    return m.senderId == AppServices.instance.uid ||
        m.galleryOffered ||
        AppServices.instance.cachedPhotoBytes(m.id) != null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.revealed) _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant _SecretTile old) {
    super.didUpdateWidget(old);
    if (widget.revealed && !old.revealed) _maybeLoad();
  }

  Future<void> _maybeLoad() async {
    if (_bytes != null || !_previewable) return;
    try {
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
    final showImage = widget.revealed && _previewable && _bytes != null;
    return GestureDetector(
      onTap: showImage ? _open : null,
      onLongPress: widget.onRemove,
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
                      widget.revealed && !_previewable
                          ? Icons.lock_outline
                          : Icons.lock,
                      color: cs.onSurfaceVariant,
                      size: 22),
                  const SizedBox(height: 4),
                  Text(
                    formatTimestamp(widget.message.createdAt),
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 10),
                  ),
                ],
              ),
            ),
    );
  }
}
