import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models/models.dart';
import '../../shared/widgets.dart';

/// Statistiche di apertura per i messaggi inviati in una conversazione.
/// Si aggiorna in tempo reale (Supabase Realtime su open_events).
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

class _StatsScreenState extends State<StatsScreen> {
  late Future<List<OpenEvent>> _future;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _future = AppServices.instance.stats
        .eventsForConversation(widget.conversationId);
    // Ricarica quando arriva un nuovo evento di apertura.
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
    setState(() {
      _future = AppServices.instance.stats
          .eventsForConversation(widget.conversationId);
    });
  }

  ({IconData icon, String label, Color color}) _outcome(
      BuildContext context, OpenOutcome o) {
    final cs = Theme.of(context).colorScheme;
    switch (o) {
      case OpenOutcome.granted:
        return (icon: Icons.check_circle, label: 'Aperto', color: Colors.green);
      case OpenOutcome.deniedRevoked:
        return (
          icon: Icons.block,
          label: 'Negato · revocato',
          color: cs.error
        );
      case OpenOutcome.deniedExpired:
        return (
          icon: Icons.timer_off,
          label: 'Negato · scaduto',
          color: cs.error
        );
      case OpenOutcome.deniedLimit:
        return (
          icon: Icons.do_not_disturb,
          label: 'Negato · limite',
          color: cs.error
        );
      case OpenOutcome.unknown:
        return (icon: Icons.help_outline, label: 'Sconosciuto', color: cs.outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Statistiche · ${widget.title}')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<OpenEvent>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done &&
                !snap.hasData) {
              return const LoadingView();
            }
            if (snap.hasError) {
              return ErrorView(message: 'Errore: ${snap.error}', onRetry: _reload);
            }
            final events = snap.data ?? [];
            final granted =
                events.where((e) => e.outcome == OpenOutcome.granted).length;
            final denied = events.length - granted;
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _statCard(context, 'Aperture', '$granted',
                          Icons.check_circle_outline),
                      const SizedBox(width: 12),
                      _statCard(context, 'Tentativi negati', '$denied',
                          Icons.block_outlined),
                    ],
                  ),
                ),
                if (events.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: EmptyView(
                      icon: Icons.query_stats,
                      title: 'Ancora nessuna apertura',
                      subtitle:
                          'Qui vedrai in tempo reale quando i tuoi contenuti '
                          'vengono aperti (o i tentativi negati).',
                    ),
                  )
                else
                  ...events.map((e) {
                    final o = _outcome(context, e.outcome);
                    return ListTile(
                      leading: Icon(o.icon, color: o.color),
                      title: Text(o.label),
                      subtitle: Text('Messaggio ${e.messageId.substring(0, 8)}…'),
                      trailing: Text(formatTimestamp(e.openedAt),
                          style: Theme.of(context).textTheme.labelSmall),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statCard(
      BuildContext context, String label, String value, IconData icon) {
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
            Icon(icon, color: cs.primary),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
