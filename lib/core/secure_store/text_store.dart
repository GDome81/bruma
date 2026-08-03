// Archivio locale dei testi già decifrati, dietro import condizionato:
//  * APK  → SQLite con righe opache, scritture incrementali, nessun tetto
//           (text_store_db.dart)
//  * web  → unico blob cifrato in SharedPreferences, perché sqflite non è
//           disponibile nella PWA (text_store_blob.dart)
//
// Entrambi espongono la stessa API: load / put / removeIds / clear.
export 'text_store_blob.dart' if (dart.library.io) 'text_store_db.dart';
