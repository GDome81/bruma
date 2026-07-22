import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models/models.dart';
import '../../core/secure_screen.dart';
import '../../shared/widgets.dart';

/// Statistiche GENERICHE e aggregate della conversazione (niente elenco dei
/// singoli messaggi): quanti messaggi/foto inviati e ricevuti, quante volte le
/// mie foto sono state aperte, e una classifica delle foto più viste con
/// anteprima del contenuto. Si aggiorna in tempo reale (open_events).
class StatsScreen extends StatefulWidget {
  const StatsScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });
  final String conversationId;
  final String title;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsData {
  _StatsData({
    required this.counts,
    required this.rankedPhotos,
    required this.viewsByPhoto,
    required this.totalPhotoViews,
    required this.deniedPhoto,
  });
  final ({int sent, int received, int sentPhotos, int receivedPhotos}) counts;
  final List<Message> rankedPhotos; // ordinate per visualizzazioni desc
  final Map<String, int> viewsByPhoto;
  final int totalPhotoViews;
  final int deniedPhoto;
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<_StatsData> _future;
  StreamSubscription? _sub;
  final Map<String, Uint8List?> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Aggiorna quando arriva un nuovo evento di apertura.
    _sub = AppServices.instance.stats
        .watchMyOpenEvents()
        .listen((_) => _reload());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  Future<_StatsData> _load() async {
    final messages = AppServices.instance.messages;
    final stats = AppServices.instance.stats;
    // Avvia in parallelo.
    final countsF = messages.conversationCounts(widget.conversationId);
    final photosF = messages.myPhotoMessages(widget.conversationId);
    final eventsF = stats.eventsForConversation(widget.conversationId);
    final counts = await countsF;
    final photos = await photosF;
    final events = await eventsF;

    final photoIds = photos.map((m) => m.id).toSet();
    final viewsByPhoto = <String, int>{};
    var denied = 0;
    for (final e in events) {
      if (!photoIds.contains(e.messageId)) continue;
      if (e.outcome == OpenOutcome.granted) {
        viewsByPhoto[e.messageId] = (viewsByPhoto[e.messageId] ?? 0) + 1;
      } else {
        denied++;
      }
    }
    final total = viewsByPhoto.values.fold<int>(0, (a, b) => a + b);
    // Classifica: più viste prima; a parità, più recenti prima.
    photos.sort((a, b) {
      final byViews =
          (viewsByPhoto[b.id] ?? 0).compareTo(viewsByPhoto[a.id] ?? 0);
      if (byViews != 0) return byViews;
      return b.createdAt.compareTo(a.createdAt);
    });
    return _StatsData(
      counts: counts,
      rankedPhotos: photos,
      viewsByPhoto: viewsByPhoto,
      totalPhotoViews: total,
      deniedPhoto: denied,
    );
  }

  Future<Uint8List?> _thumb(Message m) async {
    if (_thumbs.containsKey(m.id)) return _thumbs[m.id];
    try {
      final b = await AppServices.instance.openContentBytes(m);
      _thumbs[m.id] = b;
      return b;
    } catch (_) {
      _thumbs[m.id] = null;
      return null;
    }
  }

  void _openPreview(Message m) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PhotoPreviewPage(message: m),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Statistiche · ${widget.title}')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<_StatsData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done && !snap.hasData) {
              return const LoadingView();
            }
            if (snap.hasError) {
              return ErrorView(
                  message: 'Errore: ${snap.error}', onRetry: _reload);
            }
            final d = snap.data!;
            final c = d.counts;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _sectionTitle(context, 'Messaggi'),
                Row(children: [
                  _statCard(context, 'Inviati', '${c.sent}',
                      Icons.north_east, Colors.blue),
                  const SizedBox(width: 12),
                  _statCard(context, 'Ricevuti', '${c.received}',
                      Icons.south_west, Colors.teal),
                ]),
                const SizedBox(height: 20),
                _sectionTitle(context, 'Foto'),
                Row(children: [
                  _statCard(context, 'Inviate', '${c.sentPhotos}',
                      Icons.photo_camera_outlined, Colors.purple),
                  const SizedBox(width: 12),
                  _statCard(context, 'Ricevute', '${c.receivedPhotos}',
                      Icons.image_outlined, Colors.indigo),
                ]),
                const SizedBox(height: 20),
                _sectionTitle(context, 'Aperture delle tue foto'),
                Row(children: [
                  _statCard(context, 'Visualizzazioni', '${d.totalPhotoViews}',
                      Icons.visibility_outlined, Colors.green),
                  const SizedBox(width: 12),
                  _statCard(context, 'Tentativi negati', '${d.deniedPhoto}',
                      Icons.block_outlined,
                      Theme.of(context).colorScheme.error),
                ]),
                const SizedBox(height: 24),
                _sectionTitle(context, 'Foto più viste'),
                if (d.rankedPhotos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: EmptyView(
                      icon: Icons.leaderboard_outlined,
                      title: 'Nessuna foto inviata',
                      subtitle:
                          'Quando invii foto, qui vedrai quali sono state '
                          'aperte di più (con anteprima).',
                    ),
                  )
                else
                  ...List.generate(d.rankedPhotos.length, (i) {
                    final m = d.rankedPhotos[i];
                    final views = d.viewsByPhoto[m.id] ?? 0;
                    return _rankRow(context, i + 1, m, views);
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _rankRow(BuildContext context, int rank, Message m, int views) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openPreview(m),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // Posizione in classifica.
              SizedBox(
                width: 26,
                child: Text('$rank',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: cs.primary)),
              ),
              // Miniatura (decifrata pigramente).
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: FutureBuilder<Uint8List?>(
                    future: _thumb(m),
                    builder: (_, s) {
                      if (s.connectionState != ConnectionState.done) {
                        return Container(
                          color: cs.surfaceContainerHighest,
                          child: const Center(
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        );
                      }
                      final b = s.data;
                      if (b == null) {
                        return Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(Icons.image_not_supported_outlined,
                              color: cs.onSurfaceVariant),
                        );
                      }
                      return Image.memory(b, fit: BoxFit.cover);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$views ${views == 1 ? 'apertura' : 'aperture'}',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Inviata ${formatTimestamp(m.createdAt)}',
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(BuildContext context, String label, String value,
      IconData icon, Color accent) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

/// Anteprima a schermo intero di una propria foto (con FLAG_SECURE su Android).
class _PhotoPreviewPage extends StatefulWidget {
  const _PhotoPreviewPage({required this.message});
  final Message message;

  @override
  State<_PhotoPreviewPage> createState() => _PhotoPreviewPageState();
}

class _PhotoPreviewPageState extends State<_PhotoPreviewPage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    SecureScreenGuard.acquire();
    _future = AppServices.instance.openContentBytes(widget.message);
  }

  @override
  void dispose() {
    SecureScreenGuard.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Anteprima'),
      ),
      body: Center(
        child: FutureBuilder<Uint8List>(
          future: _future,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator();
            }
            if (s.hasError || s.data == null) {
              return const Text('Impossibile aprire la foto',
                  style: TextStyle(color: Colors.white));
            }
            return InteractiveViewer(
              maxScale: 5,
              child: Image.memory(s.data!, fit: BoxFit.contain),
            );
          },
        ),
      ),
    );
  }
}
