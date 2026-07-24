import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Cambia icona + nome dell'app nel launcher (SOLO Android) scegliendo tra
/// alcuni "travestimenti" preconfigurati (activity-alias nel manifest). No-op
/// su web (il nome/icona di una PWA sono fissati all'installazione).
class AppIcon {
  static const _channel = MethodChannel('bruma/app_icon');

  /// Travestimenti disponibili: alias tecnico ↔ etichetta mostrata.
  static const presets = <AppIconPreset>[
    AppIconPreset('BrumaDefault', 'Bruma'),
    AppIconPreset('MaskCalc', 'Calcolatrice'),
    AppIconPreset('MaskMeteo', 'Meteo'),
    AppIconPreset('MaskNote', 'Note'),
    AppIconPreset('MaskPromemoria', 'Promemoria'),
  ];

  /// Attiva l'alias [alias] (uno di [presets].alias) e disattiva gli altri.
  static Future<void> setAlias(String alias) async {
    if (kIsWeb) return;
    await _channel.invokeMethod<void>('setAlias', {'alias': alias});
  }
}

class AppIconPreset {
  const AppIconPreset(this.alias, this.label);
  final String alias;
  final String label;
}
