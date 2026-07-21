import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Accesso allo Storage per i blob delle foto cifrate (bucket privato).
class StorageRepository {
  StorageRepository(this._client);
  final SupabaseClient _client;

  StorageFileApi get _bucket =>
      _client.storage.from(AppConfig.photosBucket);

  Future<void> upload(String path, Uint8List cipherBytes) async {
    await _bucket.uploadBinary(
      path,
      cipherBytes,
      // Nome oggetto casuale: nessun upsert (evita sovrascritture indesiderate).
      fileOptions: const FileOptions(
        contentType: 'application/octet-stream',
      ),
    );
  }

  Future<Uint8List> download(String path) => _bucket.download(path);

  Future<void> remove(String path) async {
    await _bucket.remove([path]);
  }

  Future<void> removeMany(List<String> paths) async {
    if (paths.isEmpty) return;
    await _bucket.remove(paths);
  }
}
