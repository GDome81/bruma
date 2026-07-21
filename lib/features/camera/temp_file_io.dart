import 'dart:io';

/// Cancella il file temporaneo in chiaro creato dal plugin fotocamera (mobile).
Future<void> deleteTempFile(String path) async {
  try {
    await File(path).delete();
  } catch (_) {}
}
