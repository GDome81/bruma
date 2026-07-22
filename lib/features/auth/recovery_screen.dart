import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import 'import_identity_screen.dart';

/// Mostrata quando esiste un profilo remoto ma la chiave privata non e'
/// presente su questo dispositivo (nuovo telefono o dati app cancellati).
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, required this.onCompleted});
  final VoidCallback onCompleted;

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _regenerate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppServices.instance.regenerateIdentity();
      widget.onCompleted();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Errore: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Identità non trovata'),
        actions: [
          TextButton(
            onPressed: () => AppServices.instance.signOut(),
            child: const Text('Esci'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.key_off, size: 56, color: cs.error),
                  const SizedBox(height: 16),
                  Text('La chiave privata non è su questo dispositivo',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(
                    'Se hai un BACKUP dell\'identità (Esporta identità da un '
                    'altro dispositivo), importalo qui per rivedere i tuoi '
                    'contenuti. Altrimenti puoi generare una nuova identità: '
                    'potrai inviare/ricevere nuovi contenuti, ma quelli '
                    'precedenti non saranno più apribili.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: cs.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ImportIdentityScreen(
                                    onCompleted: widget.onCompleted),
                              ),
                            ),
                    icon: const Icon(Icons.download),
                    label: const Text('Importa identità (da backup)'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _regenerate,
                    icon: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.autorenew),
                    label: const Text('Genera una nuova identità'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
