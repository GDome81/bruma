import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_services.dart';
import '../../core/config.dart';
import '../../core/local_prefs.dart';
import '../../core/notifications.dart';
import '../../shared/widgets.dart';

/// Impostazioni di sicurezza: PIN di blocco (+ biometria su APK) e versione.
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _setPin() async {
    final pin = await _askPin('Nuovo PIN (min 4 cifre)');
    if (pin == null) return;
    if (pin.length < 4) {
      _snack('Il PIN deve avere almeno 4 cifre.');
      return;
    }
    final again = await _askPin('Ripeti il PIN');
    if (again == null) return;
    if (again != pin) {
      _snack('I PIN non coincidono.');
      return;
    }
    await AppServices.instance.setPin(pin);
    if (mounted) setState(() {});
    _snack('PIN impostato. L\'app si bloccherà in background.');
  }

  Future<void> _removePin() async {
    await AppServices.instance.disableLock();
    if (mounted) setState(() {});
    _snack('Blocco disattivato.');
  }

  Future<String?> _askPin(String title) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'PIN'),
          onSubmitted: (_) => Navigator.pop(ctx, c.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = LocalPrefs.appLockEnabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Sicurezza')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.pin),
            title: const Text('Blocco con PIN'),
            subtitle: Text(enabled
                ? 'Attivo · l\'app si blocca in background'
                : 'Disattivato'),
          ),
          if (!enabled)
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Imposta PIN'),
              onTap: _setPin,
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Cambia PIN'),
              onTap: _setPin,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Sblocco con biometria'),
              subtitle: Text(kIsWeb
                  ? 'Non disponibile sul web'
                  : 'Impronta/volto sull\'app Android'),
              value: LocalPrefs.lockUseBiometric,
              onChanged: kIsWeb
                  ? null
                  : (v) async {
                      await LocalPrefs.setLockUseBiometric(v);
                      setState(() {});
                    },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: const Text('Rimuovi PIN'),
              onTap: _removePin,
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Attiva notifiche'),
            subtitle: const Text(
                'Avvisi anonimi (🌙). Sul web arrivano mentre l\'app resta '
                'aperta anche in background.'),
            onTap: () async {
              await NotificationService.requestPermission();
              _snack('Se richiesto, consenti le notifiche dal browser/sistema.');
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: LimitsNote(),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('Versione build: ${AppConfig.shortBuild}',
                style: Theme.of(context).textTheme.labelSmall),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
