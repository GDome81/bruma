import 'package:flutter/material.dart';

/// Marchio compatto di Bruma: la luna ritagliata dal banner (assets/bruma_icon
/// .png) in una piastrella con angoli arrotondati. Ha già lo sfondo scuro, così
/// è leggibile sia su tema chiaro che scuro. Per il lockup completo con la
/// scritta "bruma" usa direttamente assets/bruma_logo.png.
class BrumaLogo extends StatelessWidget {
  const BrumaLogo({super.key, this.size = 96, this.radiusFactor = 0.24});

  /// Lato della piastrella.
  final double size;

  /// Raggio degli angoli come frazione del lato.
  final double radiusFactor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * radiusFactor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/bruma_icon.png',
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
