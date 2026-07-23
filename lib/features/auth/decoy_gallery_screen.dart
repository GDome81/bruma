import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'decoy_common.dart';
import 'gallery_source.dart';

/// Maschera "Galleria": sembra il visualizzatore di foto del telefono.
/// Su APK mostra le FOTO VERE del dispositivo (photo_manager); su web, o se il
/// permesso è negato, resta una griglia finta indistinguibile a colpo d'occhio.
/// Sblocco nascosto: nella barra di ricerca digita il PIN e invia, oppure
/// long-press sul titolo/miniatura (biometria su APK).
class DecoyGalleryScreen extends StatefulWidget {
  const DecoyGalleryScreen({super.key});

  @override
  State<DecoyGalleryScreen> createState() => _DecoyGalleryScreenState();
}

class _DecoyGalleryScreenState extends State<DecoyGalleryScreen>
    with DecoyUnlockMixin<DecoyGalleryScreen> {
  final _search = TextEditingController();
  bool _searching = false;

  List<Uint8List?>? _realThumbs; // non-null + non-vuoto = uso le foto vere

  @override
  void initState() {
    super.initState();
    _loadReal();
  }

  Future<void> _loadReal() async {
    if (kIsWeb) return; // sul web resta finta
    try {
      if (!await galleryRequestAccess()) return;
      final thumbs = await galleryThumbnails(limit: 60, size: 300);
      if (!mounted || thumbs.isEmpty) return;
      setState(() => _realThumbs = thumbs);
    } catch (_) {
      // permesso negato o errore: resta la griglia finta
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _submit() {
    if (submitPin(_search.text)) return;
    _search.clear();
    setState(() => _searching = false);
    FocusScope.of(context).unfocus();
  }

  void _openPhoto(int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PhotoView(index: index),
    ));
  }

  // Tinte deterministiche per i finti "scatti" (fallback senza vere foto).
  List<Color> _fakeTile(int i) {
    final h1 = (i * 47) % 360;
    final h2 = (h1 + 40) % 360;
    return [
      HSVColor.fromAHSV(1, h1.toDouble(), 0.45, 0.85).toColor(),
      HSVColor.fromAHSV(1, h2.toDouble(), 0.55, 0.55).toColor(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final real = _realThumbs;
    final useReal = real != null && real.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Cerca…',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _submit(),
              )
            // Long-press sul titolo → sblocco (nascosto).
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: longPressUnlock,
                child: const Text('Galleria'),
              ),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              if (_searching) {
                _search.clear();
                setState(() => _searching = false);
              } else {
                setState(() => _searching = true);
              }
            },
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(3),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
        ),
        itemCount: useReal ? real.length : 45,
        itemBuilder: (_, i) {
          if (useReal) {
            final bytes = real[i];
            return GestureDetector(
              onTap: () => _openPhoto(i),
              onLongPress: longPressUnlock, // sblocco nascosto
              child: bytes == null
                  ? Container(color: Colors.black12)
                  : Image.memory(bytes,
                      fit: BoxFit.cover, gaplessPlayback: true),
            );
          }
          final c = _fakeTile(i);
          return GestureDetector(
            onLongPress: longPressUnlock,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: c,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    i % 4 == 0
                        ? Icons.videocam
                        : (i % 5 == 0 ? Icons.favorite : null),
                    size: 16,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Apertura a schermo intero di una foto vera (completa l'illusione).
class _PhotoView extends StatelessWidget {
  const _PhotoView({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: FutureBuilder<Uint8List?>(
          future: galleryFullImage(index),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator();
            }
            final bytes = snap.data;
            if (bytes == null) {
              return const Icon(Icons.broken_image,
                  color: Colors.white54, size: 64);
            }
            return InteractiveViewer(
              child: Image.memory(bytes, fit: BoxFit.contain),
            );
          },
        ),
      ),
    );
  }
}
