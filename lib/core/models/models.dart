/// Modelli dati (mappano le tabelle Postgres / risultati RPC).
library;

enum MessageType { text, photo }

MessageType messageTypeFromString(String s) =>
    s == 'photo' ? MessageType.photo : MessageType.text;

String messageTypeToString(MessageType t) =>
    t == MessageType.photo ? 'photo' : 'text';

enum OpenOutcome { granted, deniedRevoked, deniedExpired, deniedLimit, unknown }

OpenOutcome openOutcomeFromString(String s) {
  switch (s) {
    case 'granted':
      return OpenOutcome.granted;
    case 'denied_revoked':
      return OpenOutcome.deniedRevoked;
    case 'denied_expired':
      return OpenOutcome.deniedExpired;
    case 'denied_limit':
      return OpenOutcome.deniedLimit;
    default:
      return OpenOutcome.unknown;
  }
}

class Profile {
  Profile({
    required this.id,
    required this.displayName,
    required this.publicKey,
  });

  final String id;
  final String displayName;
  final String publicKey; // base64

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        displayName: (m['display_name'] ?? '') as String,
        publicKey: (m['public_key'] ?? '') as String,
      );
}

class Conversation {
  Conversation({
    required this.id,
    required this.userA,
    required this.userB,
    required this.protectionEnabled,
    required this.maxOpens,
    required this.maxDurationSeconds,
    required this.appliesTo,
  });

  final String id;
  final String userA;
  final String userB;
  final bool protectionEnabled;
  final int maxOpens;
  final int maxDurationSeconds;
  final String appliesTo;

  String otherUserId(String me) => userA == me ? userB : userA;

  factory Conversation.fromMap(Map<String, dynamic> m) => Conversation(
        id: m['id'] as String,
        userA: m['user_a'] as String,
        userB: m['user_b'] as String,
        protectionEnabled: (m['protection_enabled'] ?? true) as bool,
        maxOpens: (m['max_opens'] ?? 3) as int,
        maxDurationSeconds: (m['max_duration_seconds'] ?? 30) as int,
        appliesTo: (m['applies_to'] ?? 'all') as String,
      );
}

/// Vista di una conversazione arricchita con il profilo dell'altro utente
/// e un'anteprima dell'ultimo messaggio (per la lista chat).
class ConversationView {
  ConversationView({
    required this.conversation,
    required this.other,
    this.lastMessage,
    this.unread = 0,
  });

  final Conversation conversation;
  final Profile other;
  final Message? lastMessage;

  /// Numero di messaggi dell'altro non ancora letti (calcolato localmente
  /// rispetto all'ultimo messaggio letto salvato in LocalPrefs).
  final int unread;
}

class Message {
  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.ciphertext,
    required this.storagePath,
    required this.createdAt,
    this.editedAt,
    this.deletedAt,
    this.replyTo,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final MessageType type;
  final String? ciphertext; // base64 (nonce||ct) per il testo
  final String? storagePath; // per la foto su Storage
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final String? replyTo; // id del messaggio citato

  bool get isEdited => editedAt != null;
  bool get isDeleted => deletedAt != null;

  factory Message.fromMap(Map<String, dynamic> m) => Message(
        id: m['id'] as String,
        conversationId: m['conversation_id'] as String,
        senderId: m['sender_id'] as String,
        type: messageTypeFromString(m['type'] as String),
        ciphertext: m['ciphertext'] as String?,
        storagePath: m['storage_path'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
        editedAt: m['edited_at'] == null
            ? null
            : DateTime.parse(m['edited_at'] as String),
        deletedAt: m['deleted_at'] == null
            ? null
            : DateTime.parse(m['deleted_at'] as String),
        replyTo: m['reply_to'] as String?,
      );
}

/// Reaction (emoji) di un utente su un messaggio.
class Reaction {
  Reaction({
    required this.messageId,
    required this.userId,
    required this.emoji,
  });
  final String messageId;
  final String userId;
  final String emoji;

  factory Reaction.fromMap(Map<String, dynamic> m) => Reaction(
        messageId: m['message_id'] as String,
        userId: m['user_id'] as String,
        emoji: m['emoji'] as String,
      );
}

enum RequestStatus { pending, renewed, resent, denied, unknown }

RequestStatus requestStatusFromString(String s) {
  switch (s) {
    case 'pending':
      return RequestStatus.pending;
    case 'renewed':
      return RequestStatus.renewed;
    case 'resent':
      return RequestStatus.resent;
    case 'denied':
      return RequestStatus.denied;
    default:
      return RequestStatus.unknown;
  }
}

/// Richiesta del destinatario di riavere un contenuto (rinnovo/reinvio).
class ContentRequest {
  ContentRequest({
    required this.id,
    required this.messageId,
    required this.requesterId,
    required this.ownerId,
    required this.status,
    required this.createdAt,
  });
  final String id;
  final String messageId;
  final String requesterId;
  final String ownerId;
  final RequestStatus status;
  final DateTime createdAt;

  factory ContentRequest.fromMap(Map<String, dynamic> m) => ContentRequest(
        id: m['id'] as String,
        messageId: m['message_id'] as String,
        requesterId: m['requester_id'] as String,
        ownerId: m['owner_id'] as String,
        status: requestStatusFromString(m['status'] as String),
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

/// Riga `message_access` come vista dal client — SENZA `wrapped_key`
/// (quella colonna non e' leggibile: esce solo dalla RPC request_key).
class MessageAccess {
  MessageAccess({
    required this.id,
    required this.messageId,
    required this.recipientId,
    required this.protectionEnabled,
    required this.maxOpens,
    required this.maxDurationSeconds,
    required this.expiresAt,
    required this.openCount,
    required this.active,
  });

  final String id;
  final String messageId;
  final String recipientId;
  final bool protectionEnabled;
  final int maxOpens;
  final int maxDurationSeconds;
  final DateTime? expiresAt;
  final int openCount;
  final bool active;

  // 0 (o meno) significa "illimitato", separatamente per aperture e durata.
  bool get unlimitedOpens => maxOpens <= 0;
  bool get unlimitedDuration => maxDurationSeconds <= 0;

  /// Aperture rimaste; -1 se illimitate.
  int get remainingOpens =>
      unlimitedOpens ? -1 : (maxOpens - openCount).clamp(0, maxOpens);

  bool get isExpired =>
      expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!.toUtc());

  /// Vero se il contenuto e' ancora apribile dal destinatario.
  bool get isOpenable {
    if (!active) return false; // la revoca vale sempre
    if (!protectionEnabled) return true;
    if (isExpired) return false; // isExpired è false se durata illimitata
    if (!unlimitedOpens && remainingOpens <= 0) return false;
    return true;
  }

  factory MessageAccess.fromMap(Map<String, dynamic> m) => MessageAccess(
        id: m['id'] as String,
        messageId: m['message_id'] as String,
        recipientId: m['recipient_id'] as String,
        protectionEnabled: (m['protection_enabled'] ?? true) as bool,
        maxOpens: (m['max_opens'] ?? 0) as int,
        maxDurationSeconds: (m['max_duration_seconds'] ?? 0) as int,
        expiresAt: m['expires_at'] == null
            ? null
            : DateTime.parse(m['expires_at'] as String),
        openCount: (m['open_count'] ?? 0) as int,
        active: (m['active'] ?? true) as bool,
      );
}

class OpenEvent {
  OpenEvent({
    required this.id,
    required this.messageId,
    required this.recipientId,
    required this.openedAt,
    required this.outcome,
  });

  final String id;
  final String messageId;
  final String recipientId;
  final DateTime openedAt;
  final OpenOutcome outcome;

  factory OpenEvent.fromMap(Map<String, dynamic> m) => OpenEvent(
        id: m['id'] as String,
        messageId: m['message_id'] as String,
        recipientId: m['recipient_id'] as String,
        openedAt: DateTime.parse(m['opened_at'] as String),
        outcome: openOutcomeFromString(m['outcome'] as String),
      );
}

/// Risultato di `redeem_invite`.
class RedeemResult {
  RedeemResult({required this.conversationId, required this.contact});
  final String conversationId;
  final Profile contact;

  factory RedeemResult.fromJson(Map<String, dynamic> j) => RedeemResult(
        conversationId: j['conversation_id'] as String,
        contact: Profile.fromMap(
            (j['contact'] as Map).cast<String, dynamic>()),
      );
}
