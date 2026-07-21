import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models/models.dart';
import '../../shared/widgets.dart';

/// Impostazioni di protezione per singola chat (valgono solo per le FOTO; i
/// testi sono sempre visibili). Le modifiche valgono per i messaggi futuri
/// (snapshot all'invio). La revoca agisce anche sui messaggi già inviati.
class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

const _unitSeconds = <String, int>{
  'secondi': 1,
  'minuti': 60,
  'ore': 3600,
  'giorni': 86400,
};

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  Conversation? _conv;
  String? _error;
  bool _enabled = true;
  bool _unlimitedOpens = false;
  int _maxOpens = 3;
  bool _noExpiry = false;
  int _durValue = 30;
  String _durUnit = 'secondi';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  ({int value, String unit}) _fromSeconds(int s) {
    if (s <= 0) return (value: 30, unit: 'secondi');
    if (s % 86400 == 0) return (value: s ~/ 86400, unit: 'giorni');
    if (s % 3600 == 0) return (value: s ~/ 3600, unit: 'ore');
    if (s % 60 == 0) return (value: s ~/ 60, unit: 'minuti');
    return (value: s, unit: 'secondi');
  }

  Future<void> _load() async {
    try {
      final c = await AppServices.instance.conversations
          .getConversation(widget.conversationId);
      final d = _fromSeconds(c.maxDurationSeconds);
      setState(() {
        _conv = c;
        _enabled = c.protectionEnabled;
        _unlimitedOpens = c.maxOpens <= 0;
        _maxOpens = c.maxOpens <= 0 ? 3 : c.maxOpens;
        _noExpiry = c.maxDurationSeconds <= 0;
        _durValue = d.value;
        _durUnit = d.unit;
      });
    } catch (e) {
      setState(() => _error = 'Errore: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  int get _computedSeconds =>
      _noExpiry ? 0 : _durValue * (_unitSeconds[_durUnit] ?? 1);
  int get _computedOpens => _unlimitedOpens ? 0 : _maxOpens;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AppServices.instance.conversations.updateProtection(
        widget.conversationId,
        enabled: _enabled,
        maxOpens: _computedOpens,
        maxDurationSeconds: _computedSeconds,
      );
      _snack('Impostazioni salvate (valgono per le nuove foto).');
    } catch (e) {
      _snack('Salvataggio non riuscito: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _revokeAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Revoca tutto'),
        content: const Text(
            'Tutti i contenuti che hai inviato in questa chat diventeranno '
            'non apribili per il destinatario. Procedere?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Revoca tutto')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AppServices.instance.revokeConversation(widget.conversationId);
      _snack('Contenuti revocati.');
    } catch (e) {
      _snack('Revoca non riuscita: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Protezione della chat')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _conv == null
              ? const LoadingView()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Le regole valgono per le FOTO. I testi sono sempre '
                        'visibili (cifrati E2E, senza limiti).',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                      title: const Text('Protezione foto attiva'),
                      subtitle: const Text(
                          'Se disattivata, le foto restano cifrate E2E ma '
                          'apribili senza limiti né scadenza.'),
                    ),
                    const Divider(),

                    // --- Aperture -------------------------------------------
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Numero di aperture',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    SwitchListTile(
                      value: _unlimitedOpens,
                      onChanged: _enabled
                          ? (v) => setState(() => _unlimitedOpens = v)
                          : null,
                      title: const Text('Aperture illimitate'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (!_unlimitedOpens)
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: _maxOpens.toDouble(),
                              min: 1,
                              max: 20,
                              divisions: 19,
                              label: '$_maxOpens',
                              onChanged: _enabled
                                  ? (v) =>
                                      setState(() => _maxOpens = v.round())
                                  : null,
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: Text('$_maxOpens',
                                textAlign: TextAlign.end,
                                style:
                                    Theme.of(context).textTheme.titleMedium),
                          ),
                        ],
                      ),
                    const Divider(),

                    // --- Durata ---------------------------------------------
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Durata dalla prima apertura',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    SwitchListTile(
                      value: _noExpiry,
                      onChanged: _enabled
                          ? (v) => setState(() => _noExpiry = v)
                          : null,
                      title: const Text('Senza scadenza'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (!_noExpiry)
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              enabled: _enabled,
                              initialValue: '$_durValue',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Valore'),
                              onChanged: (v) {
                                final n = int.tryParse(v);
                                if (n != null && n > 0) _durValue = n;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              initialValue: _durUnit,
                              decoration:
                                  const InputDecoration(labelText: 'Unità'),
                              onChanged: _enabled
                                  ? (v) => setState(
                                      () => _durUnit = v ?? 'secondi')
                                  : null,
                              items: _unitSeconds.keys
                                  .map((u) => DropdownMenuItem(
                                      value: u, child: Text(u)))
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: const Text('Salva'),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text('Revoca',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('La revoca agisce anche sui messaggi già inviati.',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _revokeAll,
                      style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                      icon: const Icon(Icons.block),
                      label: const Text('Revoca tutti i miei contenuti'),
                    ),
                    const SizedBox(height: 24),
                    const LimitsNote(),
                  ],
                ),
    );
  }
}
