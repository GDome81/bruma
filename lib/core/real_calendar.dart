// Accesso al calendario di sistema isolato dietro import condizionato: sul web
// non esiste un'API per leggere il calendario del dispositivo, quindi si usa lo
// stub (nessun impegno reale) e il bundle web non include il plugin.
//
// SOLA LETTURA: nessuna funzione qui scrive nel calendario del telefono, e il
// manifest dichiara solo READ_CALENDAR.
export 'real_calendar_stub.dart'
    if (dart.library.io) 'real_calendar_io.dart';
