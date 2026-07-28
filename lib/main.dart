import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/app_services.dart';
import 'core/config.dart';
import 'core/fcm.dart';
import 'core/local_prefs.dart';
import 'core/notifications.dart';
import 'shared/theme.dart';
import 'shared/widgets.dart';

/// Oltre questo tempo una chiamata di avvio è considerata "server lento / non
/// raggiungibile": si mostra un errore chiaro con "Riprova" invece di restare
/// per sempre sulla schermata iniziale.
const _startupTimeout = Duration(seconds: 20);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isConfigured) {
    runApp(const _ConfigErrorApp());
    return;
  }

  // Avvia SUBITO. L'inizializzazione (che tocca la rete e a volte è lenta lato
  // server) avviene dentro _BootstrapApp, che mostra lo stato passo-passo e, se
  // il server non risponde entro il timeout, un messaggio chiaro con "Riprova"
  // — invece di lasciare l'utente bloccato sulla schermata iniziale.
  runApp(const _BootstrapApp());
}

/// Esegue l'inizializzazione asincrona mostrando lo stato, poi cede il posto a
/// [BrumaApp] (che si apre già travestita). Finché non è pronta mostra solo un
/// loader neutro / un errore con "Riprova": nessun contenuto dell'app, quindi
/// il travestimento non viene svelato (come già faceva lo splash di sistema).
class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();
  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  final ValueNotifier<String> _status = ValueNotifier<String>('Avvio…');
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _ready = false;
    });
    try {
      _status.value = 'Connessione al server…';
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        // La anon key (JWT) è accettata anche dal parametro publishableKey.
        publishableKey: AppConfig.supabaseAnonKey,
      ).timeout(_startupTimeout);

      _status.value = 'Inizializzazione…';
      await AppServices.init();
      await LocalPrefs.init();

      // Bruma si apre SEMPRE travestita (maschera scelta in Impostazioni, di
      // default la calcolatrice) — anche al primo accesso e senza PIN. Va
      // impostato PRIMA di mostrare BrumaApp, così la sua prima schermata è già
      // la maschera. Si entra col PIN + "=" oppure con un long press.
      // (applyLockFlagSecure legge LocalPrefs → dev'essere già inizializzato.)
      AppServices.instance.panicMode.value = true;
      AppServices.instance.applyLockFlagSecure();

      _status.value = 'Quasi pronto…';
      await NotificationService.init();
      // FCM: solo Android, no-op su web, best-effort → non deve bloccare l'avvio.
      unawaited(initFcm());

      if (mounted) setState(() => _ready = true);
    } on TimeoutException {
      if (mounted) {
        setState(() => _error =
            'Il server non risponde (timeout). Controlla la connessione e riprova.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Errore di avvio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const BrumaApp();
    return MaterialApp(
      title: 'Bruma',
      debugShowCheckedModeBanner: false,
      theme: BrumaTheme.light(),
      darkTheme: BrumaTheme.dark(),
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: _error != null
            ? ErrorView(message: _error!, onRetry: _run)
            : ValueListenableBuilder<String>(
                valueListenable: _status,
                builder: (_, s, _) => LoadingView(label: s),
              ),
      ),
    );
  }
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
