import 'package:flutter/material.dart';

import '../../core/local_prefs.dart';
import '../../core/real_calendar.dart';
import 'decoy_common.dart';

/// Una voce mostrata nel calendario. Quelle REALI vengono dal calendario del
/// telefono: sono in sola lettura e non vengono mai salvate da Bruma.
class _Entry {
  _Entry(this.title, {required this.local});
  final String title;
  final bool local;
}

/// Maschera "Calendario": sembra una normale app di calendario, con griglia del
/// mese e impegni consultabili/aggiungibili (salvati SOLO in locale, nessun
/// contenuto di Bruma).
///
/// Sblocco nascosto: long-press sul nome del mese (o biometria su APK); con PIN
/// attivo si digita il PIN nel campo "Cerca" e si invia.
///
/// NB: la maschera è disegnata sopra il Navigator dell'app (MaterialApp.builder)
/// e NON ne ha uno proprio: qui non si possono usare showDialog / showDatePicker
/// / showModalBottomSheet. Tutti i pannelli sono overlay INLINE dentro lo Stack.
class DecoyCalendarScreen extends StatefulWidget {
  const DecoyCalendarScreen({super.key});

  @override
  State<DecoyCalendarScreen> createState() => _DecoyCalendarScreenState();
}

class _DecoyCalendarScreenState extends State<DecoyCalendarScreen>
    with DecoyUnlockMixin<DecoyCalendarScreen> {
  static const _months = [
    'Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
    'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre',
  ];
  static const _weekdays = ['L', 'M', 'M', 'G', 'V', 'S', 'D'];

  final _search = TextEditingController();
  final _newEvent = TextEditingController();

  late DateTime _visibleMonth;
  late DateTime _selected;
  bool _showSearch = false;
  bool _showAdd = false;

  /// Impegni LOCALI per giorno ("aaaa-mm-gg" → titoli). Persistiti.
  final Map<String, List<String>> _events = {};

  /// Impegni REALI del telefono per giorno. Solo in memoria, mai salvati.
  final Map<String, List<String>> _real = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    _loadEvents();
    _loadReal();
  }

  /// Legge gli impegni veri del mese visibile (solo se l'utente ha attivato
  /// l'opzione e concesso il permesso). Sola lettura.
  Future<void> _loadReal() async {
    if (!LocalPrefs.decoyRealCalendar) return;
    final from = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    final to = DateTime(_visibleMonth.year, _visibleMonth.month + 2);
    final list = await readCalendarEvents(from, to);
    if (!mounted) return;
    setState(() {
      _real.clear();
      for (final e in list) {
        (_real[_key(e.day)] ??= []).add(e.title);
      }
    });
  }

  /// Voci del giorno: prima le reali (non cancellabili), poi le locali.
  List<_Entry> _entriesFor(DateTime d) {
    final k = _key(d);
    return [
      for (final t in _real[k] ?? const <String>[]) _Entry(t, local: false),
      for (final t in _events[k] ?? const <String>[]) _Entry(t, local: true),
    ];
  }

  bool _hasAny(DateTime d) {
    final k = _key(d);
    return (_real[k]?.isNotEmpty ?? false) ||
        (_events[k]?.isNotEmpty ?? false);
  }

  @override
  void dispose() {
    _search.dispose();
    _newEvent.dispose();
    super.dispose();
  }

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  void _loadEvents() {
    _events.clear();
    for (final raw in LocalPrefs.decoyEvents) {
      final i = raw.indexOf('|');
      if (i <= 0) continue;
      (_events[raw.substring(0, i)] ??= []).add(raw.substring(i + 1));
    }
  }

  Future<void> _persist() async {
    final flat = <String>[
      for (final e in _events.entries)
        for (final t in e.value) '${e.key}|$t',
    ];
    await LocalPrefs.setDecoyEvents(flat);
  }

  Future<void> _addEvent() async {
    final title = _newEvent.text.trim();
    if (title.isEmpty) {
      setState(() => _showAdd = false);
      return;
    }
    setState(() {
      (_events[_key(_selected)] ??= []).add(title);
      _newEvent.clear();
      _showAdd = false;
    });
    await _persist();
  }

  Future<void> _removeEvent(String title) async {
    setState(() {
      final k = _key(_selected);
      _events[k]?.remove(title);
      if (_events[k]?.isEmpty ?? false) _events.remove(k);
    });
    await _persist();
  }

  void _submitSearch() {
    // Sblocco nascosto: se è il PIN, sblocca.
    if (submitPin(_search.text)) return;
    // Altrimenti si comporta da ricerca: porta al primo impegno che combacia.
    final q = _search.text.trim().toLowerCase();
    _search.clear();
    FocusScope.of(context).unfocus();
    if (q.isEmpty) {
      setState(() => _showSearch = false);
      return;
    }
    final keys = <String>{..._events.keys, ..._real.keys}.toList()..sort();
    for (final k in keys) {
      final hit = [
        ...?_events[k],
        ...?_real[k],
      ].any((t) => t.toLowerCase().contains(q));
      if (hit) {
        final d = DateTime.tryParse(k);
        if (d != null) {
          setState(() {
            _visibleMonth = DateTime(d.year, d.month);
            _selected = d;
            _showSearch = false;
          });
          _loadReal();
          return;
        }
      }
    }
    setState(() => _showSearch = false);
  }

  void _shiftMonth(int delta) {
    setState(() => _visibleMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + delta));
    _loadReal(); // gli impegni veri si leggono per mese visibile
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dayEvents = _entriesFor(_selected);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendario'),
        actions: [
          IconButton(
            tooltip: 'Cerca',
            icon: const Icon(Icons.search),
            onPressed: () => setState(() => _showSearch = !_showSearch),
          ),
          IconButton(
            tooltip: 'Oggi',
            icon: const Icon(Icons.today_outlined),
            onPressed: () {
              final now = DateTime.now();
              setState(() {
                _visibleMonth = DateTime(now.year, now.month);
                _selected = DateTime(now.year, now.month, now.day);
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                if (_showSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: TextField(
                      controller: _search,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Cerca un impegno',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (_) => _submitSearch(),
                    ),
                  ),
                _monthHeader(cs),
                _weekdayRow(cs),
                _monthGrid(cs),
                const Divider(height: 1),
                Expanded(child: _dayList(cs, dayEvents)),
              ],
            ),
          ),
          if (_showAdd) _addPanel(cs),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nuovo impegno',
        onPressed: () => setState(() => _showAdd = true),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _monthHeader(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shiftMonth(-1),
          ),
          Expanded(
            // Long-press sul mese → sblocco (nascosto).
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: longPressUnlock,
              child: Center(
                child: Text(
                  '${_months[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shiftMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _weekdayRow(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final w in _weekdays)
            Expanded(
              child: Center(
                child: Text(w,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _monthGrid(ColorScheme cs) {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month);
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final leading = first.weekday - 1; // lunedì = 0
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();
    final today = DateTime.now();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: _cell(cs, r * 7 + c - leading, today)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(ColorScheme cs, int dayOffset, DateTime today) {
    final dayNum = dayOffset + 1;
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 42);
    }
    final date = DateTime(_visibleMonth.year, _visibleMonth.month, dayNum);
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final isSelected = date == _selected;
    final hasEvents = _hasAny(date);

    return InkWell(
      onTap: () => setState(() => _selected = date),
      borderRadius: BorderRadius.circular(21),
      child: SizedBox(
        height: 42,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? cs.primary
                    : (isToday ? cs.primaryContainer : null),
              ),
              child: Text(
                '$dayNum',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isToday || isSelected
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isSelected ? cs.onPrimary : null,
                ),
              ),
            ),
            const SizedBox(height: 2),
            // Pallino: il giorno ha impegni.
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasEvents ? cs.primary : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayList(ColorScheme cs, List<_Entry> dayEvents) {
    final label =
        '${_selected.day} ${_months[_selected.month - 1].toLowerCase()}';
    if (dayEvents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Nessun impegno il $label',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant)),
        ),
        for (final e in dayEvents)
          ListTile(
            leading: Icon(Icons.event, color: cs.primary),
            title: Text(e.title),
            // Gli impegni VERI del telefono sono in sola lettura: niente
            // pulsante elimina (Bruma non tocca il calendario di sistema).
            trailing: e.local
                ? IconButton(
                    tooltip: 'Elimina',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _removeEvent(e.title),
                  )
                : null,
          ),
      ],
    );
  }

  /// Pannello "nuovo impegno" INLINE (nessun Navigator disponibile qui).
  Widget _addPanel(ColorScheme cs) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showAdd = false),
        child: ColoredBox(
          color: Colors.black54,
          child: Center(
            child: GestureDetector(
              onTap: () {}, // assorbe i tap sulla card
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Nuovo impegno · ${_selected.day} '
                        '${_months[_selected.month - 1].toLowerCase()}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _newEvent,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          hintText: 'Es. Dentista alle 15',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _addEvent(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => setState(() => _showAdd = false),
                            child: const Text('Annulla'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _addEvent,
                            child: const Text('Salva'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
