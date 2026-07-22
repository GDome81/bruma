import 'package:flutter/widgets.dart';

import '../../core/app_services.dart';

/// Tipo di "maschera" con cui l'app si presenta quando è bloccata.
enum DecoyType { calculator, moonPhase, gallery }

DecoyType decoyTypeFromString(String? s) {
  switch (s) {
    case 'moonPhase':
      return DecoyType.moonPhase;
    case 'gallery':
      return DecoyType.gallery;
    default:
      return DecoyType.calculator;
  }
}

String decoyTypeToString(DecoyType t) => t.name;

String decoyTypeLabel(DecoyType t) {
  switch (t) {
    case DecoyType.calculator:
      return 'Calcolatrice';
    case DecoyType.moonPhase:
      return 'Fasi lunari';
    case DecoyType.gallery:
      return 'Galleria foto';
  }
}

/// Logica di sblocco condivisa da tutte le maschere: PIN, long-press e
/// biometria (APK) si comportano in modo identico ovunque.
mixin DecoyUnlockMixin<T extends StatefulWidget> on State<T> {
  /// Rimuove la maschera e mostra l'app/login sottostante.
  void unlock() => AppServices.instance.setPanic(false);

  /// Long-press: sblocca se non c'è un PIN; con PIN + biometria (APK) prova il
  /// prompt biometrico; con PIN e senza biometria non fa nulla (serve il PIN).
  Future<void> longPressUnlock() async {
    final s = AppServices.instance;
    if (!s.lockEnabled) {
      unlock();
      return;
    }
    if (s.biometricUnlockEnabled) {
      final ok = await s.authenticateBiometric();
      if (ok) unlock();
    }
  }

  /// Se [text] è il PIN corretto sblocca e ritorna true (usato dai campi di
  /// testo delle maschere non-calcolatrice).
  bool submitPin(String text) {
    if (AppServices.instance.verifyPin(text.trim())) {
      unlock();
      return true;
    }
    return false;
  }
}
