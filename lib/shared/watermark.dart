import 'package:flutter/material.dart';

import '../core/app_services.dart';

/// Sovrappone un watermark ripetuto e trasparente (nome di chi guarda + data/
/// ora) sul contenuto mostrato. Se il destinatario fa uno screenshot o
/// fotografa lo schermo con un'altra fotocamera (l'unico modo di aggirare
/// FLAG_SECURE), l'immagine trafugata resta tracciabile a lui → deterrente.
///
/// NB: il watermark è sui PIXEL a schermo (quindi finisce in ogni cattura), non
/// modifica i byte decifrati.
class WatermarkOverlay extends StatelessWidget {
  const WatermarkOverlay({super.key, required this.child, this.label});

  final Widget child;

  /// Testo del watermark; se null usa "nome · data ora" di chi sta guardando.
  final String? label;

  static String _defaultLabel() {
    final name = AppServices.instance.myProfile?.displayName ?? 'Bruma';
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${two(n.day)}/${two(n.month)} ${two(n.hour)}:${two(n.minute)}';
    return '$name · $stamp';
  }

  @override
  Widget build(BuildContext context) {
    final text = (label == null || label!.isEmpty) ? _defaultLabel() : label!;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _WatermarkPainter(text)),
          ),
        ),
      ],
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  _WatermarkPainter(this.text);
  final String text;

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.16),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.rotate(-0.5); // ~ -28°
    final stepX = tp.width + 60;
    const stepY = 66.0;
    // Copre tutta l'area anche dopo la rotazione (bordi generosi).
    for (double y = -size.height; y < size.height * 2; y += stepY) {
      for (double x = -size.width; x < size.width * 2; x += stepX) {
        tp.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WatermarkPainter old) => old.text != text;
}
