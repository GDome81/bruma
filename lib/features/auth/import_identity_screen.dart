import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../contacts/qr_scan_screen.dart';

/// Importa un'identità da un backup (Esporta identità) + password. Usato su un
/// nuovo dispositivo per usare la STESSA identità e rileggere i contenuti.
class ImportIdentityScreen extends StatefulWidget {
  const ImportIdentityScreen({super.key, required this.onCompleted});
  final VoidCallback onCompleted;

  @override
  State<ImportIdentityScreen> createState() => _ImportIdentityScreenState();
}

class _ImportIdentityScreenState extends State<ImportIdentityScreen> {
  final _data = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _data.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (code != null) setState(() => _data.text = code);
  }

  Future<void> _import() async {
    if (_data.text.trim().isEmpty || _pw.text.isEmpty) {
      setState(() => _error = 'Inserisci il backup e la password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await Future<void>.delayed(Duration.zero);
    try {
      await AppServices.instance.importIdentity(_data.text, _pw.text);
      if (!mounted) return;
      final done = widget.onCompleted;
      Navigator.of(context).pop(); // chiude questa schermata (basta un tap)
      done();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Password errata o backup non valido.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Importa identità')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Incolla o scansiona il backup creato con "Esporta identità" '
            'sull\'altro dispositivo, poi inserisci la password.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _data,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Backup (BRUMA1:...)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scansiona QR'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pw,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password del backup'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _import,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: Text(_busy ? 'Importo…' : 'Importa'),
          ),
          const SizedBox(height: 16),
          Text(
            'Nota: importando, la chiave pubblica del profilo verrà allineata a '
            'questa identità. I contenuti cifrati per l\'identità precedente su '
            'questo dispositivo non saranno più apribili.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
