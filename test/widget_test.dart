import 'package:flutter_test/flutter_test.dart';

import 'package:bruma/core/models/models.dart';
import 'package:bruma/shared/widgets.dart';

void main() {
  test('formatHms formatta minuti e secondi', () {
    expect(formatHms(const Duration(seconds: 5)), '00:05');
    expect(formatHms(const Duration(seconds: 65)), '01:05');
    expect(formatHms(const Duration(seconds: -3)), '00:00');
  });

  test('MessageAccess calcola aperture rimaste e apribilità', () {
    final a = MessageAccess(
      id: '1',
      messageId: 'm1',
      recipientId: 'r1',
      protectionEnabled: true,
      maxOpens: 3,
      maxDurationSeconds: 30,
      expiresAt: null,
      openCount: 1,
      active: true,
    );
    expect(a.remainingOpens, 2);
    expect(a.isOpenable, true);

    final revoked = MessageAccess(
      id: '2',
      messageId: 'm2',
      recipientId: 'r1',
      protectionEnabled: true,
      maxOpens: 3,
      maxDurationSeconds: 30,
      expiresAt: null,
      openCount: 0,
      active: false,
    );
    expect(revoked.isOpenable, false);
  });

  test('messageTypeFromString mappa i tipi', () {
    expect(messageTypeFromString('photo'), MessageType.photo);
    expect(messageTypeFromString('text'), MessageType.text);
  });
}
