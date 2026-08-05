import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/local_prefs.dart';
import '../../core/models/models.dart';
import '../../core/secure_screen.dart';
import '../../core/secure_store/favorite_notes.dart';
import '../../shared/favorite_icon.dart';
import '../../shared/watermark.dart';
import '../../shared/widgets.dart';
import '../favorites/favorites_screen.dart' show editFavoriteNote;

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
    this.message,
  });

  final Uint8List bytes;
  final DateTime? expiresAt;
  final bool secure;

  /// Se valorizzato compare la 🌙 per salvare nei preferiti (con nota) senza
  /// uscire dalla foto. Vale anche per i contenuti a visibilità limitata: il
  /// preferito è un segnalibro locale con una nota, quindi resta l'unico modo
  /// di ricordarsi cos'era una foto che non si potrà più aprire.
  final Message? message;

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

  /// 🌙 rapida: salva/togli dai preferiti senza uscire dalla foto, e alla prima
  /// aggiunta chiede la nota — per un contenuto a visibilità limitata quella
  /// nota è l'unico modo di ricordarsi cos'era.
  Widget _favoriteAction(Message m) {
    final fav = LocalPrefs.isFavorite(m.id);
    return IconButton(
      tooltip: fav ? 'Togli dai preferiti' : 'Salva nei preferiti',
      icon: Icon(fav ? favoriteIconOn : favoriteIconOff,
          color: fav ? favoriteColor : Colors.white),
      onPressed: () async {
        if (fav) {
          await AppServices.instance
              .setFavorite(m.conversationId, m.id, false);
          await FavoriteNotes.set(m.id, null);
          if (mounted) setState(() {});
          return;
        }
        await AppServices.instance.setFavorite(m.conversationId, m.id, true);
        if (mounted) setState(() {});
        if (mounted) await editFavoriteNote(context, m.id);
      },
    );
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
          if (widget.message != null) _favoriteAction(widget.message!),
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
        child: WatermarkOverlay(
          child: InteractiveViewer(
            maxScale: 5,
            child: Center(child: Image.memory(_bytes, fit: BoxFit.contain)),
          ),
        ),
      ),
    );
  }
}
