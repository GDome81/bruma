import 'package:flutter/material.dart';

/// Logo di Bruma: la luna crescente argento (assets/logo.jpeg) dentro un
/// medaglione circolare bianco, così il fondo bianco del file diventa parte
/// del design ed è leggibile sia su tema chiaro che scuro.
class BrumaLogo extends StatelessWidget {
  const BrumaLogo({super.key, this.size = 96, this.zoom = 1.6});

  /// Diametro del medaglione.
  final double size;

  /// Ingrandimento dell'immagine per ritagliare il bordo bianco in eccesso.
  final double zoom;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size / zoom,
          height: size / zoom,
          child: Image.asset(
            'assets/logo.jpeg',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
