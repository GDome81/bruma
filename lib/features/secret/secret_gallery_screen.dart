import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models/models.dart';
import '../../core/secure_screen.dart';
import '../../core/supabase/access_repository.dart';
import '../../shared/watermark.dart';
import '../../shared/widgets.dart';
import '../gallery/gallery_help.dart';
import '../viewer/viewer_screen.dart';

/// Contenuti "a tempo" di UNA chat, in due schede:
///
///  * **Le mie** — le foto che HO INVIATO e che hanno ancora dei limiti, con
///    quante aperture restano all'ALTRA persona. Anteprime gratuite: apro la
///    mia copia, che non ha protezione.
///  * **Ricevute** — le foto che POSSO ANCORA APRIRE, con quante aperture
///    restano A ME. Qui NIENTE anteprime automatiche: ogni decifratura consuma
///    una delle mie aperture, quindi si vede un lucchetto e si apre solo su
///    richiesta esplicita.
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

class _Data {
  _Data(this.mine, this.received, this.accessById);

  /// Mie foto ancora sotto limiti (le più recenti prima).
  final List<Message> mine;

  /// Foto ricevute che posso ancora aprire.
  final List<Message> received;

  /// Stato di accesso per id messaggio (assente se la RPC non è disponibile).
  final Map<String, PhotoAccess> accessById;
}

class _SecretGalleryScreenState extends State<SecretGalleryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late Future<_Data> _future;
  bool _revealed = false;
  final Set<String> _reopened = {}; // evita avvisi doppi in chat

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    SecureScreenGuard.acquire();
    _future = _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    SecureScreenGuard.release();
    super.dispose();
  }

  Future<_Data> _load() async {
    final svc = AppServices.instance;
    final me = svc.uid;

    // Stato di accesso di tutte le foto in una richiesta. Se la migration non
    // è ancora applicata si prosegue senza contatori.
    var accessById = <String, PhotoAccess>{};
    try {
      final list = await svc.access.galleryAccess(widget.conversationId);
      accessById = {for (final a in list) a.messageId: a};
    } catch (_) {}

    // Le mie: già disponibili senza contatori (dalla lista messaggi).
    final mineAll = await svc.messages.myPhotoMessages(widget.conversationId);
    final mine = mineAll.where((m) {
      if (m.galleryOffered) return false; // quelle "senza limiti" → Galleria
      final a = accessById[m.id];
      // Senza contatori mostro tutto; con i contatori escludo le revocate.
      return a == null || a.access.active;
    }).toList();

    // Ricevute ancora apribili: serve la RPC, perché lo stato di accesso non è
    // deducibile dal solo messaggio.
    final received = <Message>[];
    if (accessById.isNotEmpty) {
      final openableIds = [
        for (final a in accessById.values)
          if (!a.mine && !a.galleryOffered && a.access.isOpenable) a.messageId,
      ];
      if (openableIds.isNotEmpty) {
        final msgs = await svc.messages.getByIds(openableIds.take(200).toList());
        msgs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        received.addAll(msgs.where((m) => m.senderId != me));
      }
    }
    return _Data(mine, received, accessById);
  }

  void _reload() => setState(() => _future = _load());

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Contenuti a tempo · ${widget.other.displayName}'),
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
                ...GalleryHelp.counters,
                ...GalleryHelp.actions,
              ],
            ),
          ),
          // Lo "scopri" vale solo per le MIE foto: le ricevute non hanno
          // anteprima per non consumare aperture.
          if (_tabs.index == 0)
            IconButton(
              tooltip: _revealed ? 'Nascondi' : 'Scopri',
              icon: Icon(_revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          onTap: (_) => setState(() {}), // aggiorna le azioni in barra
          tabs: const [
            Tab(text: 'Le mie'),
            Tab(text: 'Ricevute'),
          ],
        ),
      ),
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return ErrorView(message: 'Errore: ${snap.error}', onRetry: _reload);
          }
          final d = snap.data!;
          return TabBarView(
            controller: _tabs,
            children: [_mineTab(d), _receivedTab(d)],
          );
        },
      ),
    );
  }

  // --- Scheda "Le mie" -----------------------------------------------------

  Widget _mineTab(_Data d) {
    if (d.mine.isEmpty) {
      return const EmptyView(
        icon: Icons.lock_outline,
        title: 'Niente a tempo',
        subtitle:
            'Qui appaiono le foto che hai inviato in questa chat e che hanno '
            'ancora dei limiti, con quante aperture restano all\'altra persona. '
            'Tocca "scopri" per vedere le anteprime.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(3),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemCount: d.mine.length,
      itemBuilder: (_, i) {
        final m = d.mine[i];
        return _MineTile(
          key: ValueKey(m.id),
          message: m,
          revealed: _revealed,
          status: d.accessById[m.id]?.statusLabel,
          onLongPress: () => _actions(m),
        );
      },
    );
  }

  // --- Scheda "Ricevute" ---------------------------------------------------

  Widget _receivedTab(_Data d) {
    if (d.received.isEmpty) {
      final noRpc = d.accessById.isEmpty;
      return EmptyView(
        icon: Icons.mark_email_unread_outlined,
        title: noRpc ? 'Contatori non disponibili' : 'Niente da aprire',
        subtitle: noRpc
            ? 'Per questa sezione serve la migration gallery_access su '
                'Supabase: senza, l\'app non sa quante aperture ti restano.'
            : 'Non ci sono foto ricevute che puoi ancora aprire. Quelle senza '
                'limiti le trovi nella Galleria della chat.',
      );
    }
    return ListView.separated(
      itemCount: d.received.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final m = d.received[i];
        return _ReceivedTile(
          key: ValueKey(m.id),
          message: m,
          access: d.accessById[m.id],
          onOpened: _reload,
          onJump: () {
            Navigator.of(context).pop();
            widget.onJump(m.id);
          },
        );
      },
    );
  }

  // --- Azioni sulle mie foto ----------------------------------------------

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
              subtitle: const Text(
                  'Apre la chat nel punto in cui hai inviato la foto.'),
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
      _snack('Foto cancellata definitivamente.');
    } catch (e) {
      _snack('Cancellazione non riuscita: $e');
    }
  }

  /// Riabilita la STESSA foto (rinnovo dei limiti), senza inviarne una copia.
  Future<void> _reopen(Message m) async {
    if (_reopened.contains(m.id)) {
      _snack('Foto già riabilitata poco fa.');
      return;
    }
    final access = AppServices.instance.access;
    try {
      final mineAccess = await access.getMyAccess(m.id);
      if (mineAccess != null && !mineAccess.active) {
        _snack('Foto revocata: il file cifrato è stato cancellato, non può '
            'essere riabilitata. Puoi solo inviarne una nuova.');
        return;
      }
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
      _reload();
    } catch (e) {
      _snack('Riabilitazione non riuscita: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Tile "Le mie": anteprima gratuita (copia del mittente) + stato
// ---------------------------------------------------------------------------
class _MineTile extends StatefulWidget {
  const _MineTile({
    super.key,
    required this.message,
    required this.revealed,
    required this.status,
    required this.onLongPress,
  });

  final Message message;
  final bool revealed;
  final String? status;
  final VoidCallback onLongPress;

  @override
  State<_MineTile> createState() => _MineTileState();
}

class _MineTileState extends State<_MineTile> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    if (widget.revealed) _load();
  }

  @override
  void didUpdateWidget(covariant _MineTile old) {
    super.didUpdateWidget(old);
    if (widget.revealed && !old.revealed) _load();
  }

  Future<void> _load() async {
    if (_bytes != null) return;
    try {
      // Foto mia: si decifra dalla mia copia (protezione off) senza consumare.
      final b = await AppServices.instance.openPhotoBytesCached(widget.message);
      if (mounted) setState(() => _bytes = b);
    } catch (_) {}
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
      onLongPress: widget.onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showImage)
            WatermarkOverlay(
              dense: true,
              child: Image.memory(_bytes!,
                  fit: BoxFit.cover, cacheWidth: 360, gaplessPlayback: true),
            )
          else
            Container(
              color: cs.surfaceContainerHighest,
              child: Center(
                child: Icon(
                    widget.revealed ? Icons.hourglass_empty : Icons.lock,
                    color: cs.onSurfaceVariant,
                    size: 22),
              ),
            ),
          // Stato: quante aperture restano ALL'ALTRO (o revocata/scaduta).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              color: Colors.black54,
              child: Text(
                widget.status ?? formatTimestamp(widget.message.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile "Ricevute": nessuna anteprima automatica (aprire consuma un'apertura)
// ---------------------------------------------------------------------------
class _ReceivedTile extends StatefulWidget {
  const _ReceivedTile({
    super.key,
    required this.message,
    required this.access,
    required this.onOpened,
    required this.onJump,
  });

  final Message message;
  final PhotoAccess? access;
  final VoidCallback onOpened;
  final VoidCallback onJump;

  @override
  State<_ReceivedTile> createState() => _ReceivedTileState();
}

class _ReceivedTileState extends State<_ReceivedTile> {
  bool _opening = false;

  /// Se la foto è già stata aperta in questa sessione i byte sono in RAM:
  /// mostrarla non costa un'altra apertura.
  Uint8List? get _cached =>
      AppServices.instance.cachedPhotoBytes(widget.message.id);

  Future<void> _open() async {
    final cached = _cached;
    if (cached != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ViewerScreen(bytes: cached, secure: true),
      ));
      return;
    }
    final a = widget.access?.access;
    final left = a == null || a.unlimitedOpens ? null : a.remainingOpens;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprire la foto?'),
        content: Text(left == null
            ? 'Aprirla consuma una delle tue aperture.'
            : 'Aprirla consuma una delle tue aperture: te ne '
                '${left == 1 ? "resta 1" : "restano $left"}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apri')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _opening = true);
    try {
      final bytes =
          await AppServices.instance.openPhotoBytesCached(widget.message);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ViewerScreen(bytes: bytes, secure: true),
      ));
      widget.onOpened(); // i contatori sono cambiati
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Impossibile aprire: $e')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = widget.access;
    final cached = _cached;
    final expires = a?.access.expiresAt;
    // NB: layout esplicito e non ListTile+trailing. Mettendo i pulsanti nel
    // `trailing` questi si prendevano tutta la larghezza e il testo veniva
    // schiacciato a un carattere per riga.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: cached != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: WatermarkOverlay(
                      dense: true,
                      child: Image.memory(cached, fit: BoxFit.cover),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.lock, color: cs.onSurfaceVariant),
                  ),
          ),
          const SizedBox(width: 12),
          // Expanded: il testo prende lo spazio che resta, mai meno.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a?.statusLabel ?? 'Foto protetta',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    formatTimestamp(widget.message.createdAt),
                    if (expires != null) 'scade ${formatTimestamp(expires)}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_opening)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            FilledButton.tonal(
              onPressed: _open,
              child: Text(cached != null ? 'Rivedi' : 'Apri'),
            ),
            // Menu compatto: un secondo pulsante a tutta larghezza era ciò che
            // rubava lo spazio al testo.
            PopupMenuButton<String>(
              tooltip: 'Altro',
              onSelected: (_) => widget.onJump(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'jump',
                  child: ListTile(
                    leading: Icon(Icons.forum_outlined),
                    title: Text('Vai al messaggio in chat'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
