import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:sodium_libs/sodium_libs.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'crypto/crypto_service.dart';
import 'local_prefs.dart';
import 'models/models.dart';
import 'secure_screen.dart';
import 'secure_store/key_store.dart';
import 'supabase/access_repository.dart';
import 'supabase/auth_repository.dart';
import 'supabase/contacts_repository.dart';
import 'supabase/conversations_repository.dart';
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

  KeyPair? _identity;
  Profile? myProfile;

  /// Eco in memoria (solo sessione, MAI su disco) dei propri contenuti inviati,
  /// cosi' il mittente rivede cio' che ha mandato senza consumare il contatore
  /// del destinatario e senza scrivere il testo in chiaro sul dispositivo.
  final Map<String, String> textEcho = {};
  final Map<String, Uint8List> photoEcho = {};

  /// Cache in RAM dei testi ricevuti NON protetti (decifrati una sola volta).
  final Map<String, String> _decryptedText = {};

  /// Incrementa a ogni evento di apertura ricevuto via Realtime: le ricevute
  /// di lettura (doppia spunta) vi si agganciano per aggiornarsi dal vivo.
  final ValueNotifier<int> openEventsTick = ValueNotifier<int>(0);

  /// Incrementa quando una mia richiesta di contenuto viene gestita
  /// (rinnovo/reinvio): le bolle foto rileggono lo stato di accesso dal vivo.
  final ValueNotifier<int> accessTick = ValueNotifier<int>(0);

  /// Modalità "panic": quando attiva, l'app mostra un decoy (calcolatrice) al
  /// posto del login finché non si sblocca. Persistita in LocalPrefs.
  final ValueNotifier<bool> panicMode = ValueNotifier<bool>(false);

  Future<void> setPanic(bool value) async {
    panicMode.value = value;
    await LocalPrefs.setPanic(value);
  }

  /// Attiva il panic: nasconde tutto (decoy) e disconnette (richiede re-login).
  Future<void> panic() async {
    await setPanic(true);
    await signOut();
  }

  String? cachedText(String messageId) => _decryptedText[messageId];
  void cacheText(String messageId, String value) =>
      _decryptedText[messageId] = value;

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
    myProfile = await profiles.getMyProfile();
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

  /// Esporta l'identità corrente come stringa cifrata con [password].
  String exportIdentity(String password) => crypto.exportIdentity(identity, password);

  /// Importa un'identità (da backup + password): la salva sul dispositivo,
  /// allinea la chiave pubblica sul profilo e la rende quella corrente.
  /// Da qui in poi i contenuti cifrati per QUELLA identità sono apribili.
  Future<void> importIdentity(String data, String password) async {
    final kp = crypto.importIdentity(data, password); // lancia se pwd/dati errati
    await keyStore.save(uid, kp);
    await profiles.updatePublicKey(crypto.encodePublicKey(kp.publicKey));
    _setIdentity(kp);
    myProfile = await profiles.getMyProfile();
    // Svuota le cache in RAM (cifrate con la vecchia chiave).
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
    _decryptedText.remove(m.id);
    photoEcho.remove(m.id);
  }

  /// Invalida il testo in cache (es. quando arriva una modifica dal mittente).
  void invalidateText(String messageId) => _decryptedText.remove(messageId);

  /// Revoca un singolo messaggio e, se e' una foto, ne cancella il blob dallo
  /// Storage (il ciphertext non ancora aperto diventa irrecuperabile).
  Future<void> revokeMessage(Message m) async {
    await access.revokeMessage(m.id);
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
    applyLockFlagSecure();
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
    await auth.signOut();
    _setIdentity(null);
    myProfile = null;
    textEcho.clear();
    photoEcho.clear();
    _decryptedText.clear();
  }
}
