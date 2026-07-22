import 'dart:async';
import 'dart:convert';
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
import '../../shared/widgets.dart';
import '../camera/camera_screen.dart';
import '../settings/chat_settings_screen.dart';
import '../stats/stats_screen.dart';
import 'message_bubble.dart';

const _pageSize = 30;

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    required this.other,
  });

  final String conversationId;
  final Profile other;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _text = TextEditingController();
  final ItemScrollController _itemScroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();

  final List<Message> _messages = []; // crescente (vecchi → recenti)
  Map<String, List<Reaction>> _reactions = {};
  List<ContentRequest> _incoming = [];

  Conversation? _conversation;
  String? _error;
  bool _loadingInitial = true;
  bool _loadingOlder = false;
  bool _hasMore = true;
  bool _sending = false;
  bool _didInitialScroll = false;
  bool _showEmoji = false;
  Message? _replyingTo;
  DateTime? _lastReadAtOpen;

  RealtimeChannel? _msgChannel;
  RealtimeChannel? _reactChannel;
  Timer? _reactDebounce;
  StreamSubscription? _opensSub;
  StreamSubscription? _requestsSub;
  StreamSubscription? _mineReqSub;

  @override
  void initState() {
    super.initState();
    _lastReadAtOpen = LocalPrefs.lastRead(widget.conversationId);
    _positions.itemPositions.addListener(_onPositions);
    _loadConversation();
    _loadInitial();
    _msgChannel = AppServices.instance.messages.subscribeConversation(
      widget.conversationId,
      onInsert: _onInsert,
      onUpdate: _onUpdate,
    );
    _reactChannel =
        AppServices.instance.messages.subscribeReactions(_onReactionChange);
    _opensSub = AppServices.instance.stats
        .watchMyOpenEvents()
        .listen((_) => AppServices.instance.openEventsTick.value++);
    _requestsSub = AppServices.instance.requests.watchIncoming().listen((list) {
      if (!mounted) return;
      setState(() => _incoming =
          list.where((r) => r.requesterId == widget.other.id).toList());
    });
    // Lato destinatario: quando il mittente gestisce una mia richiesta,
    // aggiorna dal vivo lo stato di accesso delle bolle foto.
    _mineReqSub = AppServices.instance.requests
        .watchMine()
        .listen((_) => AppServices.instance.accessTick.value++);
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onPositions);
    _reactDebounce?.cancel();
    _opensSub?.cancel();
    _requestsSub?.cancel();
    _mineReqSub?.cancel();
    final c = AppServices.instance.client;
    if (_msgChannel != null) c.removeChannel(_msgChannel!);
    if (_reactChannel != null) c.removeChannel(_reactChannel!);
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    try {
      final c = await AppServices.instance.conversations
          .getConversation(widget.conversationId);
      if (mounted) setState(() => _conversation = c);
    } catch (_) {}
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
      _scheduleInitialScroll();
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
    setState(() => _messages.add(m));
    _markRead();
    _scrollToBottomSoon(); // su invio E ricezione: vai in fondo
  }

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
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // reverse: l'indice 0 è il più recente, in fondo → posizione esatta.
      if (_itemScroll.isAttached && _messages.isNotEmpty) {
        _itemScroll.scrollTo(
          index: 0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
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

  Future<void> _sendText() async {
    final t = _text.text.trim();
    if (t.isEmpty || _sending) return;
    final replyTo = _replyingTo?.id;
    setState(() => _sending = true);
    _text.clear();
    try {
      final conv = await AppServices.instance.conversations
          .getConversation(widget.conversationId);
      final msg = await AppServices.instance.messages.sendText(
        conversation: conv,
        recipient: widget.other,
        senderPublicKey: AppServices.instance.identity.publicKey,
        text: t,
        replyTo: replyTo,
      );
      AppServices.instance.cacheText(msg.id, t);
      if (mounted) setState(() => _replyingTo = null);
    } catch (e) {
      _text.text = t;
      _snack('Invio non riuscito: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendPhoto() async {
    if (_sending) return;
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
    if (bytes != null) await _sendPhotoBytes(bytes);
  }

  /// Allega una foto esistente dalla galleria (con anteprima di conferma).
  Future<void> _attachPhoto() async {
    if (_sending) return;
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final ok = await _confirmImage(bytes);
    if (ok == true) await _sendPhotoBytes(bytes);
  }

  Future<bool?> _confirmImage(Uint8List bytes) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Anteprima'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx, false),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
          // Barra fissa: tasti affiancati e sempre visibili (anche web mobile).
          bottomNavigationBar: Container(
            color: Colors.black,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.close),
                        label: const Text('Annulla'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.send),
                        label: const Text('Invia'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendPhotoBytes(Uint8List bytes) async {
    if (_sending) return;
    final replyTo = _replyingTo?.id;
    setState(() => _sending = true);
    try {
      final conv = await AppServices.instance.conversations
          .getConversation(widget.conversationId);
      final msg = await AppServices.instance.messages.sendPhoto(
        conversation: conv,
        recipient: widget.other,
        senderPublicKey: AppServices.instance.identity.publicKey,
        imageBytes: bytes,
        replyTo: replyTo,
      );
      AppServices.instance.photoEcho[msg.id] = bytes;
      if (mounted) setState(() => _replyingTo = null);
    } catch (e) {
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

  Future<Message?> _findMessage(String id) async {
    final local = _resolveMessage(id);
    if (local != null) return local;
    return AppServices.instance.messages.getMessage(id);
  }

  Future<void> _renew(ContentRequest req) async {
    try {
      await AppServices.instance.requests.renew(req.messageId);
      await AppServices.instance.requests.resolve(req.id, 'renewed');
      _snack('Limiti rinnovati.');
    } catch (e) {
      _snack('Rinnovo non riuscito: $e');
    }
  }

  Future<void> _resend(ContentRequest req) async {
    try {
      final m = await _findMessage(req.messageId);
      if (m == null) {
        _snack('Messaggio non trovato.');
        return;
      }
      final conv = await AppServices.instance.conversations
          .getConversation(widget.conversationId);
      final bytes = await AppServices.instance.openContentBytes(m);
      final pub = AppServices.instance.identity.publicKey;
      if (m.type == MessageType.text) {
        final sent = await AppServices.instance.messages.sendText(
            conversation: conv,
            recipient: widget.other,
            senderPublicKey: pub,
            text: utf8.decode(bytes));
        AppServices.instance.cacheText(sent.id, utf8.decode(bytes));
      } else {
        final sent = await AppServices.instance.messages.sendPhoto(
            conversation: conv,
            recipient: widget.other,
            senderPublicKey: pub,
            imageBytes: bytes);
        AppServices.instance.photoEcho[sent.id] = bytes;
      }
      await AppServices.instance.requests.resolve(req.id, 'resent');
      _snack('Contenuto reinviato.');
    } catch (e) {
      _snack('Reinvio non riuscito: $e');
    }
  }

  Future<void> _deny(ContentRequest req) async {
    try {
      await AppServices.instance.requests.resolve(req.id, 'denied');
    } catch (_) {}
  }

  /// Porta la vista sul messaggio a cui si riferisce la richiesta.
  Future<void> _goToMessage(String messageId) async {
    // Carica pagine più vecchie finché il messaggio non è nella lista (max 10).
    var attempts = 0;
    while (_messages.indexWhere((m) => m.id == messageId) < 0 &&
        _hasMore &&
        attempts < 10) {
      await _loadOlder();
      attempts++;
    }
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx >= 0 && _itemScroll.isAttached) {
      _itemScroll.scrollTo(
        index: _messages.length - 1 - idx, // indice invertito (reverse)
        duration: const Duration(milliseconds: 300),
        alignment: 0.3,
      );
    } else {
      _snack('Contenuto non più disponibile nella cronologia.');
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatSettingsScreen(conversationId: widget.conversationId),
      ),
    );
    _loadConversation();
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
          Builder(builder: (_) {
            final muted = LocalPrefs.isChatMuted(widget.conversationId);
            return IconButton(
              tooltip: muted ? 'Riattiva notifiche' : 'Silenzia notifiche',
              onPressed: () async {
                await AppServices.instance
                    .setChatMuted(widget.conversationId, !muted);
                if (mounted) setState(() {});
                _snack(!muted ? 'Chat silenziata' : 'Notifiche riattivate');
              },
              icon: Icon(muted
                  ? Icons.notifications_off
                  : Icons.notifications_none),
            );
          }),
          IconButton(
            tooltip: 'Statistiche',
            onPressed: _openStats,
            icon: const Icon(Icons.bar_chart),
          ),
          IconButton(
            tooltip: 'Impostazioni protezione',
            onPressed: _openSettings,
            icon: const Icon(Icons.shield_outlined),
          ),
        ],
      ),
      body: _error != null
          ? ErrorView(message: _error!)
          : Column(
              children: [
                if (_conversation != null) _protectionBanner(_conversation!),
                if (_incoming.isNotEmpty) _requestBanner(_incoming.first),
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
    return ScrollablePositionedList.builder(
      reverse: true,
      itemScrollController: _itemScroll,
      itemPositionsListener: _positions,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final ai = _messages.length - 1 - i; // indice crescente reale
        final m = _messages[ai];
        final bubble = MessageBubble(
          key: ValueKey(m.id),
          message: m,
          isMine: m.senderId == me,
          other: widget.other,
          reactions: _reactions[m.id] ?? const [],
          onReply: (msg) => setState(() => _replyingTo = msg),
          resolveReply: _resolveMessage,
          onQuoteTap: _goToMessage,
        );
        // Il separatore "non letti" va SOPRA il primo non letto (nell'item, il
        // Column è in orientamento normale anche con reverse).
        if (ai == firstUnread && firstUnread > 0) {
          return Column(children: [_unreadDivider(context), bubble]);
        }
        return bubble;
      },
    );
  }

  Widget _requestBanner(ContentRequest req) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.tertiaryContainer,
      child: InkWell(
        onTap: () => _goToMessage(req.messageId),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.help_outline, color: cs.onTertiaryContainer, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${widget.other.displayName} ha chiesto di riaprire un contenuto. '
                  'Tocca per vederlo.',
                  style: TextStyle(color: cs.onTertiaryContainer, fontSize: 13),
                ),
              ),
              TextButton(
                  onPressed: () => _renew(req), child: const Text('Rinnova')),
              TextButton(
                  onPressed: () => _resend(req), child: const Text('Reinvia')),
              IconButton(
                tooltip: 'Ignora',
                onPressed: () => _deny(req),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
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

  Widget _protectionBanner(Conversation c) {
    final cs = Theme.of(context).colorScheme;
    final opens = c.maxOpens <= 0 ? '∞' : '${c.maxOpens}';
    final dur = c.maxDurationSeconds <= 0 ? '∞' : '${c.maxDurationSeconds}s';
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(c.protectionEnabled ? Icons.shield : Icons.shield_outlined,
              size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              c.protectionEnabled
                  ? 'Foto protette · $opens aperture · $dur'
                  : 'Protezione foto disattivata',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
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
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingTo != null) _replyPreview(),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: _toggleEmoji,
                  icon: Icon(_showEmoji
                      ? Icons.keyboard
                      : Icons.emoji_emotions_outlined),
                  tooltip: 'Emoji',
                ),
                IconButton(
                  onPressed: _sending ? null : _sendPhoto,
                  icon: const Icon(Icons.photo_camera),
                  tooltip: 'Fotocamera',
                ),
                IconButton(
                  onPressed: _sending ? null : _attachPhoto,
                  icon: const Icon(Icons.attach_file),
                  tooltip: 'Allega foto',
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
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      onTap: () {
                        if (_showEmoji) setState(() => _showEmoji = false);
                      },
                      decoration: InputDecoration(
                        hintText: _hasKeyboard
                            ? 'Messaggio (Ctrl+Invio per inviare)'
                            : 'Messaggio',
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  onPressed: _sending ? null : _sendText,
                  icon: _sending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
          if (_showEmoji)
            SizedBox(
              height: 280,
              child: EmojiPicker(textEditingController: _text),
            ),
        ],
      ),
    );
  }
}
