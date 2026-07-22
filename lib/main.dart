import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/app_services.dart';
import 'core/config.dart';
import 'core/local_prefs.dart';
import 'core/notifications.dart';
import 'shared/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isConfigured) {
    runApp(const _ConfigErrorApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    // La anon key (JWT) è accettata anche dal parametro publishableKey.
    publishableKey: AppConfig.supabaseAnonKey,
  );
  await AppServices.init();
  await AppServices.instance.refreshIdentity();
  await LocalPrefs.init();
  await NotificationService.init();
  // Se è impostato un PIN, Bruma si apre già "bloccata" come calcolatrice: si
  // sblocca digitando il PIN e "=". Senza PIN l'app si apre normalmente e la
  // calcolatrice appare solo col tasto panic (che poi si sblocca col long-press).
  AppServices.instance.panicMode.value = AppServices.instance.lockEnabled;
  // Con il PIN attivo applica subito FLAG_SECURE (anteprima nera nei recenti
  // su Android).
  AppServices.instance.applyLockFlagSecure();

  runApp(const BrumaApp());
}

class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bruma',
      theme: BrumaTheme.light(),
      darkTheme: BrumaTheme.dark(),
      home: Scaffold(
        appBar: AppBar(title: const Text('Bruma — configurazione')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SingleChildScrollView(
              child: SelectableText(AppConfig.missingConfigMessage),
            ),
          ),
        ),
      ),
    );
  }
}
