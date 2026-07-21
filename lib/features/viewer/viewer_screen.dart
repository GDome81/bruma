import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/secure_screen.dart';
import '../../shared/widgets.dart';

/// Visualizzatore fullscreen di una foto GIÀ decifrata (byte in RAM). Non
/// richiede la chiave al server: fa parte della stessa "sessione" di apertura
/// avviata dalla bolla, quindi non consuma un'altra apertura.
///
/// Se [secure] è true attiva FLAG_SECURE (tramite il guard a contatore) e, se
/// [expiresAt] è impostato, mostra un conto alla rovescia e si chiude da solo
/// alla scadenza.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    required this.bytes,
    this.expiresAt,
    this.secure = false,
  });

  final Uint8List bytes;
  final DateTime? expiresAt;
  final bool secure;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  late Uint8List _bytes;

  @override
  void initState() {
    super.initState();
    // Copia locale: la bolla gestisce il proprio buffer in modo indipendente.
    _bytes = Uint8List.fromList(widget.bytes);
    if (widget.secure) SecureScreenGuard.acquire();
    if (widget.expiresAt != null) _startCountdown(widget.expiresAt!);
  }

  void _startCountdown(DateTime expiresAt) {
    void tick() {
      final rem = expiresAt.toUtc().difference(DateTime.now().toUtc());
      if (rem.inMilliseconds <= 0) {
        _timer?.cancel();
        if (mounted) Navigator.of(context).maybePop();
      } else if (mounted) {
        setState(() => _remaining = rem);
      }
    }

    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.secure) SecureScreenGuard.release();
    for (var i = 0; i < _bytes.length; i++) {
      _bytes[i] = 0;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Foto'),
        actions: [
          if (widget.expiresAt != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 18),
                    const SizedBox(width: 6),
                    Text(formatHms(_remaining),
                        style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: InteractiveViewer(
          maxScale: 5,
          child: Center(child: Image.memory(_bytes, fit: BoxFit.contain)),
        ),
      ),
    );
  }
}
