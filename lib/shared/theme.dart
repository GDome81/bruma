import 'package:flutter/material.dart';

/// Tema di Bruma — palette calma "foschia" (blu-grigio) su base Material 3.
class BrumaTheme {
  static const seed = Color(0xFF5B7A8C);

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      // ATTENZIONE: Size.fromHeight(48) è Size(double.infinity, 48), cioè
      // larghezza minima INFINITA: tutti i FilledButton sono a tutta larghezza.
      // Voluto per i pulsanti principali di form e dialoghi. Per un pulsante
      // dentro una riga usa [compactFilledStyle], altrimenti si mangia la riga.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    );
  }
}

/// Pulsante IN LINEA (dentro una riga di lista, accanto a del testo).
/// Annulla la larghezza minima infinita imposta dal tema: senza questo un
/// FilledButton occupa tutta la riga e il testo accanto scompare.
ButtonStyle compactFilledStyle() => FilledButton.styleFrom(
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
