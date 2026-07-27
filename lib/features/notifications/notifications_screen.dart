import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models/models.dart';
import '../../shared/widgets.dart';

/// Notifiche interne: richieste in arrivo (il destinatario chiede di riaprire
/// un contenuto). Il mittente qui rinnova i limiti, reinvia, o rifiuta.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  StreamSubscription? _sub;
  List<ContentRequest> _requests = [];
  final Map<String, String> _names = {};
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

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_open_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$name ha chiesto di riaprire un contenuto',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Text(formatTimestamp(req.createdAt),
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 8),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _act(
                      req,
                      () => AppServices.instance.renewRequest(req),
                      'Limiti rinnovati.'),
                  icon: const Icon(Icons.autorenew, size: 18),
                  label: const Text('Rinnova'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _act(
                      req,
                      () => AppServices.instance.resendRequest(req),
                      'Contenuto reinviato.'),
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Reinvia'),
                ),
                TextButton(
                  onPressed: () => _act(req,
                      () => AppServices.instance.denyRequest(req), 'Rifiutata.'),
                  child: const Text('Rifiuta'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
