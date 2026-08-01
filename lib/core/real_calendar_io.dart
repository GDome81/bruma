import 'package:flutter/services.dart';

/// Un impegno reale letto dal calendario del dispositivo.
class RealEvent {
  RealEvent(this.day, this.title);

  /// Giorno normalizzato a mezzanotte locale.
  final DateTime day;
  final String title;
}

/// Canale nativo implementato in MainActivity.kt.
///
/// NB: qui NON si usa il plugin device_calendar di proposito. Quel plugin
/// considera i permessi concessi solo se ha ANCHE WRITE_CALENDAR
/// (`arePermissionsGranted = write && read`), quindi con la sola lettura
/// risponderebbe sempre "negato". Il canale nativo chiede e usa esclusivamente
/// READ_CALENDAR: Bruma non scrive mai nel calendario del telefono.
const _channel = MethodChannel('bruma/calendar');

Future<bool> hasCalendarPermission() async {
  try {
    return await _channel.invokeMethod<bool>('hasPermission') ?? false;
  } catch (_) {
    return false;
  }
}

Future<bool> requestCalendarPermission() async {
  try {
    return await _channel.invokeMethod<bool>('requestPermission') ?? false;
  } catch (_) {
    return false;
  }
}

/// Impegni reali fra [from] e [to]. SOLA LETTURA. Ritorna vuoto se il permesso
/// manca o qualcosa va storto: la maschera non deve mai rompersi.
Future<List<RealEvent>> readCalendarEvents(DateTime from, DateTime to) async {
  try {
    final rows = await _channel.invokeListMethod<Object?>('readEvents', {
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
    });
    if (rows == null) return const [];
    final out = <RealEvent>[];
    for (final r in rows) {
      if (r is! Map) continue;
      final title = (r['title'] as String?)?.trim();
      final begin = (r['begin'] as num?)?.toInt();
      if (title == null || title.isEmpty || begin == null) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(begin);
      out.add(RealEvent(DateTime(d.year, d.month, d.day), title));
    }
    return out;
  } catch (_) {
    return const [];
  }
}
