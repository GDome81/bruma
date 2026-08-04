import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sodium_libs/sodium_libs.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'crypto/crypto_service.dart';
import 'fcm.dart';
import 'local_prefs.dart';
import 'models/models.dart';
import 'notifications.dart';
import 'notify_platform.dart';
import 'secure_screen.dart';
import 'secure_store/key_store.dart';
import 'secure_store/text_store.dart';
import 'supabase/access_repository.dart';
import 'supabase/auth_repository.dart';
import 'supabase/contacts_repository.dart';
import 'supabase/conversations_repository.dart';
import 'supabase/gallery_repository.dart';
import 'supabase/messages_repository.dart';
import 'supabase/profile_repository.dart';
import 'supabase/requests_repository.dart';
import 'supabase/stats_repository.dart';
import 'supabase/storage_repository.dart';

/// Service locator: costruito una volta all'avvio, tiene crypto, storage
/// sicuro, client Supabase, repository e l'identita' corrente in memoria.
class AppServices {
  AppServices._({
    required this.sodium,
    required this.crypto,
    required this.keyStore,
    required this.client,
    required this.auth,
    required this.profiles,
    required this.contacts,
    required this.conversations,
    required this.messages,
    required this.access,
    required this.stats,
    required this.storage,
    required this.requests,
    required this.gallery,
  });

  static late AppServices instance;

  /// Chiave del Navigator radice: permette al panic button (che vive in un
  /// overlay sopra il Navigator) di chiudere tutte le route pushate.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final Sodium sodium;
  final CryptoService crypto;
  final KeyStore keyStore;
  final SupabaseClient client;

  final AuthRepository auth;
  final ProfileRepository profiles;
  final ContactsRepository contacts;
  final ConversationsRepository conversations;
  final MessagesRepository messages;
  final AccessRepository access;
  final StatsRepository stats;
  final StorageRepository storage;
  final RequestsRepository requests;
  final GalleryRepository gallery;

  KeyPair? _identity;
  Profile? myProfile;

  /// Eco in memoria (solo sessione, MAI su disco) dei propri contenuti inviati,
  /// cosi' il mittente rivede cio' che ha mandato senza consumare il contatore
  /// del destinatario e senza scrivere il testo in chiaro sul dispositivo.
  final Map<String, String> textEcho = {};
  final Map<String, Uint8List> photoEcho = {};

  /// Cache dei testi NON protetti già decifrati. Vive in RAM ed è PERSISTITA
  /// cifrata a riposo (vedi [TextStore]): senza persistenza ogni riavvio
  /// costringeva a un giro di rete per messaggio (scroll a scatti, ricerca
  /// lenta). Le foto restano invece solo in RAM.
  final Map<String, String> _decryptedText = {};

  TextStore? _textStoreCache;
  TextStore get _textStore => _textStoreCache ??= TextStore(crypto);
  Timer? _textFlush;

  /// Solo i messaggi da scrivere/rimuovere al prossimo flush: si salva ciò che
  /// è cambiato, non tutto l'archivio.
  final Set<String> _dirtyTexts = {};
  final Set<String> _removedTexts = {};

  /// A quale account appartengono i testi attualmente in RAM. Serve perché la
  /// sessione può cadere SENZA passare da signOut() (refresh token scaduto,
  /// logout offline che solleva): senza questo marcatore i testi del vecchio
  /// utente resterebbero in memoria e verrebbero persistiti sotto il NUOVO uid.
  String? _textCacheUid;

  /// Cache in RAM (MAI su disco) dei byte in chiaro di foto già aperte: evita
  /// di ri-scaricare e ri-decifrare la stessa foto a ogni rebuild (galleria che
  /// sfarfalla) e di consumare aperture. Invalidata su revoca/rimozione/uscita.
  final Map<String, Uint8List> _openedPhotoCache = {};

  /// Incrementa a ogni evento di apertura ricevuto via Realtime: le ricevute
  /// di lettura (doppia spunta) vi si agganciano per aggiornarsi dal vivo.
  final ValueNotifier<int> openEventsTick = ValueNotifier<int>(0);

  /// Ids dei miei messaggi già letti dal destinatario, caricati in UNA query
  /// per conversazione. Le bolle li leggono da qui senza interrogare il server
  /// una per una (era la causa di decine di richieste per schermata).
  /// Indicizzati per conversazione: due chat aperte in pila non si sovrascrivono
  /// le spunte a vicenda.
  final Map<String, Set<String>> _readByConversation = {};

  /// Data del mio messaggio più RECENTE che risulta letto, per conversazione.
  /// Serve perché l'evento di lettura nasce solo quando l'app dell'altro
  /// DECIFRA quel messaggio, e decifra solo le bolle che costruisce: un
  /// messaggio rimasto appena fuori dallo schermo non risultava letto nemmeno
  /// se quelli dopo lo erano (spunte "2 poi 3", impossibili da spiegare).
  final Map<String, DateTime> _readWatermark = {};

  bool isReadByRecipient(String messageId) {
    for (final ids in _readByConversation.values) {
      if (ids.contains(messageId)) return true;
    }
    return false;
  }

  /// Soglia monotòna: non torna mai indietro.
  void setReadWatermark(String conversationId, DateTime upTo) {
    final cur = _readWatermark[conversationId];
    if (cur != null && !upTo.isAfter(cur)) return;
    _readWatermark[conversationId] = upTo;
    openEventsTick.value++;
  }

  /// Vero se l'altro ha letto qualcosa di PIÙ RECENTE di [createdAt]: allora era
  /// in chat oltre quel punto, quindi ha visto anche i messaggi precedenti.
  ///
  /// Vale solo per i TESTI. Per le foto no: aprirle è un atto deliberato e
  /// consuma un'apertura, quindi non si può dedurre — dedurlo mostrerebbe una
  /// foto come "vista" senza che nessuno l'abbia aperta, falsando anche le
  /// statistiche di visualizzazione.
  bool isReadUpTo(String conversationId, DateTime createdAt) {
    final wm = _readWatermark[conversationId];
    return wm != null && !createdAt.isAfter(wm);
  }

  void setReadReceipts(String conversationId, Iterable<String> ids) {
    // UNIONE, non sostituzione: "letto" è monotono (una volta letto resta
    // letto), così una risposta parziale non può far tornare "non letto" un
    // messaggio già segnato.
    (_readByConversation[conversationId] ??= <String>{}).addAll(ids);
    openEventsTick.value++; // le spunte si ridisegnano
  }

  /// Incrementa quando una mia richiesta di contenuto viene gestita
  /// (rinnovo/reinvio): le bolle foto rileggono lo stato di accesso dal vivo.
  final ValueNotifier<int> accessTick = ValueNotifier<int>(0);

  /// Bump dopo aver messo/tolto una reaction: la conversazione ricarica subito
  /// le reactions senza aspettare l'eco realtime (che a volte tarda).
  final ValueNotifier<int> reactionsTick = ValueNotifier<int>(0);

  /// Bump quando cambia l'appartenenza alla galleria (aggiunta/rimozione/offerta):
  /// le bolle foto rileggono lo stato "in galleria".
  final ValueNotifier<int> galleryTick = ValueNotifier<int>(0);

  /// Bump quando un messaggio viene aggiunto/tolto dai preferiti: la chat
  /// aggiorna dal vivo la stellina accanto alle bolle.
  final ValueNotifier<int> favoritesTick = ValueNotifier<int>(0);

  /// Modalità "panic": quando attiva, l'app mostra un decoy (calcolatrice) al
  /// posto del login finché non si sblocca. Persistita in LocalPrefs.
  final ValueNotifier<bool> panicMode = ValueNotifier<bool>(false);

  Future<void> setPanic(bool value) async {
    panicMode.value = value;
    await LocalPrefs.setPanic(value);
  }

  /// Attiva il panic: nasconde tutto dietro il decoy (calcolatrice) MA NON
  /// disconnette. Sbloccando (PIN o long-press) si torna all'app già loggata.
  Future<void> panic() async {
    await setPanic(true);
  }

  String? cachedText(String messageId) => _decryptedText[messageId];

  void cacheText(String messageId, String value) {
    // Le bolle ottimistiche hanno id provvisori ("temp_…"): non persisterle,
    // altrimenti resterebbero orfane nella cache.
    _decryptedText[messageId] = value;
    if (messageId.startsWith('temp_')) return;
    _dirtyTexts.add(messageId);
    _removedTexts.remove(messageId);
    _scheduleTextFlush();
  }

  /// Coalesce le scritture (durante uno scroll arrivano decine di cacheText),
  /// MA con un tetto: il debounce da solo si riarmava a ogni scrittura, quindi
  /// un'indicizzazione lunga poteva rinviarlo all'infinito e perdere tutto se
  /// l'app veniva chiusa.
  static const _flushDebounce = Duration(seconds: 3);
  static const _flushMaxDelay = Duration(seconds: 15);
  DateTime? _firstPendingWrite;

  void _scheduleTextFlush() {
    final now = DateTime.now();
    _firstPendingWrite ??= now;
    if (now.difference(_firstPendingWrite!) >= _flushMaxDelay) {
      _textFlush?.cancel();
      _flushTextCache();
      return;
    }
    _textFlush?.cancel();
    _textFlush = Timer(_flushDebounce, _flushTextCache);
  }

  /// Scrive subito ciò che è in attesa. Da chiamare quando l'app passa in
  /// background: Android congela e uccide i processi senza preavviso.
  Future<void> flushTextCacheNow() async {
    _textFlush?.cancel();
    await _flushTextCache();
  }

  Future<void> _flushTextCache() async {
    final currentUid = client.auth.currentUser?.id;
    // Non scrivere se i testi in RAM appartengono a un altro account.
    if (currentUid == null || _textCacheUid != currentUid) return;
    // Solo le modifiche: niente riscrittura dell'intero archivio.
    final toWrite = <String, String>{};
    for (final id in _dirtyTexts) {
      final t = _decryptedText[id];
      if (t != null) toWrite[id] = t;
    }
    final toRemove = _removedTexts.toList();
    _dirtyTexts.clear();
    _removedTexts.clear();
    _firstPendingWrite = null;
    // Se la scrittura fallisce gli id tornano in coda: prima venivano svuotati
    // prima dell'await e un errore li perdeva per sempre (una cancellazione
    // persa lascia sul disco un contenuto revocato).
    if (toWrite.isNotEmpty) {
      final ok = await _textStore.put(currentUid, toWrite);
      if (!ok) {
        _dirtyTexts.addAll(toWrite.keys);
        _firstPendingWrite ??= DateTime.now();
      }
    }
    if (toRemove.isNotEmpty) {
      final ok = await _textStore.removeIds(currentUid, toRemove);
      if (!ok) {
        _removedTexts.addAll(toRemove);
        _firstPendingWrite ??= DateTime.now();
      }
    }
    // Se durante la scrittura si è usciti (o cambiato account), rimuovi ciò che
    // è appena stato scritto: un flush in volo non deve resuscitare l'archivio.
    if (_textCacheUid != currentUid) await _textStore.clear(currentUid);
  }

  /// Carica la cache testi persistita per l'utente corrente.
  Future<void> _loadTextCache(String currentUid) async {
    // Cambio account senza passare da signOut: butta tutto ciò che è in RAM,
    // altrimenti i testi del vecchio utente finirebbero salvati sotto questo.
    if (_textCacheUid != null && _textCacheUid != currentUid) {
      _decryptedText.clear();
      textEcho.clear();
      photoEcho.clear();
      _openedPhotoCache.clear();
      _readByConversation.clear();
      // Anche le code: erano riferite all'account precedente, e una
      // cancellazione rimasta in sospeso non deve andare perduta né essere
      // applicata al nuovo account.
      _textFlush?.cancel();
      _dirtyTexts.clear();
      _removedTexts.clear();
      _firstPendingWrite = null;
    }
    _textCacheUid = currentUid;
    // Elimina l'archivio a blob dei rilasci precedenti: restava sul dispositivo
    // ancora decifrabile, e il logout non lo toccava più.
    unawaited(_textStore.purgeLegacyBlob(currentUid));
    try {
      final stored = await _textStore.load(currentUid);
      // Non sovrascrivere ciò che è già stato decifrato in questa sessione.
      for (final e in stored.entries) {
        _decryptedText.putIfAbsent(e.key, () => e.value);
      }
    } catch (_) {}
  }

  /// Coppia di chiavi dell'utente corrente (per unwrap delle chiavi).
  KeyPair get identity => _identity!;
  bool get hasLocalIdentity => _identity != null;
  bool get hasProfile => myProfile != null;

  String get uid => client.auth.currentUser!.id;

  /// Sostituisce l'identita' disponendo in modo deterministico la chiave
  /// privata precedente (azzera la memoria protetta libsodium).
  void _setIdentity(KeyPair? kp) {
    _identity?.secretKey.dispose();
    _identity = kp;
  }

  static Future<void> init() async {
    final sodium = await SodiumInit.init();
    final crypto = CryptoService(sodium);
    final keyStore = KeyStore(crypto);
    final client = Supabase.instance.client;

    final profiles = ProfileRepository(client);
    final storage = StorageRepository(client);
    final messages = MessagesRepository(client, crypto, storage);

    instance = AppServices._(
      sodium: sodium,
      crypto: crypto,
      keyStore: keyStore,
      client: client,
      auth: AuthRepository(client),
      profiles: profiles,
      contacts: ContactsRepository(client, profiles),
      conversations: ConversationsRepository(client, profiles, messages),
      messages: messages,
      access: AccessRepository(client),
      stats: StatsRepository(client),
      storage: storage,
      requests: RequestsRepository(client),
      gallery: GalleryRepository(client),
    );
  }

  /// Carica identita' locale + profilo remoto per l'utente autenticato.
  /// Da chiamare dopo il login e all'avvio con sessione attiva.
  Future<void> refreshIdentity() async {
    final currentUid = client.auth.currentUser?.id;
    if (currentUid == null) {
      _setIdentity(null);
      myProfile = null;
      return;
    }
    _setIdentity(await keyStore.load(currentUid));
    // Testi già decifrati in sessioni precedenti: riaprire le chat è immediato.
    // NON attende: con un archivio grande l'avvio resterebbe fermo a decifrare
    // migliaia di righe. Finché non è pronto le bolle ricadono sul server.
    unawaited(_loadTextCache(currentUid));
    // Timeout: se il server è lento, IdentityGate mostra un errore con
    // "Riprova" invece di restare all'infinito su "Carico l'identità…".
    myProfile =
        await profiles.getMyProfile().timeout(const Duration(seconds: 20));
  }

  /// Onboarding: genera la coppia di chiavi, salva la privata sul dispositivo,
  /// crea il profilo remoto con la chiave pubblica.
  Future<void> createIdentity(String displayName) async {
    final kp = crypto.generateIdentityKeyPair();
    await keyStore.save(uid, kp);
    await profiles.createProfile(
      displayName: displayName.trim(),
      publicKeyB64: crypto.encodePublicKey(kp.publicKey),
    );
    _setIdentity(kp);
    myProfile = await profiles.getMyProfile();
  }

  /// Recupero identita' persa (chiave locale assente): genera una nuova coppia
  /// e allinea la chiave pubblica sul profilo. I contenuti ricevuti in
  /// precedenza non saranno piu' apribili.
  Future<void> regenerateIdentity() async {
    final kp = crypto.generateIdentityKeyPair();
    await keyStore.save(uid, kp);
    await profiles.updatePublicKey(crypto.encodePublicKey(kp.publicKey));
    _setIdentity(kp);
  }

  // --- Allineamento identità (dispositivo ↔ account) ----------------------

  /// Chiave pubblica di QUESTO dispositivo (base64), o null se assente.
  String? get localPublicKeyB64 =>
      _identity == null ? null : crypto.encodePublicKey(_identity!.publicKey);

  /// Chiave pubblica registrata sull'ACCOUNT (profilo remoto).
  String? get accountPublicKeyB64 => myProfile?.publicKey;

  /// Vero se la chiave del dispositivo combacia con quella dell'account. Se una
  /// delle due manca, non segnaliamo disallineamento (true).
  bool get deviceKeyMatchesAccount {
    final l = localPublicKeyB64;
    final a = accountPublicKeyB64;
    if (l == null || a == null || a.isEmpty) return true;
    return l == a;
  }

  /// Impronta leggibile di una chiave pubblica base64 (confronto tra device).
  String fingerprintOf(String? b64) {
    if (b64 == null || b64.isEmpty) return '—';
    try {
      return crypto.fingerprint(crypto.decodePublicKey(b64));
    } catch (_) {
      return '—';
    }
  }

  /// Rende la chiave di QUESTO dispositivo quella ufficiale dell'account: da qui
  /// i nuovi messaggi verranno cifrati per questa chiave e il dispositivo torna
  /// a decifrarli. Gli ALTRI dispositivi dovranno importare questa identità.
  Future<void> makeThisDeviceCanonical() async {
    await profiles.updatePublicKey(crypto.encodePublicKey(identity.publicKey));
    myProfile = await profiles.getMyProfile();
  }

  /// Esporta l'identità corrente come stringa cifrata con [password] (con il
  /// tag dell'account, per rifiutare l'import su un account diverso).
  String exportIdentity(String password) =>
      crypto.exportIdentity(identity, password, tag: uid);

  /// Importa un'identità (da backup + password): la salva sul dispositivo,
  /// allinea la chiave pubblica sul profilo e la rende quella corrente.
  /// Da qui in poi i contenuti cifrati per QUELLA identità sono apribili.
  Future<void> importIdentity(String data, String password) async {
    // Lancia IdentityException (messaggio generico) su dati/password errati.
    final imported = crypto.importIdentity(data, password);
    // Rifiuta se l'identità è di un ALTRO account, con lo STESSO errore generico
    // (non riveliamo che appartiene ad altri).
    if (imported.originUid.isNotEmpty && imported.originUid != uid) {
      throw const IdentityException();
    }
    final kp = imported.keyPair;
    await keyStore.save(uid, kp);
    await profiles.updatePublicKey(crypto.encodePublicKey(kp.publicKey));
    _setIdentity(kp);
    myProfile = await profiles.getMyProfile();
    // Svuota le cache (i contenuti erano cifrati con la vecchia chiave), anche
    // quella persistita: i testi di prima non sono più pertinenti.
    _textFlush?.cancel();
    _dirtyTexts.clear();
    _removedTexts.clear();
    await _textStore.clear(uid);
    _decryptedText.clear();
    textEcho.clear();
    photoEcho.clear();
  }

  /// Apre un contenuto: richiede la chiave al server (check atomico), la apre
  /// con la chiave privata locale e decifra IN RAM. Restituisce i byte in
  /// chiaro (che il chiamante deve scartare dopo l'uso; per il testo:
  /// utf8.decode). Puo' lanciare [KeyRequestException] se l'apertura e' negata.
  ///
  /// ATTENZIONE: per i contenuti protetti ogni chiamata consuma un'apertura.
  Future<Uint8List> openContentBytes(Message m) async {
    final wrapped = await access.requestKey(m.id);
    final key = crypto.unwrapKey(wrapped, identity);
    try {
      if (m.type == MessageType.text) {
        return crypto.decryptContent(crypto.decodeBlob(m.ciphertext!), key);
      } else {
        final blob = await messages.downloadPhotoCipher(m.storagePath!);
        return crypto.decryptContent(blob, key);
      }
    } finally {
      key.dispose();
    }
  }

  /// Byte in chiaro di una foto già aperti in questa sessione, se presenti in
  /// cache. Permette a miniatura e visualizzatore di mostrarli all'istante.
  Uint8List? cachedPhotoBytes(String messageId) => _openedPhotoCache[messageId];

  /// Come [openContentBytes] ma memorizza il risultato: chiamate successive per
  /// la stessa foto tornano dalla cache (niente rete, niente re-decifra). Usare
  /// solo per foto senza limiti (galleria/eco), non per contenuti a consumo.
  Future<Uint8List> openPhotoBytesCached(Message m) async {
    final hit = _openedPhotoCache[m.id];
    if (hit != null) return hit;
    final bytes = await openContentBytes(m);
    _openedPhotoCache[m.id] = bytes;
    return bytes;
  }

  // --- Richieste di riapertura (il mittente approva) -----------------------
  // Centralizzate qui così sia la conversazione sia la schermata Notifiche
  // possono gestirle allo stesso modo.

  Future<void> renewRequest(ContentRequest req) async {
    await requests.renew(req.messageId);
    await requests.resolve(req.id, 'renewed');
  }

  Future<void> denyRequest(ContentRequest req) async {
    await requests.resolve(req.id, 'denied');
  }

  /// Chiede la riapertura di una foto: registra la richiesta (per Notifiche/
  /// badge cross-chat) E inserisce un messaggio di sistema in chat, così
  /// entrambi la vedono nel flusso della conversazione.
  Future<void> requestReopen({
    required String photoMessageId,
    required String conversationId,
    required String ownerId,
  }) async {
    await requests.createRequest(messageId: photoMessageId, ownerId: ownerId);
    await messages.sendReopenRequest(
        conversationId: conversationId, photoMessageId: photoMessageId);
  }

  /// Accetta una richiesta: rinnova la STESSA foto (nessun reinvio), risolve la
  /// richiesta e inserisce in fondo alla chat il segnaposto "foto riaperta".
  Future<void> acceptReopen(
      ContentRequest req, String conversationId) async {
    await requests.renew(req.messageId);
    await requests.resolve(req.id, 'renewed');
    await messages.sendReopenedMarker(
        conversationId: conversationId, photoMessageId: req.messageId);
    accessTick.value++; // la bolla mostra subito le aperture rinnovate
  }

  /// Reinvia il contenuto al richiedente: riapre la PROPRIA copia e la rimanda.
  Future<void> resendRequest(ContentRequest req) async {
    final m = await messages.getMessage(req.messageId);
    if (m == null) throw Exception('Messaggio non trovato');
    final conv = await conversations.getConversation(m.conversationId);
    final recipient = await profiles.getProfile(req.requesterId);
    if (recipient == null) throw Exception('Destinatario non trovato');
    final bytes = await openContentBytes(m);
    final pub = identity.publicKey;
    if (m.type == MessageType.text) {
      final sent = await messages.sendText(
          conversation: conv,
          recipient: recipient,
          senderPublicKey: pub,
          text: utf8.decode(bytes));
      cacheText(sent.id, utf8.decode(bytes));
    } else {
      final sent = await messages.sendPhoto(
          conversation: conv,
          recipient: recipient,
          senderPublicKey: pub,
          imageBytes: bytes);
      photoEcho[sent.id] = bytes;
    }
    await requests.resolve(req.id, 'resent');
  }

  /// Riabilita in chat una MIA foto già inviata: rinnova i limiti sulla copia
  /// del DESTINATARIO (STESSA foto: nessun reinvio, nessun duplicato, nessuna
  /// nuova statistica) e inserisce in fondo alla chat il segnaposto
  /// "foto riaperta".
  Future<void> reopenPhotoInChat(Message m) async {
    await requests.renew(m.id);
    await messages.sendReopenedMarker(
        conversationId: m.conversationId, photoMessageId: m.id);
    accessTick.value++; // le bolle rileggono le aperture rimaste
  }

  /// Decifra i TESTI di più messaggi riusando la cache, con un tetto di
  /// richieste in volo (il server fa un check-and-increment per ogni chiave:
  /// centinaia di richieste in parallelo lo metterebbero in contesa).
  /// I messaggi non decifrabili (revocati o cifrati per un'altra identità)
  /// vengono semplicemente saltati.
  /// [onBatch] viene chiamato dopo ogni gruppo con i testi appena decifrati e
  /// quanti ne restano: permette a chi chiama (la ricerca) di mostrare
  /// risultati e avanzamento invece di uno spinner muto su migliaia di messaggi.
  Future<Map<String, String>> decryptTexts(
    List<Message> list, {
    int concurrency = 6,
    void Function(Map<String, String> batch, int done, int total)? onBatch,
  }) async {
    final out = <String, String>{};
    final todo = <Message>[];
    for (final m in list) {
      final cached = cachedText(m.id) ?? textEcho[m.id];
      if (cached != null) {
        out[m.id] = cached;
      } else {
        todo.add(m);
      }
    }
    for (var i = 0; i < todo.length; i += concurrency) {
      final end =
          (i + concurrency) > todo.length ? todo.length : i + concurrency;
      final slice = todo.sublist(i, end);
      final texts = await Future.wait(slice.map((m) async {
        try {
          // Timeout per messaggio: senza, una singola richiesta appesa
          // bloccherebbe l'indicizzazione per sempre (spinner infinito).
          final bytes = await openContentBytes(m)
              .timeout(const Duration(seconds: 15));
          final t = utf8.decode(bytes);
          cacheText(m.id, t);
          return t;
        } catch (_) {
          return null; // revocato / altra identità / timeout → salta
        }
      }));
      final batch = <String, String>{};
      for (var j = 0; j < slice.length; j++) {
        final t = texts[j];
        if (t != null) {
          out[slice[j].id] = t;
          batch[slice[j].id] = t;
        }
      }
      onBatch?.call(batch, end, todo.length);
    }
    return out;
  }

  // --- Galleria (wrapper che notificano le bolle via galleryTick) ---------

  Future<void> addToGallery(String messageId, String conversationId) async {
    await gallery.add(messageId, conversationId);
    galleryTick.value++;
  }

  Future<void> removeFromGallery(String messageId) async {
    await gallery.remove(messageId);
    _openedPhotoCache.remove(messageId);
    galleryTick.value++;
  }

  /// Offre alla galleria una foto già inviata (mittente) e la aggiunge subito
  /// alla propria galleria.
  Future<void> offerPhotoToGallery(String messageId, String conversationId) async {
    await messages.offerToGallery(messageId);
    await gallery.add(messageId, conversationId);
    galleryTick.value++;
  }

  /// Toglie la foto dalla galleria SENZA cancellarla (torna protetta/limitata).
  Future<void> unofferPhotoFromGallery(String messageId) async {
    await messages.unofferFromGallery(messageId);
    // Torna limitata: i byte in cache non vanno più mostrati liberamente.
    _openedPhotoCache.remove(messageId);
    galleryTick.value++;
  }

  /// Le MIE foto rese disponibili (senza limiti) in questa chat che NON sono
  /// più nella mia galleria: utile per ricordare cosa ho condiviso e resta
  /// accessibile all'altro anche dopo che l'ho tolta dalla mia galleria.
  /// Basata solo sui miei dati (nessuna lettura della galleria altrui).
  Future<List<Message>> myAvailablePhotosNotSaved(String conversationId) async {
    final mine = await messages.myPhotoMessages(conversationId);
    final offered = mine.where((m) => m.galleryOffered).toList();
    if (offered.isEmpty) return [];
    final saved = await gallery.savedIds(conversationId);
    return offered.where((m) => !saved.contains(m.id)).toList();
  }

  /// Modifica il testo di un proprio messaggio (ri-cifra con nuova K per
  /// destinatario e per sé) e aggiorna la cache in RAM.
  Future<void> editTextMessage({
    required Message message,
    required Profile recipient,
    required String newText,
  }) async {
    await messages.editText(
      message: message,
      recipient: recipient,
      senderPublicKey: identity.publicKey,
      newText: newText,
    );
    cacheText(message.id, newText);
  }

  /// Elimina per tutti un proprio messaggio (soft-delete + blob) e pulisce le
  /// cache locali.
  Future<void> deleteMessageForEveryone(Message m) async {
    await messages.deleteMessage(m);
    _dropText(m.id);
    photoEcho.remove(m.id);
    _openedPhotoCache.remove(m.id);
  }

  /// Toglie un testo dalla RAM e lo cancella SUBITO dal disco.
  ///
  /// Volutamente non passa dal debounce: quello si riarma a ogni scrittura, e
  /// una revoca rinviata (o perduta con la chiusura dell'app) lascerebbe il
  /// contenuto nell'archivio, da cui tornerebbe leggibile al riavvio. Se la
  /// cancellazione fallisce l'id resta in coda per un nuovo tentativo.
  bool _dropText(String messageId) {
    final had = _decryptedText.remove(messageId) != null;
    _dirtyTexts.remove(messageId);
    _removedTexts.add(messageId);
    unawaited(_removeTextsNow());
    return had;
  }

  Future<void> _removeTextsNow() async {
    final currentUid = client.auth.currentUser?.id;
    if (currentUid == null || _textCacheUid != currentUid) return;
    if (_removedTexts.isEmpty) return;
    final toRemove = _removedTexts.toList();
    _removedTexts.clear();
    final ok = await _textStore.removeIds(currentUid, toRemove);
    if (!ok) _removedTexts.addAll(toRemove); // riprovare al prossimo giro
  }

  /// Invalida il testo in cache (es. quando arriva una modifica dal mittente).
  void invalidateText(String messageId) => _dropText(messageId);

  /// Fa valere la REVOCA sulla cache: butta via i testi (e le foto) dei
  /// messaggi che non sono più apribili. Senza questo, un contenuto revocato
  /// resterebbe leggibile dalla cache sul dispositivo — la revoca non
  /// significherebbe più nulla.
  Future<void> purgeInaccessible(String conversationId) async {
    try {
      final gone = await access.inactiveMessageIds(conversationId);
      if (gone.isEmpty) return;
      var changed = false;
      for (final id in gone) {
        _openedPhotoCache.remove(id);
        photoEcho.remove(id);
        // Solo ciò che è davvero in cache: accodare ogni id inattivo a ogni
        // apertura di chat significava rifare N hash e N DELETE ogni volta.
        if (_decryptedText.containsKey(id)) {
          if (_dropText(id)) changed = true;
        }
      }
      if (changed) {
        // Le bolle testo mostrano di nuovo lo stato "non disponibile".
        accessTick.value++;
      }
    } catch (_) {}
  }

  /// Revoca un singolo messaggio e, se e' una foto, ne cancella il blob dallo
  /// Storage (il ciphertext non ancora aperto diventa irrecuperabile).
  Future<void> revokeMessage(Message m) async {
    await access.revokeMessage(m.id);
    _openedPhotoCache.remove(m.id);
    // Anche la mia copia in chiaro esce dall'archivio (RAM e disco): un
    // contenuto revocato non deve restare leggibile da nessuna parte.
    _dropText(m.id);
    photoEcho.remove(m.id);
    if (m.type == MessageType.photo && m.storagePath != null) {
      try {
        await storage.remove(m.storagePath!);
      } catch (_) {
        // best-effort: la revoca logica e' comunque avvenuta
      }
    }
  }

  /// Revoca tutti i miei contenuti nella chat e cancella i blob delle mie foto.
  Future<void> revokeConversation(String conversationId) async {
    await access.revokeConversation(conversationId);
    try {
      final paths = await messages.myPhotoStoragePaths(conversationId);
      await storage.removeMany(paths);
    } catch (_) {
      // best-effort
    }
  }

  // --- Blocco app con PIN --------------------------------------------------

  bool _lockSecureHeld = false;

  bool get lockEnabled => LocalPrefs.appLockEnabled;

  Future<void> setPin(String pin) async {
    final salt = crypto.randomSalt();
    final hash = crypto.hashPin(pin, salt);
    await LocalPrefs.setPin(base64Encode(salt), hash);
    await LocalPrefs.setAppLockEnabled(true);
    applyLockFlagSecure();
  }

  bool verifyPin(String pin) {
    final saltB64 = LocalPrefs.pinSalt;
    final hash = LocalPrefs.pinHash;
    if (saltB64 == null || hash == null) return false;
    return crypto.hashPin(pin, base64Decode(saltB64)) == hash;
  }

  Future<void> disableLock() async {
    await LocalPrefs.clearPin();
    await LocalPrefs.setLockUseBiometric(false);
    applyLockFlagSecure();
  }

  // --- Sblocco biometrico (solo APK; sul web local_auth non è disponibile) --

  /// Biometria attivabile: solo su piattaforma nativa (non web).
  bool get biometricSupportedPlatform => !kIsWeb;

  /// Biometria attiva come sblocco alternativo (impostata dall'utente + APK).
  bool get biometricUnlockEnabled => !kIsWeb && LocalPrefs.lockUseBiometric;

  /// Il dispositivo ha una biometria configurata (impronta/volto).
  Future<bool> deviceHasBiometrics() async {
    if (kIsWeb) return false;
    try {
      final a = LocalAuthentication();
      return await a.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Mostra il prompt biometrico di sistema. Ritorna true se autenticato.
  Future<bool> authenticateBiometric() async {
    if (kIsWeb) return false;
    try {
      return await LocalAuthentication().authenticate(
        localizedReason: 'Sblocca Bruma',
        options: const AuthenticationOptions(
            stickyAuth: true, biometricOnly: true),
      );
    } catch (_) {
      return false;
    }
  }

  // --- Notifiche / Web Push ------------------------------------------------

  /// Chiede il permesso notifiche e registra il canale push:
  ///  • Web  → Web Push (subscription salvata in `push_subscriptions`).
  ///  • APK  → token FCM salvato in `fcm_tokens`.
  /// Ritorna un messaggio pronto per la UI.
  Future<String> enablePush() async {
    await NotificationService.requestPermission();
    if (!kIsWeb) {
      // Android: registra il token FCM (per le notifiche ad app chiusa).
      final token = await requestAndGetFcmToken();
      if (token == null) {
        return 'Notifiche non attivate: permesso negato o Firebase non '
            'configurato in questa build.';
      }
      await _upsertFcmToken(token);
      _fcmRefreshSub ??= fcmTokenRefresh().listen(_upsertFcmToken);
      return 'Notifiche push attivate su questo dispositivo.';
    }
    try {
      final sub = await subscribeWebPush(AppConfig.vapidPublicKey);
      await client.from('push_subscriptions').upsert({
        'user_id': uid,
        'endpoint': sub['endpoint'],
        'p256dh': sub['p256dh'],
        'auth': sub['auth'],
      }, onConflict: 'endpoint');
      return 'Notifiche attivate su questo dispositivo.';
    } catch (e) {
      return 'Push non attivato — $e';
    }
  }

  StreamSubscription<String>? _fcmRefreshSub;

  Future<void> _upsertFcmToken(String token) async {
    try {
      await client.from('fcm_tokens').upsert(
        {'user_id': uid, 'token': token},
        onConflict: 'token',
      );
    } catch (_) {
      // rete/tabella assente: best-effort
    }
  }

  /// Dopo il login (APK): registra silenziosamente il token FCM già esistente
  /// e resta in ascolto dei refresh. Non chiede permessi (quelli si concedono
  /// con "Attiva notifiche"). No-op su web.
  Future<void> startFcmSync() async {
    if (kIsWeb) return;
    final token = await currentFcmToken();
    if (token != null) await _upsertFcmToken(token);
    _fcmRefreshSub ??= fcmTokenRefresh().listen(_upsertFcmToken);
  }


  // --- Preferenze notifiche (suono/vibrazione + muto per chat) -------------
  // Salvate in locale (per le notifiche in-app) e sincronizzate su Supabase
  // (best-effort) così anche la Edge Function del push le rispetta.

  Future<void> setNotifSound(bool v) async {
    await LocalPrefs.setNotifSound(v);
    await _syncNotifPrefs();
  }

  Future<void> setNotifVibrate(bool v) async {
    await LocalPrefs.setNotifVibrate(v);
    await _syncNotifPrefs();
  }

  /// Testo notifica personalizzato (mascheramento). null/empty → default 🌙.
  Future<void> setNotifText(String? title, String? body) async {
    await LocalPrefs.setNotifText(title, body);
    await _syncNotifPrefs();
  }

  Future<void> _syncNotifPrefs() async {
    try {
      await client.from('notif_prefs').upsert({
        'user_id': uid,
        'sound': LocalPrefs.notifSound,
        'vibrate': LocalPrefs.notifVibrate,
        'notif_title': LocalPrefs.notifTitle,
        'notif_body': LocalPrefs.notifBody,
      }, onConflict: 'user_id');
    } catch (_) {
      // la tabella potrebbe non esistere ancora: le notifiche in-app funzionano
      // lo stesso, il push la rispetterà quando la migration è applicata.
    }
  }

  /// Preferiti (solo locali): aggiunge/toglie e notifica la chat via tick.
  Future<void> setFavorite(
      String conversationId, String messageId, bool fav) async {
    await LocalPrefs.setFavorite(conversationId, messageId, fav);
    favoritesTick.value++;
  }

  Future<void> setChatMuted(String conversationId, bool muted) async {
    await LocalPrefs.setChatMuted(conversationId, muted);
    try {
      if (muted) {
        await client.from('chat_mutes').upsert({
          'user_id': uid,
          'conversation_id': conversationId,
        }, onConflict: 'user_id,conversation_id');
      } else {
        await client
            .from('chat_mutes')
            .delete()
            .eq('user_id', uid)
            .eq('conversation_id', conversationId);
      }
    } catch (_) {}
  }

  /// Tiene FLAG_SECURE attivo (anteprima recents nera su Android) finché il
  /// blocco è attivo. Il viewer foto si somma sopra questo "base".
  void applyLockFlagSecure() {
    final want = LocalPrefs.appLockEnabled;
    if (want && !_lockSecureHeld) {
      SecureScreenGuard.acquire();
      _lockSecureHeld = true;
    } else if (!want && _lockSecureHeld) {
      SecureScreenGuard.release();
      _lockSecureHeld = false;
    }
  }

  Future<void> signOut() async {
    // Rimuovi il token FCM di QUESTO dispositivo PRIMA del signOut: la RLS
    // richiede la sessione viva e dopo il signOut `uid` non è più disponibile.
    // Senza, il dispositivo continuerebbe a ricevere push per l'account uscito
    // — leak grave col modello decoy/plausible-deniability.
    await _removeFcmTokenForThisDevice();
    await _fcmRefreshSub?.cancel();
    _fcmRefreshSub = null;
    // Cancella la cache testi PRIMA del signOut (dopo `uid` non c'è più):
    // uscendo non deve restare la cronologia sul dispositivo.
    final leavingUid = client.auth.currentUser?.id;
    _textFlush?.cancel();
    // Prima di tutto: sgancia la cache dall'account. Un flush già in volo si
    // accorgerà che l'utente non è più quello e non riscriverà nulla.
    _textCacheUid = null;
    _dirtyTexts.clear();
    _removedTexts.clear();
    if (leavingUid != null) await _textStore.clear(leavingUid);
    try {
      await auth.signOut();
    } finally {
      // Anche se il signOut remoto fallisce (tipico offline: solleva DOPO aver
      // già scartato la sessione) le cache locali vanno svuotate, altrimenti i
      // testi in chiaro del vecchio account resterebbero in memoria.
      _setIdentity(null);
      myProfile = null;
      textEcho.clear();
      photoEcho.clear();
      _decryptedText.clear();
      _openedPhotoCache.clear();
      _readByConversation.clear();
      _readWatermark.clear();
    }
  }

  Future<void> _removeFcmTokenForThisDevice() async {
    if (kIsWeb) return;
    try {
      final token = await currentFcmToken();
      if (token == null) return;
      await client
          .from('fcm_tokens')
          .delete()
          .eq('user_id', uid)
          .eq('token', token);
    } catch (_) {
      // best-effort
    }
  }
}
