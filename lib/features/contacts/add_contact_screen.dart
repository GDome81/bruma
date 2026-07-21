import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_services.dart';
import '../../shared/widgets.dart';
import 'qr_scan_screen.dart';

/// Mostra il proprio codice invito (testo + QR + condividi) e consente di
/// aggiungere un contatto inserendo/scansionando il codice altrui.
class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  late Future<String> _codeFuture;
  final _input = TextEditingController();
  bool _redeeming = false;

  @override
  void initState() {
    super.initState();
    _codeFuture = AppServices.instance.contacts.getOrCreateMyInviteCode();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _mapError(String message) {
    final m = message.toLowerCase();
    if (m.contains('invalid_code')) return 'Codice non valido.';
    if (m.contains('cannot_add_self')) {
      return 'Non puoi aggiungere te stesso.';
    }
    if (m.contains('not_authenticated')) return 'Sessione scaduta.';
    return 'Errore: $message';
  }

  Future<void> _redeem(String code) async {
    final c = code.trim();
    if (c.isEmpty) {
      _snack('Inserisci un codice.');
      return;
    }
    setState(() => _redeeming = true);
    try {
      final res = await AppServices.instance.contacts.redeemInvite(c);
      if (mounted) Navigator.of(context).pop(res.conversationId);
    } on PostgrestException catch (e) {
      _snack(_mapError(e.message));
    } catch (e) {
      _snack('Errore: $e');
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (code != null) await _redeem(code);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Aggiungi contatto')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Il tuo codice invito',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          FutureBuilder<String>(
            future: _codeFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: LoadingView(),
                );
              }
              if (snap.hasError) {
                return ErrorView(message: 'Errore: ${snap.error}');
              }
              final code = snap.data!;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(12),
                        child: QrImageView(
                          data: code,
                          size: 200,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SelectableText(
                        code,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(letterSpacing: 2),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: code));
                              _snack('Codice copiato.');
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copia'),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => Share.share(
                                'Aggiungimi su Bruma con il codice: $code'),
                            icon: const Icon(Icons.share),
                            label: const Text('Condividi'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Text('Aggiungi un contatto',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Inserisci il codice ricevuto o scansiona il suo QR.',
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Codice invito',
              hintText: 'BRU-XXXX-XXXX',
            ),
            onSubmitted: _redeem,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _redeeming ? null : () => _redeem(_input.text),
                  icon: _redeeming
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.person_add_alt_1),
                  label: const Text('Aggiungi'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _redeeming ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scansiona'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
