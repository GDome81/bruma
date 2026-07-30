import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_services.dart';
import '../../core/local_prefs.dart';
import '../../core/models/models.dart';
import '../../core/notifications.dart';
import 'notifications_screen.dart';

/// Avvia le notifiche locali per l'utente autenticato: chiede il permesso e,
/// quando arriva un messaggio da altri mentre l'app NON è in primo piano,
/// mostra una notifica generica.
class NotificationHost extends StatefulWidget {
  const NotificationHost({super.key, required this.child});
  final Widget child;

  @override
  State<NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends State<NotificationHost>
    with WidgetsBindingObserver {
  RealtimeChannel? _inbox;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  StreamSubscription? _reqSub;
  Set<String> _seenReqIds = {};
  bool _reqFirst = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.requestPermission();
    _inbox = AppServices.instance.messages.subscribeInbox(_onMessage);
    // Richieste in arrivo di riapertura contenuti → avviso in-app.
    _reqSub =
        AppServices.instance.requests.watchIncoming().listen(_onRequests);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_inbox != null) AppServices.instance.client.removeChannel(_inbox!);
    _reqSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }

  void _onMessage(Message m) {
    // Notifica solo per messaggi ALTRUI e solo se l'app non è in primo piano
    // (in foreground la UI si aggiorna già dal vivo).
    if (m.senderId == AppServices.instance.uid) return;
    if (_lifecycle == AppLifecycleState.resumed) return;
    // Chat silenziata → niente notifica.
    if (LocalPrefs.isChatMuted(m.conversationId)) return;
    // Su APK Android le notifiche in background le mostra FCM (system tray):
    // qui NON mostriamo nulla, altrimenti nella finestra "background ma
    // processo/socket ancora vivo" si avrebbero DUE 🌙. Sul web (nessun FCM)
    // resta il realtime a mostrarle.
    if (!kIsWeb) return;
    NotificationService.showGenericMessage(
      silent: !LocalPrefs.notifSound,
      vibrate: LocalPrefs.notifVibrate,
      title: LocalPrefs.effectiveNotifTitle,
      body: LocalPrefs.effectiveNotifBody,
    );
  }

  void _onRequests(List<ContentRequest> list) {
    final ids = list.map((r) => r.id).toSet();
    // Al primo evento memorizzo le richieste già presenti senza avvisare
    // (altrimenti a ogni avvio si riproporrebbero le vecchie).
    if (_reqFirst) {
      _seenReqIds = ids;
      _reqFirst = false;
      return;
    }
    final fresh = list.where((r) => !_seenReqIds.contains(r.id)).toList();
    _seenReqIds = ids;
    if (fresh.isEmpty || !mounted) return;
    // Sotto la maschera (panic) NON mostro nulla: svelerebbe l'app.
    if (AppServices.instance.panicMode.value) return;
    final n = fresh.length;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      // ✕ per chiuderlo subito: a volte restava sullo schermo dando fastidio.
      showCloseIcon: true,
      content: Text(n == 1
          ? 'Nuova richiesta di riapertura di un contenuto.'
          : '$n nuove richieste di riapertura.'),
      action: SnackBarAction(
        label: 'Vedi',
        onPressed: () => AppServices.instance.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
