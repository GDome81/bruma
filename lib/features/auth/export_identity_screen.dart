import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_services.dart';

/// Esporta l'identità (chiave privata) come backup cifrato con una password.
/// Serve per usare la stessa identità su un altro dispositivo (Importa).
class ExportIdentityScreen extends StatefulWidget {
  const ExportIdentityScreen({super.key});

  @override
  State<ExportIdentityScreen> createState() => _ExportIdentityScreenState();
}

class _ExportIdentityScreenState extends State<ExportIdentityScreen> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  String? _result;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final p = _pw.text;
    if (p.length < 6) {
      setState(() => _error = 'La password deve avere almeno 6 caratteri.');
      return;
    }
    if (p != _pw2.text) {
      setState(() => _error = 'Le password non coincidono.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await Future<void>.delayed(Duration.zero); // fa disegnare lo spinner
    try {
      final r = AppServices.instance.exportIdentity(p);
      if (mounted) {
        setState(() {
          _result = r;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Errore: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Esporta identità')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Questo backup contiene la tua chiave privata. Chi lo ottiene '
              'INSIEME alla password può leggere i tuoi contenuti e impersonarti. '
              'Conservalo con cura e scegli una password robusta.',
              style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          if (_result == null) ...[
            TextField(
              controller: _pw,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password del backup'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pw2,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Ripeti password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock),
              label: Text(_busy ? 'Genero…' : 'Genera backup'),
            ),
          ] else ...[
            Text('Backup pronto', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                    data: _result!, size: 240, backgroundColor: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(_result!, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _result!));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Backup copiato.')));
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copia'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Share.share(_result!),
                    icon: const Icon(Icons.share),
                    label: const Text('Condividi'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Sull\'altro dispositivo: Importa identità → incolla o scansiona '
              'questo codice + la password.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
