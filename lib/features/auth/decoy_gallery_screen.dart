import 'package:flutter/material.dart';

import 'decoy_common.dart';

/// Maschera "Galleria": sembra un visualizzatore di foto del telefono. Sblocco:
/// nella barra di ricerca digita il PIN e invia (o long-press sul titolo;
/// biometria su APK).
class DecoyGalleryScreen extends StatefulWidget {
  const DecoyGalleryScreen({super.key});

  @override
  State<DecoyGalleryScreen> createState() => _DecoyGalleryScreenState();
}

class _DecoyGalleryScreenState extends State<DecoyGalleryScreen>
    with DecoyUnlockMixin<DecoyGalleryScreen> {
  final _search = TextEditingController();
  bool _searching = false;

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

  // Tinte deterministiche per i finti "scatti" (nessuna vera foto).
  List<Color> _tile(int i) {
    final h1 = (i * 47) % 360;
    final h2 = (h1 + 40) % 360;
    return [
      HSVColor.fromAHSV(1, h1.toDouble(), 0.45, 0.85).toColor(),
      HSVColor.fromAHSV(1, h2.toDouble(), 0.55, 0.55).toColor(),
    ];
  }

  @override
  Widget build(BuildContext context) {
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
        itemCount: 45,
        itemBuilder: (_, i) {
          final c = _tile(i);
          return GestureDetector(
            // Long-press anche sulle miniature → sblocco.
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
