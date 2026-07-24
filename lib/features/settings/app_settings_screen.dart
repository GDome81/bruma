import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_services.dart';
import '../../core/config.dart';
import '../../core/local_prefs.dart';
import '../../shared/widgets.dart';
import '../auth/decoy_common.dart';
import '../tutorial/tutorial_screen.dart';

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
    _snack('PIN impostato. Bruma ora si apre come calcolatrice: '
        'digita il PIN e "=" per sbloccare.');
  }

  Future<void> _removePin() async {
    await AppServices.instance.disableLock();
    if (mounted) setState(() {});
    _snack('Blocco disattivato.');
  }

  IconData _decoyIcon(DecoyType t) {
    switch (t) {
      case DecoyType.calculator:
        return Icons.calculate_outlined;
      case DecoyType.moonPhase:
        return Icons.nightlight_round;
      case DecoyType.gallery:
        return Icons.photo_library_outlined;
    }
  }

  Future<void> _toggleBiometric(bool v) async {
    if (v) {
      final ok = await AppServices.instance.deviceHasBiometrics();
      if (!ok) {
        _snack('Nessuna impronta/volto configurati su questo dispositivo.');
        return;
      }
    }
    await LocalPrefs.setLockUseBiometric(v);
    if (mounted) setState(() {});
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

  Future<void> _editNotifText() async {
    final titleC = TextEditingController(text: LocalPrefs.notifTitle ?? '');
    final bodyC = TextEditingController(text: LocalPrefs.notifBody ?? '');
    // [titolo, testo] — il primo (vuoto) è il default anonimo 🌙.
    const presets = <List<String>>[
      ['', ''],
      ['Promemoria', 'Hai un promemoria'],
      ['Meteo', 'Aggiornamento disponibile'],
      ['Note', 'Nota aggiornata'],
      ['🔔', ''],
    ];
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Testo notifica'),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Scegli un preset o scrivi il tuo. Lascia vuoto per la '
                    'notifica anonima 🌙.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final p in presets)
                      ActionChip(
                        label: Text(p[0].isEmpty ? '🌙 Default' : p[0]),
                        onPressed: () => setLocal(() {
                          titleC.text = p[0];
                          bodyC.text = p[1];
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: titleC,
                  decoration: const InputDecoration(labelText: 'Titolo'),
                ),
                TextField(
                  controller: bodyC,
                  decoration: const InputDecoration(labelText: 'Testo'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salva')),
        ],
      ),
    );
    if (saved == true) {
      await AppServices.instance
          .setNotifText(titleC.text.trim(), bodyC.text.trim());
      if (mounted) setState(() {});
      _snack('Testo notifica aggiornato.');
    }
    titleC.dispose();
    bodyC.dispose();
  }

  Future<void> _makeCanonical() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usare questa chiave per l\'account?'),
        content: const Text(
            'Da adesso i nuovi messaggi verranno cifrati per la chiave di '
            'QUESTO dispositivo, che tornerà quindi ad aprirli. Gli altri tuoi '
            'dispositivi smetteranno di aprire i messaggi nuovi finché non vi '
            'importi questa stessa identità. I messaggi già esistenti non '
            'cambiano.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Conferma')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AppServices.instance.makeThisDeviceCanonical();
      if (mounted) setState(() {});
      _snack('Fatto: questo dispositivo è ora la chiave dell\'account.');
    } catch (e) {
      _snack('Operazione non riuscita: $e');
    }
  }

  Widget _identitySection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = AppServices.instance;
    final matches = s.deviceKeyMatchesAccount;
    final fp = s.fingerprintOf(s.localPublicKeyB64);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child:
              Text('Identità', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ListTile(
          leading: const Icon(Icons.fingerprint),
          title: const Text('Impronta di questo dispositivo'),
          subtitle: Text('$fp\n\nDeve essere IDENTICA su tutti i tuoi '
              'dispositivi (APK e web) dello stesso account.'),
          isThreeLine: true,
        ),
        if (!matches)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Questo dispositivo usa una chiave NON più allineata '
                    'all\'account: i messaggi nuovi potrebbero non aprirsi qui. '
                    'Usa la chiave di questo dispositivo per l\'account (sotto), '
                    'oppure importa qui l\'identità corretta.',
                    style: TextStyle(color: cs.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ListTile(
          leading: Icon(Icons.vpn_key, color: cs.primary),
          title: const Text('Usa questa chiave per l\'account'),
          subtitle: const Text(
              'Rende questo dispositivo quello "ufficiale": i nuovi messaggi '
              'verranno cifrati per la sua chiave. Gli altri dispositivi '
              'dovranno importare questa identità.'),
          onTap: _makeCanonical,
        ),
      ],
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
                ? 'Attivo · l\'app si apre come calcolatrice; sblocca col PIN e "="'
                : 'Disattivato · l\'app si apre normalmente'),
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
            if (!kIsWeb)
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Sblocco con impronta/volto'),
                subtitle: const Text(
                    'Solo app Android. Tieni premuto sul display della '
                    'calcolatrice per usarla; il PIN resta come alternativa.'),
                value: LocalPrefs.lockUseBiometric,
                onChanged: _toggleBiometric,
              ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: const Text('Rimuovi PIN'),
              onTap: _removePin,
            ),
          ],
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Maschera',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Come si presenta Bruma quando è bloccata.',
                style: TextStyle(fontSize: 13)),
          ),
          ...DecoyType.values.map((t) {
            final selected = decoyTypeFromString(LocalPrefs.decoyType) == t;
            return ListTile(
              leading: Icon(_decoyIcon(t)),
              title: Text(decoyTypeLabel(t)),
              trailing: selected
                  ? Icon(Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () async {
                await LocalPrefs.setDecoyType(decoyTypeToString(t));
                if (mounted) setState(() {});
              },
            );
          }),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Attiva notifiche'),
            subtitle: const Text(
                'Avvisi anonimi (🌙). Sul web arrivano mentre l\'app resta '
                'aperta anche in background.'),
            onTap: () async {
              final msg = await AppServices.instance.enablePush();
              _snack(msg);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Suono'),
            subtitle: const Text(
                'Notifiche con suono. Spento = silenziose. (Suoneria '
                'personalizzata solo su app Android.)'),
            value: LocalPrefs.notifSound,
            onChanged: (v) async {
              await AppServices.instance.setNotifSound(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Vibrazione'),
            value: LocalPrefs.notifVibrate,
            onChanged: (v) async {
              await AppServices.instance.setNotifVibrate(v);
              setState(() {});
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
                'Puoi silenziare una singola chat dal menu ⋮ dentro la '
                'conversazione.',
                style: TextStyle(fontSize: 12)),
          ),
          ListTile(
            leading: const Icon(Icons.edit_notifications_outlined),
            title: const Text('Testo notifica'),
            subtitle: Text(
                'Come appare l\'avviso: "${LocalPrefs.effectiveNotifTitle}" · '
                '${LocalPrefs.effectiveNotifBody}\n'
                'Personalizzalo per mascherare (vuoto = 🌙 anonimo).'),
            isThreeLine: true,
            onTap: _editNotifText,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('Rivedi tutorial'),
            subtitle: const Text('Come funziona Bruma: maschera, backup, chat.'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => const TutorialScreen(),
            )),
          ),
          const Divider(),
          _identitySection(context),
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
