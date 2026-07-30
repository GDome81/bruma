import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/local_prefs.dart';
import '../../core/models/models.dart';
import '../../shared/widgets.dart';

/// Normalizza per la ricerca: minuscolo + diacritici rimossi. La mappa è
/// 1 carattere → 1 carattere, così le posizioni trovate nel testo normalizzato
/// valgono anche sul testo originale (serve per evidenziare il termine).
String foldForSearch(String s) {
  const map = <String, String>{
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
    'ç': 'c', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y', 'æ': 'a', 'œ': 'o',
  };
  final sb = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    sb.write(map[ch] ?? ch);
  }
  return sb.toString();
}

class _Hit {
  _Hit(this.message, this.text) : folded = foldForSearch(text);
  final Message message;
  final String text;
  final String folded;
}

/// Ricerca nei testi di UNA chat. I messaggi sono cifrati end-to-end: il server
/// vede solo ciphertext, quindi la ricerca avviene sul dispositivo dopo aver
/// decifrato i testi.
///
/// PRIVACY: decifrare un messaggio RICEVUTO registra un'apertura, quindi il
/// mittente lo vedrebbe come "letto". Per questo l'indice comprende sempre e
/// solo ciò che non svela nulla di nuovo — i miei messaggi e quelli ricevuti
/// che ho già aperto — mentre i messaggi ricevuti non ancora aperti si
/// includono solo con un consenso esplicito (memorizzato).
class MessageSearchScreen extends StatefulWidget {
  const MessageSearchScreen({
    super.key,
    required this.conversationId,
    required this.other,
    required this.onJump,
  });

  final String conversationId;
  final Profile other;

  /// Chiamata (dopo aver chiuso questa schermata) per saltare al messaggio
  /// nella chat sottostante, senza aprire una seconda copia della chat.
  final void Function(String messageId) onJump;

  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
  final _controller = TextEditingController();
  final List<_Hit> _index = [];

  List<Message> _pendingUnopened = []; // ricevuti mai aperti (fuori indice)
  bool _loading = true;
  bool _indexing = false;
  Object? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = AppServices.instance.uid;
      final all = await AppServices.instance.messages
          .textMessages(widget.conversationId);
      // Sicuri da decifrare: i miei (l'apertura non è visibile all'altro) e i
      // ricevuti già aperti (una seconda apertura non aggiunge informazione).
      final safe = <Message>[];
      final unopened = <Message>[];
      for (final m in all) {
        if (m.senderId == me ||
            AppServices.instance.cachedText(m.id) != null ||
            LocalPrefs.searchIndexAll) {
          safe.add(m);
        } else {
          unopened.add(m);
        }
      }
      final texts = await AppServices.instance.decryptTexts(safe);
      if (!mounted) return;
      setState(() {
        _index
          ..clear()
          ..addAll([
            for (final m in safe)
              if (texts[m.id] != null) _Hit(m, texts[m.id]!),
          ]);
        _pendingUnopened = unopened;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  /// Include anche i messaggi ricevuti mai aperti: li decifra, quindi da quel
  /// momento risulteranno letti per il mittente. Serve il consenso.
  Future<void> _indexUnopened() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cercare anche nei non aperti?'),
        content: Text(
            'Per cercare dentro ${_pendingUnopened.length} messaggi di '
            '${widget.other.displayName} che non hai ancora aperto, l\'app deve '
            'decifrarli: da quel momento risulteranno LETTI per chi li ha '
            'inviati.\n\nLa scelta viene ricordata.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cerca comunque')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await LocalPrefs.setSearchIndexAll(true);
    setState(() => _indexing = true);
    try {
      final texts = await AppServices.instance.decryptTexts(_pendingUnopened);
      if (!mounted) return;
      setState(() {
        for (final m in _pendingUnopened) {
          final t = texts[m.id];
          if (t != null) _index.add(_Hit(m, t));
        }
        _pendingUnopened = [];
        _indexing = false;
      });
    } catch (_) {
      if (mounted) setState(() => _indexing = false);
    }
  }

  void _open(_Hit hit) {
    // Chiudi la ricerca e chiedi alla chat sottostante di saltare al messaggio.
    Navigator.of(context).pop();
    widget.onJump(hit.message.id);
  }

  List<_Hit> get _results {
    final q = foldForSearch(_query.trim());
    if (q.length < 2) return const [];
    final out = _index.where((h) => h.folded.contains(q)).toList();
    out.sort((a, b) => b.message.createdAt.compareTo(a.message.createdAt));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Cerca in chat con ${widget.other.displayName}…',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Pulisci',
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_indexing) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body(cs)),
        ],
      ),
    );
  }

  Widget _body(ColorScheme cs) {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorView(message: 'Errore: $_error', onRetry: _load);
    }
    final q = _query.trim();
    if (q.length < 2) {
      return EmptyView(
        icon: Icons.search,
        title: 'Cerca nei messaggi',
        subtitle: 'Scrivi almeno 2 caratteri. Vengono cercati '
            '${_index.length} messaggi di testo di questa chat.',
      );
    }
    final results = _results;
    if (results.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: EmptyView(
              icon: Icons.search_off,
              title: 'Nessun risultato',
              subtitle: 'Nessun messaggio contiene "$q".',
            ),
          ),
          _unopenedFooter(cs),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => _tile(results[i], q, cs),
          ),
        ),
        _unopenedFooter(cs),
      ],
    );
  }

  /// Invito (solo se ci sono ricevuti mai aperti) a estendere la ricerca.
  Widget _unopenedFooter(ColorScheme cs) {
    if (_pendingUnopened.isEmpty) return const SizedBox.shrink();
    return Material(
      color: cs.surfaceContainerHighest,
      child: InkWell(
        onTap: _indexing ? null : _indexUnopened,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.mark_email_unread_outlined,
                  size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_pendingUnopened.length} messaggi non ancora aperti non '
                  'sono nella ricerca (verrebbero segnati come letti). Tocca '
                  'per includerli.',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(_Hit hit, String rawQuery, ColorScheme cs) {
    final mine = hit.message.senderId == AppServices.instance.uid;
    final q = foldForSearch(rawQuery);
    return ListTile(
      leading: CircleAvatar(
        child: Icon(mine ? Icons.person : Icons.person_outline, size: 18),
      ),
      title: Text.rich(
        _snippet(hit.text, hit.folded, q,
            hl: TextStyle(
                backgroundColor: cs.primary.withValues(alpha: 0.30),
                fontWeight: FontWeight.w700)),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${mine ? 'Tu' : widget.other.displayName} · '
          '${formatTimestamp(hit.message.createdAt)}'),
      onTap: () => _open(hit),
    );
  }

  /// Estratto attorno alla prima occorrenza, con tutte le occorrenze della
  /// finestra evidenziate (i messaggi possono essere molto lunghi).
  TextSpan _snippet(String text, String folded, String q,
      {required TextStyle hl, int before = 28, int after = 140}) {
    final first = folded.indexOf(q);
    if (first < 0) return TextSpan(text: text);
    final start = (first - before).clamp(0, text.length);
    final end = (first + q.length + after).clamp(0, text.length);
    final spans = <TextSpan>[];
    if (start > 0) spans.add(const TextSpan(text: '…'));
    var i = start;
    while (i < end) {
      final at = folded.indexOf(q, i);
      if (at < 0 || at >= end) {
        spans.add(TextSpan(text: text.substring(i, end)));
        break;
      }
      if (at > i) spans.add(TextSpan(text: text.substring(i, at)));
      final mEnd = (at + q.length).clamp(0, end);
      spans.add(TextSpan(text: text.substring(at, mEnd), style: hl));
      i = mEnd;
    }
    if (end < text.length) spans.add(const TextSpan(text: '…'));
    return TextSpan(children: spans);
  }
}
