import 'package:flutter/material.dart';

/// Vista centrale di caricamento.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[
            const SizedBox(height: 16),
            Text(label!),
          ],
        ],
      ),
    );
  }
}

/// Vista d'errore con eventuale retry.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Riprova')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Stato vuoto (nessun elemento).
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cs.outline),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Nota sui limiti noti (sezione 11 della spec) da mostrare nelle impostazioni
/// di protezione e nel visualizzatore, per non nascondere le limitazioni.
class LimitsNote extends StatelessWidget {
  const LimitsNote({super.key, this.compact = false});
  final bool compact;

  static const text =
      'Bruma applica deterrenti forti, non promesse impossibili:\n'
      '• Il blocco screenshot non impedisce di fotografare lo schermo con un '
      'altro dispositivo.\n'
      '• Un client manomesso, dopo una singola apertura, potrebbe conservare la '
      'chiave: il limite di aperture vincola solo l\'app onesta.\n'
      '• La revoca rende inservibile ciò che non è ancora stato aperto; non '
      'recupera ciò che è già stato visto.';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              compact ? text.split('\n').first : text,
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

String formatHms(Duration d) {
  final s = d.inSeconds.clamp(0, 359999);
  final m = (s ~/ 60);
  final sec = s % 60;
  if (m >= 60) {
    final h = m ~/ 60;
    return '${h}h ${m % 60}m';
  }
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

String formatTimestamp(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  if (sameDay) return '$hh:$mm';
  final dd = local.day.toString().padLeft(2, '0');
  final mo = local.month.toString().padLeft(2, '0');
  return '$dd/$mo $hh:$mm';
}
