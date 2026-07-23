import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'decoy_common.dart';

/// Maschera "Fasi lunari": sembra un'app che calcola la fase della luna per una
/// data. Sblocco: nel campo data digita il PIN e invia (o long-press sulla
/// luna; biometria su APK).
class DecoyMoonScreen extends StatefulWidget {
  const DecoyMoonScreen({super.key});

  @override
  State<DecoyMoonScreen> createState() => _DecoyMoonScreenState();
}

class _DecoyMoonScreenState extends State<DecoyMoonScreen>
    with DecoyUnlockMixin<DecoyMoonScreen> {
  final _field = TextEditingController();
  late DateTime _date = DateTime.now();
  bool _showCalendar = false;

  static const _synodic = 29.530588853;
  static const _names = [
    'Luna nuova',
    'Luna crescente',
    'Primo quarto',
    'Gibbosa crescente',
    'Luna piena',
    'Gibbosa calante',
    'Ultimo quarto',
    'Luna calante',
  ];
  static const _emoji = ['🌑', '🌒', '🌓', '🌔', '🌕', '🌖', '🌗', '🌘'];

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  double _ageDays(DateTime d) {
    final ref = DateTime.utc(2000, 1, 6, 18, 14);
    var age = d.toUtc().difference(ref).inSeconds / 86400.0 % _synodic;
    if (age < 0) age += _synodic;
    return age;
  }

  int _phaseIndex(DateTime d) =>
      (((_ageDays(d) / _synodic) * 8).round()) % 8;

  int _illumination(DateTime d) {
    final frac = (1 - math.cos(2 * math.pi * _ageDays(d) / _synodic)) / 2;
    return (frac * 100).round();
  }

  // NB: niente showDatePicker qui — la maschera è disegnata sopra il Navigator
  // dell'app (in MaterialApp.builder) e non ne ha uno suo. Usiamo un
  // CalendarDatePicker INLINE (widget, non dialog) mostrato in overlay dentro
  // la schermata: nessun Navigator richiesto.
  DateTime get _clampedDate {
    final first = DateTime(1900);
    final last = DateTime(2100);
    if (_date.isBefore(first)) return first;
    if (_date.isAfter(last)) return last;
    return _date;
  }

  void _submit() {
    final text = _field.text.trim();
    // Sblocco nascosto: se è il PIN, sblocca.
    if (submitPin(text)) return;
    // Altrimenti prova a interpretare una data (gg/mm/aaaa) e mostra la fase.
    final m = RegExp(r'^(\d{1,2})\D+(\d{1,2})\D+(\d{2,4})$').firstMatch(text);
    if (m != null) {
      final d = int.tryParse(m.group(1)!) ?? 1;
      final mo = int.tryParse(m.group(2)!) ?? 1;
      var y = int.tryParse(m.group(3)!) ?? 2000;
      if (y < 100) y += 2000;
      setState(() => _date = DateTime(y, mo, d));
    }
    _field.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = _phaseIndex(_date);
    final dateLabel =
        '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}';
    return Scaffold(
      appBar: AppBar(title: const Text('Fasi Lunari')),
      body: Stack(
        children: [
          SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              TextField(
                controller: _field,
                textInputAction: TextInputAction.search,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9/\-. ]')),
                ],
                decoration: InputDecoration(
                  prefixIcon: IconButton(
                    icon: const Icon(Icons.calendar_month),
                    tooltip: 'Scegli dal calendario',
                    onPressed: () =>
                        setState(() => _showCalendar = !_showCalendar),
                  ),
                  hintText: 'Vai a una data (gg/mm/aaaa)',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _submit,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const Spacer(),
              // Long-press sulla luna → sblocco (nascosto).
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: longPressUnlock,
                child: Text(_emoji[idx],
                    style: const TextStyle(fontSize: 128)),
              ),
              const SizedBox(height: 16),
              Text(_names[idx],
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text('$dateLabel · illuminazione ${_illumination(_date)}%',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const Spacer(),
            ],
          ),
        ),
      ),
          // Calendario INLINE (nessun Navigator): scrim + card centrata.
          if (_showCalendar)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showCalendar = false),
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: GestureDetector(
                      onTap: () {}, // assorbe i tap sulla card
                      child: Card(
                        margin: const EdgeInsets.all(24),
                        child: SizedBox(
                          width: 340,
                          child: CalendarDatePicker(
                            initialDate: _clampedDate,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100),
                            onDateChanged: (d) => setState(() {
                              _date = d;
                              _showCalendar = false;
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
