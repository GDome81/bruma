import 'package:flutter/material.dart';

import '../../core/app_services.dart';

/// Schermata "decoy" mostrata in modalità panic: sembra una normale
/// calcolatrice. Per tornare all'app: LONG-PRESS sul display → login.
class DecoyScreen extends StatefulWidget {
  const DecoyScreen({super.key});

  @override
  State<DecoyScreen> createState() => _DecoyScreenState();
}

class _DecoyScreenState extends State<DecoyScreen> {
  String _display = '0';
  double? _acc;
  String? _op;
  bool _fresh = true;

  void _inputDigit(String d) {
    setState(() {
      if (_fresh || _display == '0') {
        _display = d;
        _fresh = false;
      } else {
        if (_display.length < 12) _display += d;
      }
    });
  }

  void _inputDot() {
    setState(() {
      if (_fresh) {
        _display = '0.';
        _fresh = false;
      } else if (!_display.contains('.')) {
        _display += '.';
      }
    });
  }

  double get _value => double.tryParse(_display) ?? 0;

  String _fmt(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    return v.toString();
  }

  void _setOp(String op) {
    setState(() {
      if (_op != null && !_fresh) _compute();
      _acc = _value;
      _op = op;
      _fresh = true;
    });
  }

  void _compute() {
    if (_op == null || _acc == null) return;
    final b = _value;
    final r = switch (_op) {
      '+' => _acc! + b,
      '−' => _acc! - b,
      '×' => _acc! * b,
      '÷' => b == 0 ? 0.0 : _acc! / b,
      _ => _acc!,
    };
    _display = _fmt(r);
    _acc = r;
  }

  void _equals() {
    setState(() {
      _compute();
      _op = null;
      _fresh = true;
    });
  }

  void _clear() {
    setState(() {
      _display = '0';
      _acc = null;
      _op = null;
      _fresh = true;
    });
  }

  void _backspace() {
    setState(() {
      if (_display.length <= 1 || (_display.length == 2 && _display.startsWith('-'))) {
        _display = '0';
        _fresh = true;
      } else {
        _display = _display.substring(0, _display.length - 1);
      }
    });
  }

  void _percent() {
    setState(() => _display = _fmt(_value / 100));
  }

  // Sblocco nascosto: torna al login (richiede re-autenticazione).
  void _unlock() => AppServices.instance.setPanic(false);

  Widget _btn(String label,
      {Color? bg, Color? fg, VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Material(
          color: bg ?? cs.surfaceContainerHighest,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              height: 68,
              child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 26,
                        color: fg ?? cs.onSurface,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Display: long-press per sbloccare (nascosto).
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: _unlock,
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_display,
                        maxLines: 1,
                        style: TextStyle(
                            fontSize: 72,
                            fontWeight: FontWeight.w300,
                            color: cs.onSurface)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                children: [
                  Row(children: [
                    _btn('C',
                        bg: cs.secondaryContainer,
                        fg: cs.onSecondaryContainer,
                        onTap: _clear),
                    _btn('⌫',
                        bg: cs.secondaryContainer,
                        fg: cs.onSecondaryContainer,
                        onTap: _backspace),
                    _btn('%',
                        bg: cs.secondaryContainer,
                        fg: cs.onSecondaryContainer,
                        onTap: _percent),
                    _btn('÷',
                        bg: cs.primaryContainer,
                        fg: cs.onPrimaryContainer,
                        onTap: () => _setOp('÷')),
                  ]),
                  Row(children: [
                    _btn('7', onTap: () => _inputDigit('7')),
                    _btn('8', onTap: () => _inputDigit('8')),
                    _btn('9', onTap: () => _inputDigit('9')),
                    _btn('×',
                        bg: cs.primaryContainer,
                        fg: cs.onPrimaryContainer,
                        onTap: () => _setOp('×')),
                  ]),
                  Row(children: [
                    _btn('4', onTap: () => _inputDigit('4')),
                    _btn('5', onTap: () => _inputDigit('5')),
                    _btn('6', onTap: () => _inputDigit('6')),
                    _btn('−',
                        bg: cs.primaryContainer,
                        fg: cs.onPrimaryContainer,
                        onTap: () => _setOp('−')),
                  ]),
                  Row(children: [
                    _btn('1', onTap: () => _inputDigit('1')),
                    _btn('2', onTap: () => _inputDigit('2')),
                    _btn('3', onTap: () => _inputDigit('3')),
                    _btn('+',
                        bg: cs.primaryContainer,
                        fg: cs.onPrimaryContainer,
                        onTap: () => _setOp('+')),
                  ]),
                  Row(children: [
                    _btn('0', onTap: () => _inputDigit('0')),
                    _btn('.', onTap: _inputDot),
                    _btn('=',
                        bg: cs.primary,
                        fg: cs.onPrimary,
                        onTap: _equals),
                  ]),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
