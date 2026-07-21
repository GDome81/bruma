// Espone `deleteTempFile` scegliendo l'implementazione giusta per piattaforma
// (dart:io su mobile/desktop, no-op su web).
export 'temp_file_stub.dart' if (dart.library.io) 'temp_file_io.dart';
