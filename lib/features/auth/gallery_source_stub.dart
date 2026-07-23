import 'dart:typed_data';

// Web (o piattaforme senza dart:io): nessun accesso alla galleria di sistema.
Future<bool> galleryRequestAccess() async => false;

Future<List<Uint8List?>> galleryThumbnails(
        {int limit = 60, int size = 300}) async =>
    const [];

Future<Uint8List?> galleryFullImage(int index) async => null;
