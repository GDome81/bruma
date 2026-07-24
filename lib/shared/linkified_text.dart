import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Testo che rende cliccabili gli URL (http/https e "www."), aprendoli nel
/// browser esterno. Per sicurezza apre SOLO http/https (nessun altro schema).
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(this.text, {super.key, this.style, this.linkStyle});

  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  static final _urlRegex =
      RegExp(r'((https?:\/\/|www\.)[^\s]+)', caseSensitive: false);

  final List<TapGestureRecognizer> _recognizers = [];
  late List<_Seg> _segs;

  @override
  void initState() {
    super.initState();
    _segs = _parse(widget.text);
  }

  @override
  void didUpdateWidget(covariant LinkifiedText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _disposeRecognizers();
      _segs = _parse(widget.text);
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  List<_Seg> _parse(String text) {
    final segs = <_Seg>[];
    var last = 0;
    for (final m in _urlRegex.allMatches(text)) {
      if (m.start > last) segs.add(_Seg(text.substring(last, m.start), null));
      final urlText = text.substring(m.start, m.end);
      final rec = TapGestureRecognizer()..onTap = () => _open(urlText);
      _recognizers.add(rec);
      segs.add(_Seg(urlText, rec));
      last = m.end;
    }
    if (last < text.length) segs.add(_Seg(text.substring(last), null));
    return segs;
  }

  Future<void> _open(String raw) async {
    // Togli punteggiatura finale comune ("...link)." ecc.).
    var url = raw.replaceFirst(RegExp(r'''[),.!?;:'"]+$'''), '');
    if (url.toLowerCase().startsWith('www.')) url = 'https://$url';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (uri.scheme != 'http' && uri.scheme != 'https') return; // sicurezza
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // niente browser / errore: ignora
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style;
    final link = (widget.linkStyle ??
            const TextStyle(
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w600))
        .merge(base);
    return Text.rich(
      TextSpan(
        children: [
          for (final s in _segs)
            TextSpan(
              text: s.text,
              style: s.recognizer == null ? base : link,
              recognizer: s.recognizer,
            ),
        ],
      ),
    );
  }
}

class _Seg {
  _Seg(this.text, this.recognizer);
  final String text;
  final TapGestureRecognizer? recognizer;
}
