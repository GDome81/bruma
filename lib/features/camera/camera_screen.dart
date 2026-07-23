import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../shared/widgets.dart';
import 'temp_file.dart';

/// Fotocamera in-app. Scatta una foto, ne legge i byte in memoria e li
/// restituisce (via pop). Il file temporaneo creato dal plugin viene
/// cancellato subito: la foto non entra mai nella galleria di sistema.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  List<CameraDescription> _cameras = const [];
  int _index = 0;
  String? _error;
  bool _busy = false;
  Uint8List? _preview; // foto scattata in attesa di conferma d'invio

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  Future<void> _setup() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'Nessuna fotocamera disponibile.');
        return;
      }
      await _startController(_index);
    } catch (e) {
      setState(() => _error = 'Errore fotocamera: $e');
    }
  }

  Future<void> _startController(int index) async {
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller = controller;
    _initFuture = controller.initialize();
    setState(() {});
    await _initFuture;
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    await _controller?.dispose();
    _index = (_index + 1) % _cameras.length;
    await _startController(_index);
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final XFile shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      // Cancella subito il file temporaneo in chiaro creato dal plugin (mobile).
      await deleteTempFile(shot.path);
      // Passo 2: mostra l'anteprima prima di inviare.
      if (mounted) {
        setState(() {
          _preview = bytes;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Scatto non riuscito: $e';
        });
      }
    }
  }

  void _send() {
    final b = _preview;
    if (b != null) Navigator.of(context).pop<Uint8List>(b);
  }

  /// Torna alla fotocamera dal vivo. Su web (e a volte su mobile) il flusso
  /// video si blocca dopo lo scatto: riavviamo il controller per essere certi
  /// di mostrare un'anteprima dal vivo e non l'ultimo fotogramma congelato.
  Future<void> _retake() async {
    if (!mounted) return;
    setState(() {
      _preview = null;
      _busy = true;
    });
    final old = _controller;
    _controller = null;
    await old?.dispose();
    if (!mounted) return;
    await _startController(_index);
    if (mounted) setState(() => _busy = false);
  }

  /// Fattore di zoom per coprire lo schermo mantenendo le proporzioni del
  /// preview (formula standard del plugin camera): se il prodotto degli
  /// aspect-ratio è < 1 si inverte, così il preview riempie sempre il viewport.
  double _coverScale(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return 1;
    var scale = size.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return scale;
  }

  Widget _previewScaffold() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Anteprima'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Annulla invio',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.memory(
            _preview!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const Text(
              'Impossibile mostrare l\'anteprima',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
      // Barra fissa in basso: i due tasti sono SEMPRE affiancati e visibili,
      // anche su web mobile, sopra la barra di sistema (SafeArea).
      bottomNavigationBar: Container(
        color: Colors.black,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _retake,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Riscatta'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _send,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.send),
                    label: const Text('Invia'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Passo 2: anteprima con invia / riscatta.
    if (_preview != null) return _previewScaffold();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scatta una foto'),
        actions: [
          if (_cameras.length > 1)
            IconButton(
              onPressed: _busy ? null : _switchCamera,
              icon: const Icon(Icons.cameraswitch),
            ),
        ],
      ),
      body: _error != null
          ? ErrorView(message: _error!)
          : FutureBuilder<void>(
              future: _initFuture,
              builder: (context, snap) {
                if (_controller == null ||
                    snap.connectionState != ConnectionState.done) {
                  return const LoadingView(label: 'Avvio fotocamera…');
                }
                if (snap.hasError) {
                  return ErrorView(message: 'Errore: ${snap.error}');
                }
                return Stack(
                  children: [
                    // Anteprima a tutto schermo (cover) SENZA distorsione.
                    // CameraPreview mantiene già le sue proporzioni; lo
                    // ingrandiamo con Transform.scale finché copre lo schermo,
                    // ritagliando l'eccesso (ClipRect). Niente stretch.
                    Positioned.fill(
                      child: ClipRect(
                        child: Transform.scale(
                          scale: _coverScale(context),
                          alignment: Alignment.center,
                          child: Center(child: CameraPreview(_controller!)),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Le foto non vengono salvate in galleria',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 32,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: _busy ? null : _capture,
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border:
                                  Border.all(color: Colors.white70, width: 4),
                            ),
                            child: _busy
                                ? const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 3),
                                  )
                                : const Icon(Icons.camera_alt,
                                    color: Colors.black, size: 34),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
