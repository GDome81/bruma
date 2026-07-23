import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

// Foto reali del telefono per la maschera "Galleria" (solo APK/native).
// Manteniamo i riferimenti agli asset così da poter caricare la versione
// grande su richiesta (apertura a schermo intero).
List<AssetEntity> _assets = [];

/// Chiede il permesso di accesso alle foto. True se l'accesso è concesso
/// (anche parziale su Android 14+).
Future<bool> galleryRequestAccess() async {
  final ps = await PhotoManager.requestPermissionExtend();
  return ps.hasAccess;
}

/// Miniature (quadrate) delle foto più recenti. Un elemento può essere null se
/// la miniatura non è generabile.
Future<List<Uint8List?>> galleryThumbnails(
    {int limit = 60, int size = 300}) async {
  final paths = await PhotoManager.getAssetPathList(
    type: RequestType.image,
    onlyAll: true,
  );
  if (paths.isEmpty) {
    _assets = [];
    return const [];
  }
  _assets = await paths.first.getAssetListRange(start: 0, end: limit);
  final out = <Uint8List?>[];
  for (final a in _assets) {
    out.add(await a.thumbnailDataWithSize(ThumbnailSize.square(size)));
  }
  return out;
}

/// Versione grande della foto [index] (per l'apertura a schermo intero).
Future<Uint8List?> galleryFullImage(int index) async {
  if (index < 0 || index >= _assets.length) return null;
  return _assets[index].thumbnailDataWithSize(const ThumbnailSize(1280, 1280));
}
