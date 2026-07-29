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
  });

  final String conversationId;
  final Profile other;

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
    final mine = await AppServices.instance.messages
        .myPhotoMessages(widget.conversationId); // già dal più recente
    // Solo quelle ancora sotto controllo di visualizzazioni: le foto rese
    // "senza limiti" in galleria stanno nella galleria normale.
    return mine.where((m) => !m.galleryOffered).toList();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _resend(Message m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reinvia nella chat?'),
        content: const Text(
            'La foto verrà inviata di nuovo come nuovo messaggio, con le regole '
            'di protezione ATTUALI della chat (numero aperture e scadenza).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reinvia')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppServices.instance
          .resendPhotoToChat(message: m, recipient: widget.other);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto reinviata nella chat.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Reinvio non riuscito: $e')));
      }
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
              onResend: () => _resend(items[i]),
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
    required this.onResend,
  });

  final Message message;
  final bool revealed;
  final VoidCallback onResend;

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
      onLongPress: widget.onResend, // tieni premuto → reinvia nella chat
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
