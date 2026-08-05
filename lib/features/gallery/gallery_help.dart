import 'package:flutter/material.dart';

import '../../shared/favorite_icon.dart';

/// Testi della guida sulle gallerie, in UN SOLO posto: li usano sia i pannelli
/// ⓘ dentro le schermate sia la sezione del tutorial, così non divergono.
class GalleryHelp {
  /// Testo introduttivo: in Bruma le foto stanno in posti diversi a seconda di
  /// quanto sono "libere", e senza una frase di contesto non è intuibile.
  static const intro =
      'In Bruma una foto non sta in un posto solo: dipende da quanti limiti ha. '
      'Ci sono tre raccolte, tutte separate per ogni chat, e ognuna risponde a '
      'una domanda diversa.';

  /// Le tre raccolte: cosa c'è dentro e a cosa servono.
  static const collections = <(IconData, String, String)>[
    (
      Icons.collections_outlined,
      'Galleria — "cosa possiamo rivedere sempre"',
      'Contiene solo le foto SENZA limiti che hai salvato. Ci arrivano quando '
          'chi le manda le rende disponibili e tu le aggiungi. Si aprono quante '
          'volte vuoi. Menu ⋮ → Galleria.',
    ),
    (
      Icons.lock_clock,
      'Contenuti a tempo — "cosa sta per scadere"',
      'Le foto che hanno ancora un credito di aperture o una scadenza. Due '
          'schede: "Le mie" (quelle che hai inviato, con quante aperture '
          'restano all\'altro) e "Ricevute" (quelle che puoi ancora aprire, con '
          'quante ne restano a te). Menu ⋮ → Contenuti a tempo.',
    ),
    (
      favoriteIconOff,
      'Preferiti — "cosa voglio ritrovare"',
      'Messaggi e foto che hai segnato, con una nota facoltativa per '
          'ricordarti cosa erano: utile per i contenuti protetti che non si '
          'possono rivedere. Toccandone uno torni a quel punto della chat. '
          'Menu ⋮ → Preferiti.',
    ),
    (
      Icons.touch_app_outlined,
      'Come si usano',
      'Tutte le azioni partono dal TIENI PREMUTO: su una foto in chat per '
          'renderla disponibile, salvarla o revocarla; su una foto nelle '
          'raccolte per riabilitarla, cancellarla o saltare al messaggio.',
    ),
  ];

  /// Un punto della guida: titolo, spiegazione, icona.
  static const galleryStates = <(IconData, String, String)>[
    (
      Icons.lock_outline,
      'Foto protetta',
      'Ha un numero di aperture e/o una scadenza. Quando il credito finisce '
          'non è più apribile. È lo stato predefinito.',
    ),
    (
      Icons.collections_outlined,
      'Foto disponibile',
      'Il mittente l\'ha resa senza limiti: si può aprire quante volte si '
          'vuole, ma resta sul server e lui può ancora togliertela.',
    ),
    (
      Icons.bookmark,
      'In galleria',
      'Una foto disponibile che hai salvato: la ritrovi nella Galleria della '
          'chat. È un segnalibro, non una copia sul telefono.',
    ),
  ];

  static const actions = <(IconData, String, String)>[
    (
      Icons.delete_forever,
      'Revoca = cancella',
      'Elimina la foto dal server per sempre: nessuno può più aprirla, '
          'nemmeno tu. Irreversibile.',
    ),
    (
      Icons.lock_open_outlined,
      'Togli dalla galleria ≠ cancella',
      'La foto torna protetta e con i limiti della chat, ma NON viene '
          'cancellata: puoi renderla di nuovo apribile quando vuoi.',
    ),
    (
      Icons.autorenew,
      'Rendi di nuovo apribile',
      'Azzera il contatore delle aperture sulla STESSA foto. Non crea una '
          'copia e non altera le statistiche.',
    ),
  ];

  static const counters = <(IconData, String, String)>[
    (
      Icons.visibility_outlined,
      '"Le mie"',
      'Le foto che hai inviato e che hanno ancora dei limiti. Il contatore '
          'dice quante aperture restano all\'ALTRA persona.',
    ),
    (
      Icons.mark_email_unread_outlined,
      '"Ricevute"',
      'Le foto ricevute che puoi ancora aprire. Il contatore dice quante '
          'aperture restano A TE.',
    ),
    (
      Icons.visibility_off_outlined,
      'Perché le ricevute non hanno anteprima',
      'Aprire una foto protetta consuma una delle tue aperture: mostrarne '
          'l\'anteprima le brucerebbe tutte solo scorrendo la lista. Per '
          'questo vedi un lucchetto e apri solo quando decidi tu.',
    ),
  ];
}

/// Pannello ⓘ: spiega la schermata in cui ti trovi, senza uscire dal contesto.
Future<void> showGalleryHelp(
  BuildContext context, {
  required String title,
  required List<(IconData, String, String)> sections,
  String? intro,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(ctx).textTheme.titleLarge),
                if (intro != null) ...[
                  const SizedBox(height: 10),
                  Text(intro,
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          color: cs.onSurfaceVariant)),
                ],
                const SizedBox(height: 16),
                for (final s in sections) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 12),
                        child: Icon(s.$1, size: 20, color: cs.primary),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.$2,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(s.$3,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
