import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models/models.dart';
import '../../shared/watermark.dart';
import '../../shared/widgets.dart';
import '../conversation/conversation_screen.dart';

/// Notifiche interne: richieste in arrivo (il destinatario chiede di riaprire
/// un contenuto). Il mittente qui rinnova i limiti, reinvia, o rifiuta — e può
/// toccare la riga per andare alla foto nella chat.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  StreamSubscription? _sub;
  List<ContentRequest> _requests = [];
  final Map<String, String> _names = {};
  final Map<String, Future<Uint8List?>> _thumbs = {};
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _sub = AppServices.instance.requests.watchIncoming().listen((list) {
      if (!mounted) return;
      setState(() => _requests = list);
      _loadNames(list);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadNames(List<ContentRequest> list) async {
    final missing = list
        .map((r) => r.requesterId)
        .where((id) => !_names.containsKey(id))
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    try {
      final map = await AppServices.instance.profiles.getProfilesByIds(missing);
      if (!mounted) return;
      setState(() => map.forEach((k, v) => _names[k] = v.displayName));
    } catch (_) {}
  }

  /// Miniatura della foto richiesta (memoizzata). Come proprietario posso
  /// decifrare la mia copia senza consumare aperture.
  Future<Uint8List?> _thumb(String messageId) {
    return _thumbs.putIfAbsent(messageId, () async {
      try {
        final m = await AppServices.instance.messages.getMessage(messageId);
        if (m == null || m.type != MessageType.photo) return null;
        return await AppServices.instance.openPhotoBytesCached(m);
      } catch (_) {
        return null;
      }
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _open(ContentRequest req) async {
    try {
      final m = await AppServices.instance.messages.getMessage(req.messageId);
      if (m == null) {
        _snack('Contenuto non più disponibile.');
        return;
      }
      final other = await AppServices.instance.profiles.getProfile(req.requesterId);
      if (other == null || !mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConversationScreen(
          conversationId: m.conversationId,
          other: other,
          jumpToMessageId: req.messageId,
        ),
      ));
    } catch (e) {
      _snack('Errore: $e');
    }
  }

  /// Rinnovo coerente con la chat: rinnova la stessa foto + segnaposto
  /// "riaperta" in fondo (nessun reinvio/duplicato).
  Future<void> _renew(ContentRequest req) async {
    final m = await AppServices.instance.messages.getMessage(req.messageId);
    if (m == null) throw Exception('Messaggio non trovato');
    await AppServices.instance.acceptReopen(req, m.conversationId);
  }

  Future<void> _act(
      ContentRequest req, Future<void> Function() action, String ok) async {
    if (_busyId != null) return;
    setState(() => _busyId = req.id);
    try {
      await action();
      _snack(ok);
    } catch (e) {
      _snack('Operazione non riuscita: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifiche')),
      body: _requests.isEmpty
          ? const EmptyView(
              icon: Icons.notifications_none,
              title: 'Nessuna notifica',
              subtitle:
                  'Qui arrivano le richieste di riaprire un contenuto che hai '
                  'inviato.',
            )
          : ListView.separated(
              itemCount: _requests.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _tile(_requests[i]),
            ),
    );
  }

  Widget _tile(ContentRequest req) {
    final name = _names[req.requesterId] ?? '…';
    final busy = _busyId == req.id;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _open(req),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Miniatura → link visivo alla foto.
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: FutureBuilder<Uint8List?>(
                      future: _thumb(req.messageId),
                      builder: (_, s) {
                        if (s.connectionState != ConnectionState.done) {
                          return Container(
                            color: cs.surfaceContainerHighest,
                            child: const Center(
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            ),
                          );
                        }
                        final b = s.data;
                        if (b == null) {
                          return Container(
                            color: cs.surfaceContainerHighest,
                            child: Icon(Icons.lock_open_outlined,
                                color: cs.onSurfaceVariant),
                          );
                        }
                        return WatermarkOverlay(
                          dense: true,
                          child: Image.memory(b, fit: BoxFit.cover),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$name ha chiesto di riaprire una foto',
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(formatTimestamp(req.createdAt),
                          style: Theme.of(context).textTheme.labelSmall),
                      Text('Tocca per vederla nella chat',
                          style: TextStyle(fontSize: 11, color: cs.primary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          _act(req, () => _renew(req), 'Foto riaperta.'),
                      icon: const Icon(Icons.autorenew, size: 18),
                      label: const Text('Rinnova'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _act(
                          req,
                          () => AppServices.instance.resendRequest(req),
                          'Contenuto reinviato.'),
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text('Reinvia'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _act(
                          req,
                          () => AppServices.instance.denyRequest(req),
                          'Rifiutata.'),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Rifiuta'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
