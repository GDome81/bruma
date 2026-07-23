// Firebase Cloud Messaging isolato dietro import condizionato: su web (nessun
// dart:io) si usa lo stub no-op — così il bundle web non include Firebase e
// resta sul Web Push esistente. Su APK Android si usa l'implementazione reale.
export 'fcm_stub.dart' if (dart.library.io) 'fcm_io.dart';
