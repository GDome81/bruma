import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_services.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/biometric_gate.dart';
import 'features/auth/decoy_screen.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/auth/panic_button.dart';
import 'features/auth/recovery_screen.dart';
import 'features/chats/chats_screen.dart';
import 'features/notifications/notification_host.dart';
import 'shared/theme.dart';
import 'shared/widgets.dart';

class BrumaApp extends StatelessWidget {
  const BrumaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bruma',
      debugShowCheckedModeBanner: false,
      navigatorKey: AppServices.instance.navigatorKey,
      theme: BrumaTheme.light(),
      darkTheme: BrumaTheme.dark(),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
      // Il panic button resta sopra qualunque schermata/route.
      builder: (context, child) => Stack(
        children: [
          ?child,
          const PanicButton(),
        ],
      ),
    );
  }
}

/// Decide tra schermata di autenticazione e area autenticata, reagendo
/// ai cambi di sessione.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = AppServices.instance.auth.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppServices.instance.auth.currentSession;
    if (session == null) {
      // Logout normale → login; dopo un panic → decoy (calcolatrice).
      return ValueListenableBuilder<bool>(
        valueListenable: AppServices.instance.panicMode,
        builder: (_, panic, _) =>
            panic ? const DecoyScreen() : const AuthScreen(),
      );
    }
    return IdentityGate(key: ValueKey(session.user.id));
  }
}

/// Con sessione attiva: risolve identita' locale + profilo remoto e instrada
/// verso onboarding, recupero identita' o home.
class IdentityGate extends StatefulWidget {
  const IdentityGate({super.key});

  @override
  State<IdentityGate> createState() => _IdentityGateState();
}

class _IdentityGateState extends State<IdentityGate> {
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = AppServices.instance.refreshIdentity();
  }

  void _reload() {
    setState(() {
      _future = AppServices.instance.refreshIdentity();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: LoadingView(label: 'Carico l\'identità…'));
        }
        if (snap.hasError) {
          return Scaffold(
            body: ErrorView(
              message: 'Errore di avvio: ${snap.error}',
              onRetry: _reload,
            ),
          );
        }
        final s = AppServices.instance;
        if (!s.hasProfile) {
          return OnboardingScreen(onCompleted: _reload);
        }
        if (!s.hasLocalIdentity) {
          return RecoveryScreen(onCompleted: _reload);
        }
        return const NotificationHost(
          child: BiometricGate(child: ChatsScreen()),
        );
      },
    );
  }
}
