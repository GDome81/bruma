import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/local_prefs.dart';

/// Blocco biometrico: se attivo (e non su web), richiede sblocco con
/// impronta/volto/PIN all'avvio e al ritorno in foreground.
class BiometricGate extends StatefulWidget {
  const BiometricGate({super.key, required this.child});
  final Widget child;

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate>
    with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  bool _unlocked = false;
  bool _authing = false;

  bool get _lockActive => !kIsWeb && LocalPrefs.biometricEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_lockActive) {
      _unlocked = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_lockActive) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (mounted) setState(() => _unlocked = false);
    } else if (state == AppLifecycleState.resumed) {
      if (!_unlocked) _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (_authing || _unlocked) return;
    setState(() => _authing = true);
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Sblocca Bruma',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // consente il fallback a PIN/sequenza
        ),
      );
      if (mounted) {
        setState(() {
          _unlocked = ok;
          _authing = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _authing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_lockActive || _unlocked) return widget.child;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            Text('Bruma è bloccata',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _authing ? null : _authenticate,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Sblocca'),
            ),
          ],
        ),
      ),
    );
  }
}
