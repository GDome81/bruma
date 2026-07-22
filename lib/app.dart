import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_services.dart';
import 'core/local_prefs.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/decoy_common.dart';
import 'features/auth/decoy_gallery_screen.dart';
import 'features/auth/decoy_moon_screen.dart';
import 'features/auth/decoy_screen.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/auth/panic_button.dart';
import 'features/auth/recovery_screen.dart';
import 'features/chats/chats_screen.dart';
import 'features/notifications/notification_host.dart';
import 'shared/theme.dart';
import 'shared/widgets.dart';

class BrumaApp extends StatefulWidget {
  const BrumaApp({super.key});

  @override
  State<BrumaApp> createState() => _BrumaAppState();
}

class _BrumaAppState extends State<BrumaApp> with WidgetsBindingObserver {
  // Vero se in questo ciclo l'app è andata DAVVERO in background (hidden/
  // paused), non solo un blur transitorio (inactive).
  bool _wentBackground = false;
  // Vero se la calcolatrice è stata mostrata dal ciclo di vita (per poterla
  // togliere al ritorno da un blur transitorio senza chiedere il PIN, ma senza
  // toccare un panic attivato a mano dal pulsante).
  bool _coverSetByLifecycle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = AppServices.instance;
    // Senza PIN l'app NON si nasconde (scelta dell'utente): la calcolatrice si
    // mostra solo col pulsante panic.
    if (!s.lockEnabled) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      // Copri SUBITO con la calcolatrice — anche solo su `inactive` — così
      // l'anteprima nella gallery delle app recenti mostra la calcolatrice e
      // non le chat (è lì che Android scatta l'istantanea).
      if (state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused) {
        _wentBackground = true;
      }
      if (!s.panicMode.value) {
        s.setPanic(true);
        _coverSetByLifecycle = true;
      }
    } else if (state == AppLifecycleState.resumed) {
      // Se è stato solo un blur transitorio (mai andata davvero in background)
      // e la copertura l'avevamo messa noi, toglila senza chiedere il PIN.
      // Se invece è andata in background, la calcolatrice resta → serve il PIN.
      if (!_wentBackground && _coverSetByLifecycle && s.panicMode.value) {
        s.setPanic(false);
      }
      _wentBackground = false;
      _coverSetByLifecycle = false;
    }
  }

  /// La maschera scelta dall'utente (Impostazioni → Sicurezza → Maschera).
  Widget _decoy() {
    switch (decoyTypeFromString(LocalPrefs.decoyType)) {
      case DecoyType.moonPhase:
        return const DecoyMoonScreen();
      case DecoyType.gallery:
        return const DecoyGalleryScreen();
      case DecoyType.calculator:
        return const DecoyScreen();
    }
  }

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
      // Il panic button resta sopra qualunque schermata/route; quando il panic
      // è attivo il decoy (calcolatrice) copre TUTTO senza disconnettere, così
      // sbloccando si torna all'app già loggata.
      builder: (context, child) => Stack(
        children: [
          ?child,
          const PanicButton(),
          ValueListenableBuilder<bool>(
            valueListenable: AppServices.instance.panicMode,
            builder: (_, panic, _) => panic
                ? Positioned.fill(child: _decoy())
                : const SizedBox.shrink(),
          ),
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
      // Il decoy (in caso di panic) è gestito come overlay globale in
      // MaterialApp.builder: qui basta login vs area autenticata.
      return const AuthScreen();
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
        return const NotificationHost(child: ChatsScreen());
      },
    );
  }
}
