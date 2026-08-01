import 'package:device_calendar/device_calendar.dart';

/// Un impegno reale letto dal calendario del dispositivo.
class RealEvent {
  RealEvent(this.day, this.title);

  /// Giorno normalizzato a mezzanotte locale.
  final DateTime day;
  final String title;
}

final _plugin = DeviceCalendarPlugin();

Future<bool> hasCalendarPermission() async {
  try {
    final r = await _plugin.hasPermissions();
    return r.isSuccess && r.data == true;
  } catch (_) {
    return false;
  }
}

/// Chiede il permesso Calendario (solo lettura, vedi manifest).
Future<bool> requestCalendarPermission() async {
  try {
    final r = await _plugin.requestPermissions();
    return r.isSuccess && r.data == true;
  } catch (_) {
    return false;
  }
}

/// Impegni reali fra [from] e [to]. SOLA LETTURA: non scrive né modifica nulla.
/// Ritorna vuoto se il permesso manca o qualcosa va storto: la maschera non deve
/// mai rompersi per il calendario.
Future<List<RealEvent>> readCalendarEvents(
    DateTime from, DateTime to) async {
  try {
    if (!await hasCalendarPermission()) return const [];
    final cals = await _plugin.retrieveCalendars();
    final list = cals.data;
    if (list == null || list.isEmpty) return const [];
    final out = <RealEvent>[];
    for (final c in list) {
      final id = c.id;
      if (id == null) continue;
      final res = await _plugin.retrieveEvents(
        id,
        RetrieveEventsParams(startDate: from, endDate: to),
      );
      for (final e in res.data ?? const <Event>[]) {
        final s = e.start;
        final t = (e.title ?? '').trim();
        if (s == null || t.isEmpty) continue;
        out.add(RealEvent(DateTime(s.year, s.month, s.day), t));
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}
