// Nessun calendario di sistema fuori da Android/iOS (web): no-op.

/// Un impegno reale letto dal calendario del dispositivo.
class RealEvent {
  RealEvent(this.day, this.title);

  /// Giorno normalizzato a mezzanotte locale.
  final DateTime day;
  final String title;
}

Future<bool> hasCalendarPermission() async => false;

Future<bool> requestCalendarPermission() async => false;

Future<List<RealEvent>> readCalendarEvents(DateTime from, DateTime to) async =>
    const [];
