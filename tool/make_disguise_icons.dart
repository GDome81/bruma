// Genera icone launcher SEMPLICI e piatte per i travestimenti dell'app
// (Calcolatrice, Meteo, Note, Promemoria) usate dalle activity-alias Android.
// Sono volutamente essenziali: servono a mimetizzare, non a vincere premi.
//
// Uso:  dart run tool/make_disguise_icons.dart
import 'dart:io';

import 'package:image/image.dart' as img;

const _size = 432;
const _dir = 'android/app/src/main/res/mipmap-xxxhdpi';

img.Image _canvas(int r, int g, int b) {
  final im = img.Image(width: _size, height: _size, numChannels: 4);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  return im;
}

void _save(img.Image im, String name) {
  final f = File('$_dir/$name.png');
  f.writeAsBytesSync(img.encodePng(im));
  stdout.writeln('scritto ${f.path}');
}

void _calc() {
  final im = _canvas(0x26, 0x32, 0x38); // slate scuro
  final white = img.ColorRgb8(0xF5, 0xF5, 0xF5);
  final btn = img.ColorRgb8(0x54, 0x6E, 0x7A);
  final orange = img.ColorRgb8(0xFF, 0x98, 0x00);
  // display
  img.fillRect(im, x1: 70, y1: 60, x2: 362, y2: 150, color: white);
  // 3x3 tasti + colonna operatori
  const startY = 185;
  const gap = 18;
  const cell = 74;
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      final x = 70 + col * (cell + gap);
      final y = startY + row * (cell + gap);
      img.fillRect(im, x1: x, y1: y, x2: x + cell, y2: y + cell, color: btn);
    }
  }
  // colonna operatori arancione a destra
  for (var row = 0; row < 3; row++) {
    final x = 70 + 3 * (cell + gap);
    final y = startY + row * (cell + gap);
    img.fillRect(im, x1: x, y1: y, x2: x + cell, y2: y + cell, color: orange);
  }
  _save(im, 'ic_calc');
}

void _meteo() {
  final im = _canvas(0x40, 0xA7, 0xE3); // azzurro cielo
  final sun = img.ColorRgb8(0xFF, 0xD5, 0x4F);
  final white = img.ColorRgb8(0xFF, 0xFF, 0xFF);
  // sole in alto a sinistra con raggi
  const sx = 165, sy = 150, sr = 70;
  for (var a = 0; a < 360; a += 45) {
    final rad = a * 3.1415926 / 180.0;
    final x1 = (sx + (sr + 12) * _cos(rad)).round();
    final y1 = (sy + (sr + 12) * _sin(rad)).round();
    final x2 = (sx + (sr + 46) * _cos(rad)).round();
    final y2 = (sy + (sr + 46) * _sin(rad)).round();
    img.drawLine(im, x1: x1, y1: y1, x2: x2, y2: y2, color: sun, thickness: 12);
  }
  img.fillCircle(im, x: sx, y: sy, radius: sr, color: sun);
  // nuvola bianca in basso a destra (3 cerchi + base)
  img.fillCircle(im, x: 250, y: 300, radius: 55, color: white);
  img.fillCircle(im, x: 320, y: 300, radius: 70, color: white);
  img.fillCircle(im, x: 300, y: 260, radius: 55, color: white);
  img.fillRect(im, x1: 200, y1: 300, x2: 372, y2: 355, color: white);
  _save(im, 'ic_meteo');
}

void _note() {
  final im = _canvas(0xF4, 0xB4, 0x00); // ambra
  final white = img.ColorRgb8(0xFF, 0xFF, 0xFF);
  final line = img.ColorRgb8(0xBD, 0xBD, 0xBD);
  img.fillRect(im, x1: 78, y1: 60, x2: 354, y2: 372, color: white);
  for (var i = 0; i < 5; i++) {
    final y = 120 + i * 48;
    img.drawLine(im, x1: 110, y1: y, x2: 322, y2: y, color: line, thickness: 8);
  }
  _save(im, 'ic_note');
}

void _promemoria() {
  final im = _canvas(0xE5, 0x39, 0x35); // rosso
  final white = img.ColorRgb8(0xFF, 0xFF, 0xFF);
  final dark = img.ColorRgb8(0xB7, 0x1C, 0x1C);
  // orologio
  const cx = 216, cy = 226, r = 132;
  img.fillCircle(im, x: cx, y: cy, radius: r, color: white);
  for (var t = 0; t < 3; t++) {
    img.drawCircle(im, x: cx, y: cy, radius: r - t, color: dark);
  }
  // lancette
  img.drawLine(im, x1: cx, y1: cy, x2: cx, y2: cy - 80, color: dark, thickness: 12);
  img.drawLine(im, x1: cx, y1: cy, x2: cx + 60, y2: cy, color: dark, thickness: 12);
  // campanella in alto (pulsante)
  img.fillRect(im, x1: cx - 20, y1: 60, x2: cx + 20, y2: 92, color: white);
  _save(im, 'ic_promemoria');
}

// mini trig senza import di dart:math per tenere il file compatto
double _cos(double x) => _sin(x + 1.5707963);
double _sin(double x) {
  // Taylor ridotta, normalizza in [-pi, pi]
  var t = x % 6.2831853;
  if (t > 3.1415926) t -= 6.2831853;
  if (t < -3.1415926) t += 6.2831853;
  final t3 = t * t * t;
  final t5 = t3 * t * t;
  final t7 = t5 * t * t;
  return t - t3 / 6 + t5 / 120 - t7 / 5040;
}

void main() {
  Directory(_dir).createSync(recursive: true);
  _calc();
  _meteo();
  _note();
  _promemoria();
  stdout.writeln('Fatto.');
}
