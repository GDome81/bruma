import 'package:flutter/material.dart';

import '../../core/local_prefs.dart';
import '../../shared/bruma_logo.dart';

/// Tutorial mostrato al primo accesso (una sola volta) e ri-apribile da
/// Impostazioni → "Rivedi tutorial". Spiega maschera, sblocco, messaggi
/// effimeri, backup dell'identità e notifiche anonime.
///
/// Marca [LocalPrefs.tutorialSeen] a true quando viene chiuso (fine o salta),
/// così non riappare da solo.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _controller = PageController();
  int _page = 0;

  late final List<_Slide> _slides = const [
    _Slide(
      logo: true,
      title: 'Benvenuto in Bruma',
      body:
          'Messaggi e foto che spariscono, cifrati end-to-end: solo tu e chi '
          'scrivi potete leggerli. Nessuno, nemmeno il server, vede i '
          'contenuti.',
    ),
    _Slide(
      icon: Icons.login,
      title: 'Registrazione e primo accesso',
      body:
          'Per entrare fai un long press (tieni premuto) sulla maschera: '
          'appare la schermata di accesso.\n\n'
          '• Registrati con email e password (servono solo per collegare i '
          'tuoi dispositivi, non vengono mostrate a nessuno).\n'
          '• Scegli un nome visualizzato: qui Bruma genera la tua coppia di '
          'chiavi. La chiave privata resta SOLO su questo dispositivo e non '
          'viene mai caricata.\n'
          '• Aggiungi un contatto col suo codice/QR e inizia a scrivergli.',
    ),
    _Slide(
      icon: Icons.calculate_outlined,
      title: 'La maschera',
      body:
          'Bruma si apre sempre travestita (calcolatrice, fasi lunari o '
          'galleria — la scegli in Sicurezza). Sembra un\'app qualsiasi.\n\n'
          '• Per sbloccare: digita il PIN e premi "=" (o invio nelle altre '
          'maschere).\n'
          '• In alternativa fai un long press per andare all\'accesso.\n'
          '• Il pulsante panic rimette all\'istante la maschera senza '
          'disconnetterti.',
    ),
    _Slide(
      icon: Icons.local_fire_department_outlined,
      title: 'Messaggi e foto effimere',
      body:
          '• I testi si vedono subito; le foto si aprono con un tap.\n'
          '• Per le foto puoi impostare limiti di aperture e una scadenza, e '
          'revocarle quando vuoi.\n'
          '• Scorri un messaggio verso destra per rispondere; tocca una '
          'citazione per saltare al messaggio originale.\n'
          '• Spunte: 1 grigia = in invio, 2 grigie = inviato, 3 blu = letto.',
    ),
    _Slide(
      icon: Icons.vpn_key_outlined,
      warn: true,
      title: 'Fai il backup dell\'identità',
      body:
          'La tua chiave privata vive solo su questo dispositivo. Se cancelli '
          'la cache del browser, disinstalli l\'app o cambi telefono SENZA '
          'backup, perdi l\'accesso ai contenuti — non sono recuperabili.\n\n'
          'Vai su menu ⋮ → "Esporta identità" e conserva il backup in un '
          'posto sicuro. Su un nuovo dispositivo userai "Importa identità".',
    ),
    _Slide(
      icon: Icons.nightlight_round,
      title: 'Notifiche anonime',
      body:
          'Attiva le notifiche da Sicurezza: arriva solo una 🌙, senza nome '
          'né contenuto. Puoi gestire suono e vibrazione, e silenziare le '
          'singole chat.\n\n'
          'Nota: sull\'app Android gli screenshot sono bloccati mentre una '
          'foto è aperta; sul sito/PWA nessun browser lo consente.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    LocalPrefs.setTutorialSeen(true);
    if (mounted) Navigator.of(context).maybePop();
  }

  void _next() {
    if (_page >= _slides.length - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final last = _page >= _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(last ? '' : 'Salta'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? cs.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(last ? 'Iniziamo' : 'Avanti'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide({
    required this.title,
    required this.body,
    this.icon,
    this.logo = false,
    this.warn = false,
  });

  final String title;
  final String body;
  final IconData? icon;
  final bool logo;
  final bool warn;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = slide.warn ? cs.error : cs.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          if (slide.logo)
            const BrumaLogo(size: 120)
          else
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(slide.icon, size: 56, color: accent),
            ),
          const SizedBox(height: 32),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            slide.body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
