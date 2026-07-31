import 'dart:async';
import 'dart:math';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_services.dart';
import '../../core/local_prefs.dart';
import '../../core/models/models.dart';
import '../../shared/emoji_config.dart';
import '../../shared/widgets.dart';
import '../camera/camera_screen.dart';
import '../favorites/favorites_screen.dart';
import '../gallery/gallery_screen.dart';
import '../search/message_search_screen.dart';
import '../secret/secret_gallery_screen.dart';
import '../settings/chat_settings_screen.dart';
import '../stats/stats_screen.dart';
import 'message_bubble.dart';

const _pageSize = 30;

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    required this.other,
    this.jumpToMessageId,
  });

  final String conversationId;
  final Profile other;

  /// Se valorizzato (es. aperta da Notifiche), all'avvio la chat salta a questo
  /// messaggio e lo evidenzia.
  final String? jumpToMessageId;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final ItemScrollController _itemScroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();

  final List<Message> _messages = []; // crescente (vecchi → recenti)
  Map<String, List<Reaction>> _reactions = {};
  // Tutte le richieste che mi riguardano (mittente o destinatario), per foto:
  // l'ultima per ogni messaggio → stato + azioni sulle bolle di riapertura.
  Map<String, ContentRequest> _reqByMessage = {};

  String? _error;
  bool _loadingInitial = true;
  bool _loadingOlder = false;
  bool _hasMore = true;
  bool _sending = false;
  bool _didInitialScroll = false;
  bool _showEmoji = false;
  bool _showScrollDown = false; // tasto "vai all'ultimo messaggio"
  int _newCount = 0; // messaggi arrivati mentre sono scrollato in alto
  bool _jumping = false; // sto caricando la cronologia per saltare a un messaggio
  Timer? _receiptsDebounce;
  Message? _replyingTo;
  DateTime? _lastReadAtOpen;
  String? _highlightId; // messaggio evidenziato dopo il tap su una citazione
  Timer? _highlightTimer;

  RealtimeChannel? _msgChannel;
  RealtimeChannel? _reactChannel;
  Timer? _reactDebounce;
  StreamSubscription? _opensSub;
  StreamSubscription? _requestsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastReadAtOpen = LocalPrefs.lastRead(widget.conversationId);
    _positions.itemPositions.addListener(_onPositions);
    _loadInitial();
    _msgChannel = AppServices.instance.messages.subscribeConversation(
      widget.conversationId,
      onInsert: _onInsert,
      onUpdate: _onUpdate,
    );
    _reactChannel =
        AppServices.instance.messages.subscribeReactions(_onReactionChange);
    // Ricarica subito le reactions quando io ne aggiungo/tolgo una (non aspetto
    // l'eco realtime, che a volte tarda).
    AppServices.instance.reactionsTick.addListener(_reloadReactions);
    // Aggiorna la stellina sulle bolle quando cambio i preferiti.
    AppServices.instance.favoritesTick.addListener(_onFavoritesChanged);
    // Ricevute di lettura: UNA query per tutta la chat (non una per bolla),
    // rinfrescata quando arrivano eventi di apertura.
    _loadReadReceipts();
    _opensSub = AppServices.instance.stats.watchMyOpenEvents().listen(
          (_) => _loadReadReceiptsSoon(),
          // Se lo stream muore non deve restare un'eccezione non gestita né
          // spunte congelate: al prossimo rientro _resync ricarica comunque.
          onError: (_) {},
          cancelOnError: false,
        );
    // Fa valere le revoche sulla cache persistente dei testi.
    AppServices.instance.purgeInaccessible(widget.conversationId);
    // Tutte le richieste che mi riguardano (mittente o destinatario), con ogni
    // stato: le bolle di riapertura mostrano azioni (proprietario) o esito
    // (richiedente) dal vivo.
    _requestsSub = AppServices.instance.requests.watchAll().listen((list) {
      if (!mounted) return;
      // Tieni la più recente per ogni messaggio citato.
      final map = <String, ContentRequest>{};
      for (final r in list) {
        final cur = map[r.messageId];
        if (cur == null || r.createdAt.isAfter(cur.createdAt)) {
          map[r.messageId] = r;
        }
      }
      setState(() => _reqByMessage = map);
      AppServices.instance.accessTick.value++;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Tornando in primo piano (soprattutto su mobile), il socket realtime può
    // essersi chiuso mentre l'app era in background: senza far nulla si
    // perderebbero i messaggi arrivati nel frattempo, costringendo a uscire e
    // rientrare nella chat. Qui riabbono il canale e recupero gli eventuali
    // messaggi persi.
    if (state == AppLifecycleState.resumed) _resync();
  }

  void _resync() {
    final c = AppServices.instance.client;
    if (_msgChannel != null) c.removeChannel(_msgChannel!);
    _msgChannel = AppServices.instance.messages.subscribeConversation(
      widget.conversationId,
      onInsert: _onInsert,
      onUpdate: _onUpdate,
    );
    _catchUpLatest();
    // Le ricevute non dipendono più da una query per bolla: se lo stream degli
    // eventi si è interrotto in background resterebbero congelate. Le
    // ricarico al rientro (e ricontrollo le revoche).
    _loadReadReceipts();
    AppServices.instance.purgeInaccessible(widget.conversationId);
  }

  /// Ricarica l'ultima pagina e inserisce solo i messaggi non ancora presenti
  /// (dedup per id in [_onInsert]), così i nuovi compaiono subito al rientro.
  Future<void> _catchUpLatest() async {
    try {
      final page = await AppServices.instance.messages
          .fetchPage(conversationId: widget.conversationId, limit: _pageSize);
      for (final m in page.reversed) {
        _onInsert(m); // ordine crescente; ignora i duplicati
      }
    } catch (_) {
      // offline o errore transitorio: il realtime recupererà da solo.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positions.itemPositions.removeListener(_onPositions);
    AppServices.instance.reactionsTick.removeListener(_reloadReactions);
    AppServices.instance.favoritesTick.removeListener(_onFavoritesChanged);
    _reactDebounce?.cancel();
    _receiptsDebounce?.cancel();
    _highlightTimer?.cancel();
    _opensSub?.cancel();
    _requestsSub?.cancel();
    final c = AppServices.instance.client;
    if (_msgChannel != null) c.removeChannel(_msgChannel!);
    if (_reactChannel != null) c.removeChannel(_reactChannel!);
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final page = await AppServices.instance.messages
          .fetchPage(conversationId: widget.conversationId, limit: _pageSize);
      _messages
        ..clear()
        ..addAll(page.reversed); // crescente
      _hasMore = page.length == _pageSize;
      await _reloadReactions();
      if (!mounted) return;
      setState(() => _loadingInitial = false);
      if (widget.jumpToMessageId != null) {
        _didInitialScroll = true; // non farlo scavalcare dallo scroll iniziale
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _goToMessage(widget.jumpToMessageId!));
      } else {
        _scheduleInitialScroll();
      }
      _markRead();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingInitial = false;
          _error = 'Errore: $e';
        });
      }
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _messages.isEmpty) return;
    _loadingOlder = true;
    try {
      final older = await AppServices.instance.messages.fetchPage(
        conversationId: widget.conversationId,
        before: _messages.first.createdAt,
        limit: _pageSize,
      );
      if (older.isEmpty) {
        _hasMore = false;
        _loadingOlder = false;
        return;
      }
      // Lista invertita: prependere i più vecchi non sposta gli indici degli
      // item già visibili (in fondo), quindi nessun "salto" da compensare.
      setState(() => _messages.insertAll(0, older.reversed));
      _hasMore = older.length == _pageSize;
      await _reloadReactions();
    } finally {
      _loadingOlder = false;
    }
  }

  // Coalesce eventi reaction ravvicinati in un solo refetch.
  void _onReactionChange() {
    _reactDebounce?.cancel();
    _reactDebounce =
        Timer(const Duration(milliseconds: 300), _reloadReactions);
  }

  Future<void> _reloadReactions() async {
    final ids = _messages.map((m) => m.id).toList();
    final list =
        await AppServices.instance.messages.reactionsForMessages(ids);
    final map = <String, List<Reaction>>{};
    for (final r in list) {
      (map[r.messageId] ??= []).add(r);
    }
    if (mounted) setState(() => _reactions = map);
  }

  void _onInsert(Message m) {
    if (!mounted) return;
    if (m.conversationId != widget.conversationId) return;
    if (_messages.any((x) => x.id == m.id)) return;
    final mine = m.senderId == AppServices.instance.uid;
    final atBottom = _isAtBottom();
    setState(() => _messages.add(m));
    // "Foto riaperta": la bolla della foto deve rileggere subito le aperture.
    if (m.type == MessageType.reopened) {
      AppServices.instance.accessTick.value++;
    }
    _markRead();
    if (mine || atBottom) {
      _scrollToBottomSoon(); // seguo se ho inviato io o ero già in fondo
    } else if (!_isSystem(m)) {
      // Sono scrollato in alto: non trascinare, segnala col badge sul tasto.
      setState(() => _newCount++);
    }
  }

  Future<void> _loadReadReceipts() async {
    try {
      final ids = await AppServices.instance.stats
          .readMessageIds(widget.conversationId);
      if (mounted) {
        AppServices.instance.setReadReceipts(widget.conversationId, ids);
      }
    } catch (_) {}
  }

  // Più eventi di apertura ravvicinati → una sola query.
  void _loadReadReceiptsSoon() {
    _receiptsDebounce?.cancel();
    _receiptsDebounce =
        Timer(const Duration(milliseconds: 400), _loadReadReceipts);
  }

  bool _isSystem(Message m) =>
      m.type == MessageType.reopenRequest || m.type == MessageType.reopened;

  bool _isAtBottom() =>
      _positions.itemPositions.value.any((p) => p.index == 0);

  void _onUpdate(Message m) {
    if (!mounted) return;
    final idx = _messages.indexWhere((x) => x.id == m.id);
    if (idx < 0) return;
    final old = _messages[idx];
    // Invalida la cache del testo solo per le modifiche ALTRUI: le mie sono
    // già in cache (le ho appena scritte).
    if ((old.editedAt != m.editedAt || old.ciphertext != m.ciphertext) &&
        m.senderId != AppServices.instance.uid) {
      AppServices.instance.invalidateText(m.id);
    }
    setState(() => _messages[idx] = m);
  }

  void _onPositions() {
    final positions = _positions.itemPositions.value;
    if (positions.isEmpty) return;
    // reverse: gli indici ALTI sono i messaggi più VECCHI (in cima). Carico la
    // pagina precedente quando ci si avvicina alla cima.
    final maxIndex = positions.map((p) => p.index).reduce(max);
    if (maxIndex >= _messages.length - 4) _loadOlder();
    // reverse: l'indice 0 è il messaggio più recente (in fondo). Se non è
    // visibile vuol dire che ho scrollato in alto → mostro il tasto "vai giù".
    final atBottom = positions.any((p) => p.index == 0);
    if (atBottom == _showScrollDown) {
      setState(() => _showScrollDown = !atBottom);
    }
    // Tornato in fondo → azzero il contatore dei nuovi messaggi.
    if (atBottom && _newCount != 0) setState(() => _newCount = 0);
  }

  void _scrollToBottomSoon() {
    // reverse: l'indice 0 è il più recente, in fondo. alignment 0 = bordo
    // iniziale dell'item (in reverse: il BASSO) allineato al bordo iniziale
    // del viewport → il fondo dell'ultimo messaggio tocca il fondo schermo.
    void go({bool animate = true}) {
      if (!_itemScroll.isAttached || _messages.isEmpty) return;
      _itemScroll.scrollTo(
        index: 0,
        alignment: 0,
        duration: animate
            ? const Duration(milliseconds: 250)
            : Duration.zero,
        curve: Curves.easeOut,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      go();
      // Una bolla multi-riga alta o l'apertura della tastiera cambiano
      // l'altezza DOPO il primo frame: la prima animazione si fermerebbe corta
      // lasciando visibile solo un pezzetto del messaggio. Ri-allineo quando il
      // layout si è assestato.
      Future.delayed(const Duration(milliseconds: 320), () {
        if (mounted) go(animate: false);
      });
    });
  }

  int _computeFirstUnread() {
    if (_lastReadAtOpen == null) return -1;
    final me = AppServices.instance.uid;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.senderId != me && m.createdAt.isAfter(_lastReadAtOpen!)) return i;
    }
    return -1;
  }

  void _scheduleInitialScroll() {
    if (_didInitialScroll || _messages.isEmpty) return;
    _didInitialScroll = true;
    final unread = _computeFirstUnread();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_itemScroll.isAttached) return;
      if (unread >= 0) {
        // reverse: indice invertito del primo non letto (portato in vista).
        _itemScroll.jumpTo(index: _messages.length - 1 - unread);
      } else {
        // Più recente in fondo = indice 0 (naturale con reverse).
        _itemScroll.jumpTo(index: 0);
      }
    });
  }

  void _markRead() {
    if (_messages.isNotEmpty) {
      LocalPrefs.setLastRead(
          widget.conversationId, _messages.last.createdAt);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // Vero su desktop (tastiera fisica) — anche su web riflette l'OS del browser.
  bool get _hasKeyboard => const {
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform);

  String _newTempId() => 'temp_${DateTime.now().microsecondsSinceEpoch}';

  /// Destinatario con chiave pubblica AGGIORNATA, riletta al momento dell'invio:
  /// evita di cifrare con una chiave in cache vecchia (es. se il destinatario
  /// ha riallineato l'identità mentre la chat era aperta). Fallback a
  /// widget.other se il fetch fallisce.
  Future<Profile> _freshRecipient() async {
    try {
      final p =
          await AppServices.instance.profiles.getProfile(widget.other.id);
      if (p != null && p.publicKey.isNotEmpty) return p;
    } catch (_) {}
    return widget.other;
  }

  Future<void> _sendText() async {
    final t = _text.text.trim();
    if (t.isEmpty || _sending) return;
    final replyTo = _replyingTo?.id;
    // 1) Bolla OTTIMISTICA con 1 spunta ("in invio"): compare subito, prima che
    //    il server confermi. Diventerà 2 spunte quando l'insert va a buon fine.
    final tempId = _newTempId();
    final temp = Message(
      id: tempId,
      conversationId: widget.conversationId,
      senderId: AppServices.instance.uid,
      type: MessageType.text,
      ciphertext: null,
      storagePath: null,
      createdAt: DateTime.now().toUtc(),
      replyTo: replyTo,
      pending: true,
    );
    AppServices.instance.cacheText(tempId, t);
    _text.clear();
    setState(() {
      _messages.add(temp);
      _replyingTo = null;
      _sending = true;
    });
    _scrollToBottomSoon();
    try {
      final conv = await AppServices.instance.conversations
          .getConversation(widget.conversationId);
      final recipient = await _freshRecipient();
      final msg = await AppServices.instance.messages.sendText(
        conversation: conv,
        recipient: recipient,
        senderPublicKey: AppServices.instance.identity.publicKey,
        text: t,
        replyTo: replyTo,
      );
      AppServices.instance.cacheText(msg.id, t);
      // 2) Confermato dal server → sostituisci la bolla temp con quella reale.
      _replaceTemp(tempId, msg);
    } catch (e) {
      // Fallito (es. niente campo): togli la bolla e ripristina il testo.
      _removeTemp(tempId);
      _text.text = t;
      _snack('Invio non riuscito: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Sostituisce la bolla ottimistica [tempId] con il messaggio reale
  /// confermato dal server, evitando doppioni se nel frattempo è già arrivato
  /// via realtime.
  void _replaceTemp(String tempId, Message real) {
    if (!mounted) return;
    setState(() {
      final i = _messages.indexWhere((m) => m.id == tempId);
      final alreadyReal = _messages.any((m) => m.id == real.id);
      if (i >= 0) {
        if (alreadyReal) {
          _messages.removeAt(i); // l'eco realtime l'ha già inserito
        } else {
          _messages[i] = real;
        }
      } else if (!alreadyReal) {
        _messages.add(real);
      }
    });
    _markRead();
  }

  void _removeTemp(String tempId) {
    if (!mounted) return;
    setState(() => _messages.removeWhere((m) => m.id == tempId));
  }

  Future<void> _sendPhoto() async {
    if (_sending) return;
    final r = await Navigator.of(context).push<CameraResult>(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
    if (r != null) {
      await _sendPhotoBytes(r.bytes, galleryOffered: r.toGallery);
    }
  }

  /// Allega una foto esistente dalla galleria (con anteprima di conferma).
  Future<void> _attachPhoto() async {
    if (_sending) return;
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final r = await _confirmImage(bytes);
    if (r != null) await _sendPhotoBytes(r.bytes, galleryOffered: r.toGallery);
  }

  Future<CameraResult?> _confirmImage(Uint8List bytes) {
    var toGallery = false;
    return showDialog<CameraResult>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: StatefulBuilder(
          builder: (ctx, setLocal) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text('Anteprima'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            body: Center(
              child: InteractiveViewer(
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            bottomNavigationBar: Container(
              color: Colors.black,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        value: toGallery,
                        onChanged: (v) =>
                            setLocal(() => toGallery = v ?? false),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Disponibile in galleria',
                            style:
                                TextStyle(color: Colors.white, fontSize: 14)),
                        subtitle: const Text(
                            'Cifrata, senza limiti di aperture',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 12)),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.close),
                              label: const Text('Annulla'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => Navigator.pop(
                                  ctx, CameraResult(bytes, toGallery)),
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.send),
                              label: const Text('Invia'),
                            ),
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

  Future<void> _sendPhotoBytes(Uint8List bytes,
      {bool galleryOffered = false}) async {
    if (_sending) return;
    final replyTo = _replyingTo?.id;
    // Bolla OTTIMISTICA (1 spunta) subito, con l'anteprima locale: l'upload di
    // una foto può essere lento, così l'utente la vede intanto che parte.
    final tempId = _newTempId();
    final temp = Message(
      id: tempId,
      conversationId: widget.conversationId,
      senderId: AppServices.instance.uid,
      type: MessageType.photo,
      ciphertext: null,
      storagePath: null,
      createdAt: DateTime.now().toUtc(),
      replyTo: replyTo,
      pending: true,
      galleryOffered: galleryOffered,
    );
    AppServices.instance.photoEcho[tempId] = bytes;
    setState(() {
      _messages.add(temp);
      _replyingTo = null;
      _sending = true;
    });
    _scrollToBottomSoon();
    try {
      final conv = await AppServices.instance.conversations
          .getConversation(widget.conversationId);
      final recipient = await _freshRecipient();
      final msg = await AppServices.instance.messages.sendPhoto(
        conversation: conv,
        recipient: recipient,
        senderPublicKey: AppServices.instance.identity.publicKey,
        imageBytes: bytes,
        replyTo: replyTo,
        galleryOffered: galleryOffered,
      );
      AppServices.instance.photoEcho[msg.id] = bytes;
      _replaceTemp(tempId, msg); // 1 spunta → 2 spunte
      if (galleryOffered) {
        // Le foto che offro entrano SUBITO nella mia galleria, così so cosa
        // ho condiviso (best-effort).
        try {
          await AppServices.instance
              .addToGallery(msg.id, widget.conversationId);
        } catch (_) {}
      }
    } catch (e) {
      _removeTemp(tempId);
      AppServices.instance.photoEcho.remove(tempId);
      _snack('Invio foto non riuscito: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // --- Richieste (mittente approva) ----------------------------------------

  Message? _resolveMessage(String id) {
    for (final x in _messages) {
      if (x.id == id) return x;
    }
    return null;
  }

  /// Porta la vista su un messaggio (citazione, preferito, risultato di
  /// ricerca). Se non è nella pagina caricata NON scorre pagina per pagina:
  /// legge la data del messaggio e carica in UN SOLO giro di rete tutti i
  /// messaggi da lì in avanti.
  Future<void> _goToMessage(String messageId) async {
    if (_messages.indexWhere((m) => m.id == messageId) < 0) {
      setState(() => _jumping = true);
      try {
        final target =
            await AppServices.instance.messages.getMessage(messageId);
        if (target != null) {
          final page = await AppServices.instance.messages.fetchFrom(
            conversationId: widget.conversationId,
            from: target.createdAt,
          );
          if (!mounted) return;
          // Unisci senza duplicati e riordina (le bolle ottimistiche restano).
          final known = _messages.map((m) => m.id).toSet();
          final fresh = page.where((m) => !known.contains(m.id)).toList();
          if (fresh.isNotEmpty) {
            _messages
              ..addAll(fresh)
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
            await _reloadReactions();
          }
        }
      } catch (_) {
        // Fallback: prosegui con quello che c'è già in lista.
      } finally {
        if (mounted) setState(() => _jumping = false);
      }
    }

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) {
      _snack('Contenuto non più disponibile nella cronologia.');
      return;
    }
    // Dopo il merge la lista è appena cambiata: attendi il frame così
    // ScrollablePositionedList è agganciato e gli indici sono validi.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScroll.isAttached) return;
      final i = _messages.indexWhere((m) => m.id == messageId);
      if (i < 0) return;
      _itemScroll.scrollTo(
        index: _messages.length - 1 - i, // indice invertito (reverse)
        duration: const Duration(milliseconds: 300),
        alignment: 0.3,
      );
      _flashMessage(messageId);
    });
  }

  /// Evidenzia brevemente un messaggio (come WhatsApp quando tocchi una
  /// citazione).
  void _flashMessage(String messageId) {
    _highlightTimer?.cancel();
    setState(() => _highlightId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted && _highlightId == messageId) {
        setState(() => _highlightId = null);
      }
    });
  }

  ContentRequest? _pendingRequestFor(Message reopenMsg) {
    final r = _reqByMessage[reopenMsg.replyTo];
    if (r != null && r.status == RequestStatus.pending) return r;
    return null;
  }

  Future<void> _acceptReopen(Message reopenMsg) async {
    final req = _pendingRequestFor(reopenMsg);
    if (req == null) return; // già gestita
    try {
      // Rinnova la STESSA foto + inserisce il segnaposto "riaperta" in fondo.
      await AppServices.instance.acceptReopen(req, widget.conversationId);
    } catch (e) {
      if (mounted) _snack('Errore: $e');
    }
  }

  Future<void> _denyReopen(Message reopenMsg) async {
    final req = _pendingRequestFor(reopenMsg);
    if (req == null) return;
    try {
      await AppServices.instance.denyRequest(req);
    } catch (_) {}
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatSettingsScreen(conversationId: widget.conversationId),
      ),
    );
  }

  void _openStats() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatsScreen(
          conversationId: widget.conversationId,
          title: widget.other.displayName,
        ),
      ),
    );
  }

  void _openGallery() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GalleryScreen(
        conversationId: widget.conversationId,
        title: widget.other.displayName,
      ),
    ));
  }

  void _openFavorites() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FavoritesScreen(
        conversationId: widget.conversationId,
        other: widget.other,
        // Torna a questa chat (senza duplicarla) e salta al messaggio.
        onJump: _goToMessage,
      ),
    ));
  }

  void _openSearch() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MessageSearchScreen(
        conversationId: widget.conversationId,
        other: widget.other,
        // Torna a questa chat (senza duplicarla) e salta al messaggio.
        onJump: _goToMessage,
      ),
    ));
  }

  void _openSecret() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SecretGalleryScreen(
        conversationId: widget.conversationId,
        other: widget.other,
        onJump: _goToMessage,
      ),
    ));
  }

  Future<void> _toggleMute() async {
    final muted = LocalPrefs.isChatMuted(widget.conversationId);
    await AppServices.instance.setChatMuted(widget.conversationId, !muted);
    if (mounted) setState(() {});
    _snack(!muted ? 'Chat silenziata' : 'Notifiche riattivate');
  }

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = AppServices.instance.uid;
    final firstUnread = _computeFirstUnread();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              child: Text(widget.other.displayName.trim().isNotEmpty
                  ? widget.other.displayName.trim()[0].toUpperCase()
                  : '?'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.other.displayName,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cerca nella chat',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'search':
                  _openSearch();
                case 'gallery':
                  _openGallery();
                case 'stats':
                  _openStats();
                case 'favorites':
                  _openFavorites();
                case 'secret':
                  _openSecret();
                case 'protection':
                  _openSettings();
                case 'mute':
                  _toggleMute();
              }
            },
            itemBuilder: (_) {
              final muted = LocalPrefs.isChatMuted(widget.conversationId);
              return [
                _menuItem('search', Icons.search, 'Cerca nella chat'),
                _menuItem('gallery', Icons.collections_outlined, 'Galleria'),
                _menuItem('stats', Icons.bar_chart, 'Statistiche'),
                _menuItem('favorites', Icons.star_border, 'Preferiti'),
                _menuItem('secret', Icons.lock_outline, 'Galleria segreta'),
                _menuItem(
                    'protection', Icons.shield_outlined, 'Protezione'),
                const PopupMenuDivider(),
                _menuItem(
                  'mute',
                  muted ? Icons.notifications_off : Icons.notifications_none,
                  muted ? 'Riattiva notifiche' : 'Silenzia notifiche',
                ),
              ];
            },
          ),
        ],
      ),
      body: _error != null
          ? ErrorView(message: _error!)
          : Column(
              children: [
                // Niente banner in cima: le regole di protezione si vedono dal
                // menu ⋮ → Protezione, e le richieste di riapertura appaiono
                // come messaggi in chat (bolla "reopen_request").
                Expanded(child: _messageList(me, firstUnread)),
                _inputBar(),
              ],
            ),
    );
  }

  Widget _messageList(String me, int firstUnread) {
    if (_loadingInitial) return const LoadingView();
    if (_messages.isEmpty) {
      return const EmptyView(
        icon: Icons.lock_outline,
        title: 'Nessun messaggio',
        subtitle:
            'Scrivi o invia una foto. I contenuti sono cifrati end-to-end.',
      );
    }
    // reverse: true → l'indice 0 è in FONDO. Mappo l'indice invertito i sul
    // messaggio in ordine crescente, così il più recente resta in basso.
    final list = ScrollablePositionedList.builder(
      reverse: true,
      itemScrollController: _itemScroll,
      itemPositionsListener: _positions,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final ai = _messages.length - 1 - i; // indice crescente reale
        final m = _messages[ai];
        final cs = Theme.of(context).colorScheme;
        final isSystem = m.type == MessageType.reopenRequest ||
            m.type == MessageType.reopened;
        // Stato della richiesta legata alla foto citata (per entrambi i lati).
        final req = m.type == MessageType.reopenRequest
            ? _reqByMessage[m.replyTo]
            : null;
        final reopenStatus = req?.status ?? RequestStatus.pending;
        // Proprietario (il reopen_request l'ha inviato l'altro) + pendente →
        // mostra Rinnova/Rifiuta.
        final reopenActionable = m.type == MessageType.reopenRequest &&
            m.senderId != me &&
            reopenStatus == RequestStatus.pending;
        final bubble = MessageBubble(
          key: ValueKey(m.id),
          message: m,
          isMine: m.senderId == me,
          other: widget.other,
          reactions: _reactions[m.id] ?? const [],
          onReply: (msg) => setState(() => _replyingTo = msg),
          resolveReply: _resolveMessage,
          onQuoteTap: _goToMessage,
          reopenActionable: reopenActionable,
          reopenStatus: reopenStatus,
          onReopenAccept: () => _acceptReopen(m),
          onReopenDeny: () => _denyReopen(m),
        );
        // Swipe da sinistra → rispondi (come WhatsApp). Non per i messaggi di
        // sistema (richieste/riaperture): non si citano.
        Widget item = isSystem
            ? bubble
            : Dismissible(
                key: ValueKey('sw_${m.id}'),
                direction: DismissDirection.startToEnd,
                dismissThresholds: const {DismissDirection.startToEnd: 0.28},
                confirmDismiss: (_) async {
                  setState(() => _replyingTo = m);
                  return false;
                },
                background: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(Icons.reply, color: cs.primary),
                  ),
                ),
                child: bubble,
              );
        // Evidenziazione dopo il tap su una citazione.
        item = AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          color: m.id == _highlightId
              ? cs.primary.withValues(alpha: 0.18)
              : Colors.transparent,
          child: item,
        );
        // Il separatore "non letti" va SOPRA il primo non letto.
        if (ai == firstUnread && firstUnread > 0) {
          return Column(children: [_unreadDivider(context), item]);
        }
        return item;
      },
    );
    return Stack(
      children: [
        list,
        if (_jumping)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_showScrollDown)
          Positioned(
            right: 12,
            bottom: 12,
            child: Badge(
              isLabelVisible: _newCount > 0,
              label: Text('$_newCount'),
              child: FloatingActionButton.small(
                heroTag: 'scrollToLatest',
                tooltip: _newCount > 0
                    ? '$_newCount nuovi messaggi'
                    : 'Vai all\'ultimo messaggio',
                onPressed: () {
                  _scrollToBottomSoon();
                  if (_newCount != 0) setState(() => _newCount = 0);
                },
                child: const Icon(Icons.keyboard_arrow_down),
              ),
            ),
          ),
      ],
    );
  }

  Widget _unreadDivider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.primary.withValues(alpha: 0.4))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('messaggi non letti',
                style: TextStyle(color: cs.primary, fontSize: 12)),
          ),
          Expanded(child: Divider(color: cs.primary.withValues(alpha: 0.4))),
        ],
      ),
    );
  }

  void _toggleEmoji() {
    setState(() => _showEmoji = !_showEmoji);
    if (_showEmoji) FocusManager.instance.primaryFocus?.unfocus();
  }

  Widget _replyPreview() {
    final m = _replyingTo!;
    final cs = Theme.of(context).colorScheme;
    final me = AppServices.instance.uid;
    final who = m.senderId == me ? 'Tu' : widget.other.displayName;
    final label = m.type == MessageType.photo
        ? '📷 Foto'
        : (AppServices.instance.cachedText(m.id) ?? 'Messaggio');
    return Container(
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: [
          Container(width: 3, height: 34, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rispondi a $who',
                    style: TextStyle(
                        color: cs.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingTo != null) _replyPreview(),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // "Pillola" stile WhatsApp: emoji + testo (ampio) + allega +
                // fotocamera, tutto dentro un unico campo arrotondato.
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: _toggleEmoji,
                          color: cs.onSurfaceVariant,
                          icon: Icon(_showEmoji
                              ? Icons.keyboard
                              : Icons.emoji_emotions_outlined),
                          tooltip: 'Emoji',
                        ),
                        Expanded(
                          child: CallbackShortcuts(
                            bindings: {
                              const SingleActivator(LogicalKeyboardKey.enter,
                                  control: true): () => _sendText(),
                            },
                            child: TextField(
                              controller: _text,
                              minLines: 1,
                              maxLines: 6,
                              textCapitalization:
                                  TextCapitalization.sentences,
                              onTap: () {
                                if (_showEmoji) {
                                  setState(() => _showEmoji = false);
                                }
                              },
                              decoration: InputDecoration(
                                hintText: _hasKeyboard
                                    ? 'Messaggio (Ctrl+Invio per inviare)'
                                    : 'Messaggio',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 11),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _sending ? null : _attachPhoto,
                          color: cs.onSurfaceVariant,
                          icon: const Icon(Icons.attach_file),
                          tooltip: 'Allega foto',
                        ),
                        IconButton(
                          onPressed: _sending ? null : _sendPhoto,
                          color: cs.onSurfaceVariant,
                          icon: const Icon(Icons.photo_camera_outlined),
                          tooltip: 'Fotocamera',
                        ),
                        const SizedBox(width: 2),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Tasto invio rotondo (come WhatsApp).
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Material(
                    color: cs.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _sending ? null : _sendText,
                      child: Center(
                        child: _sending
                            ? SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: cs.onPrimary),
                              )
                            : Icon(Icons.send, color: cs.onPrimary, size: 22),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_showEmoji)
            SizedBox(
              height: 280,
              child: EmojiPicker(
                textEditingController: _text,
                config: brumaEmojiConfig(context),
              ),
            ),
        ],
      ),
    );
  }
}
