// Sorgente foto per la maschera "Galleria". Su APK legge le foto vere del
// telefono (photo_manager); su web non esiste un'API per elencare la galleria,
// quindi lo stub restituisce vuoto e la maschera resta finta.
export 'gallery_source_stub.dart'
    if (dart.library.io) 'gallery_source_io.dart';
