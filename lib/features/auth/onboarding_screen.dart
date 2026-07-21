import 'package:flutter/material.dart';

import '../../core/app_services.dart';

/// Primo accesso: sceglie il nome visualizzato, genera la coppia di chiavi
/// (privata salvata solo sul dispositivo) e crea il profilo.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onCompleted});
  final VoidCallback onCompleted;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Inserisci un nome');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppServices.instance.createIdentity(name);
      widget.onCompleted();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Errore nella creazione del profilo: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crea il tuo profilo'),
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
                  Text('Come vuoi farti chiamare?',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Ora genereremo la tua coppia di chiavi. La chiave privata '
                    'resta solo su questo telefono e non viene mai caricata.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(labelText: 'Nome visualizzato'),
                    onSubmitted: (_) => _create(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: cs.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _loading ? null : _create,
                    icon: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.vpn_key),
                    label: const Text('Genera identità e continua'),
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
