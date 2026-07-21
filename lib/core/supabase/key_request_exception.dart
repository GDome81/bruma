/// Esito negativo di una richiesta di apertura (`request_key`).
enum KeyDenialReason { notFound, revoked, expired, limitReached, unknown }

class KeyRequestException implements Exception {
  KeyRequestException(this.reason, [this.raw]);
  final KeyDenialReason reason;
  final String? raw;

  /// Mappa il messaggio d'errore Postgres nella causa corrispondente.
  factory KeyRequestException.fromMessage(String message) {
    final m = message.toLowerCase();
    if (m.contains('not_found')) {
      return KeyRequestException(KeyDenialReason.notFound, message);
    }
    if (m.contains('revoked')) {
      return KeyRequestException(KeyDenialReason.revoked, message);
    }
    if (m.contains('expired')) {
      return KeyRequestException(KeyDenialReason.expired, message);
    }
    if (m.contains('limit')) {
      return KeyRequestException(KeyDenialReason.limitReached, message);
    }
    return KeyRequestException(KeyDenialReason.unknown, message);
  }

  String get userMessage {
    switch (reason) {
      case KeyDenialReason.revoked:
        return 'Il mittente ha revocato questo contenuto.';
      case KeyDenialReason.expired:
        return 'La finestra di visualizzazione è scaduta.';
      case KeyDenialReason.limitReached:
        return 'Hai esaurito le aperture disponibili.';
      case KeyDenialReason.notFound:
        return 'Contenuto non disponibile.';
      case KeyDenialReason.unknown:
        return 'Impossibile aprire il contenuto.';
    }
  }

  @override
  String toString() => 'KeyRequestException($reason, $raw)';
}
