// Ritaglia la luna dal banner del logo (assets/bruma_logo.png) per ricavare
// un'icona quadrata (assets/bruma_icon.png) usata da flutter_launcher_icons.
//
// Uso:  dart run tool/make_icon.dart
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final srcFile = File('assets/bruma_logo.png');
  final src = img.decodePng(srcFile.readAsBytesSync())!;
  stdout.writeln('Sorgente: ${src.width}x${src.height}');

  // Il banner è ~2752x1536: la luna sta a sinistra, il testo a destra.
  // Ritaglio quadrato centrato sulla luna, escludendo la scritta "bruma".
  // Calcolo in proporzione così regge anche se le dimensioni cambiano.
  final w = src.width;
  final h = src.height;
  final side = (h * 0.66).round(); // quadrato ~66% dell'altezza
  final cx = (w * 0.345).round(); // centro luna ~34.5% della larghezza
  final cy = (h * 0.515).round(); // centro luna ~51.5% dell'altezza
  var x = cx - side ~/ 2;
  var y = cy - side ~/ 2;
  x = x.clamp(0, w - side);
  y = y.clamp(0, h - side);
  stdout.writeln('Crop: x=$x y=$y side=$side');

  final cropped = img.copyCrop(src, x: x, y: y, width: side, height: side);
  final out = img.copyResize(cropped, width: 1024, height: 1024);
  File('assets/bruma_icon.png').writeAsBytesSync(img.encodePng(out));

  final p = src.getPixel(10, 10);
  stdout.writeln('Colore sfondo (top-left): '
      '#${p.r.toInt().toRadixString(16).padLeft(2, '0')}'
      '${p.g.toInt().toRadixString(16).padLeft(2, '0')}'
      '${p.b.toInt().toRadixString(16).padLeft(2, '0')}');
  stdout.writeln('Scritto assets/bruma_icon.png (1024x1024)');
}
