import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';

/// Pulsante "panic" globale: linguetta discreta sul bordo sinistro, visibile
/// sopra qualunque schermata quando si è loggati. Tocco → nasconde tutto
/// (decoy) e disconnette (serve re-login).
class PanicButton extends StatefulWidget {
  const PanicButton({super.key});

  @override
  State<PanicButton> createState() => _PanicButtonState();
}

class _PanicButtonState extends State<PanicButton> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = AppServices.instance.auth
        .authStateChanges()
        .listen((_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Solo quando autenticati (non sul decoy/login).
    if (AppServices.instance.auth.currentSession == null) {
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(context);
    return Positioned(
      left: 0,
      top: media.size.height * 0.42,
      child: GestureDetector(
        onTap: () {
          // Chiude tutte le schermate aperte, poi mostra il decoy + logout.
          AppServices.instance.navigatorKey.currentState
              ?.popUntil((r) => r.isFirst);
          AppServices.instance.panic();
        },
        child: Opacity(
          opacity: 0.45,
          child: Container(
            width: 26,
            height: 54,
            decoration: const BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: const Icon(Icons.visibility_off,
                size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
