import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/app_services.dart';
import '../../core/local_prefs.dart';
import '../../shared/bruma_logo.dart';

/// Blocca l'app con PIN (+ biometria su APK) all'avvio e ogni volta che torna
/// in foreground dal background. Su APK FLAG_SECURE rende nera l'anteprima nei
/// recenti (gestito da AppServices.applyLockFlagSecure).
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = AppServices.instance.lockEnabled;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!AppServices.instance.lockEnabled) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (mounted && !_locked) setState(() => _locked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppServices.instance.lockEnabled || !_locked) return widget.child;
    return _LockScreen(onUnlocked: () => setState(() => _locked = false));
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  final _pin = TextEditingController();
  final _auth = LocalAuthentication();
  String? _error;
  bool _busy = false;

  bool get _canBiometric => !kIsWeb && LocalPrefs.lockUseBiometric;

  @override
  void initState() {
    super.initState();
    if (_canBiometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    await Future<void>.delayed(Duration.zero);
    final ok = AppServices.instance.verifyPin(_pin.text);
    if (ok) {
      widget.onUnlocked();
      return;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = 'PIN errato';
        _pin.clear();
      });
    }
  }

  Future<void> _biometric() async {
    if (!_canBiometric) return;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Sblocca Bruma',
        options: const AuthenticationOptions(
            stickyAuth: true, biometricOnly: true),
      );
      if (ok) widget.onUnlocked();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrumaLogo(size: 84),
                  const SizedBox(height: 16),
                  Text('Bruma è bloccata',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8),
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: cs.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: const Text('Sblocca'),
                  ),
                  if (_canBiometric) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _biometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Usa biometria'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
