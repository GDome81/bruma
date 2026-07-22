import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_services.dart';
import '../../core/local_prefs.dart';
import '../../core/models/models.dart';
import '../../core/notifications.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.requestPermission();
    _inbox = AppServices.instance.messages.subscribeInbox(_onMessage);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_inbox != null) AppServices.instance.client.removeChannel(_inbox!);
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
    NotificationService.showGenericMessage(
      silent: !LocalPrefs.notifSound,
      vibrate: LocalPrefs.notifVibrate,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
