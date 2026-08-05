import 'dart:async';
import 'dart:convert';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sodium_libs/sodium_libs.dart' show SodiumException;

import '../../core/app_services.dart';
import '../../core/local_prefs.dart';
import '../../core/models/models.dart';
import '../../core/secure_screen.dart';
import '../../core/secure_store/favorite_notes.dart';
import '../../core/supabase/key_request_exception.dart';
import '../../shared/emoji_config.dart';
import '../../shared/favorite_icon.dart';
import '../../shared/linkified_text.dart';
import '../../shared/watermark.dart';
import '../../shared/widgets.dart';
import '../favorites/favorites_screen.dart';
import '../viewer/viewer_screen.dart';

const _readBlue = Color(0xFF34B7F1);
const _reactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// Bolla di un messaggio (testo o foto) con reactions ed azioni.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.other,
    required this.reactions,
    required this.onReply,
    required this.resolveReply,
    required this.onQuoteTap,
    this.reopenActionable = false,
    this.reopenStatus,
    this.onReopenAccept,
    this.onReopenDeny,
  });

  final Message message;
  final bool isMine;
  final Profile other;
  final List<Reaction> reactions;
  final void Function(Message) onReply;
  final Message? Function(String id) resolveReply;
  final void Function(String id) onQuoteTap;

  /// Solo per i messaggi `reopen_request`: vero se sono il proprietario e la
  /// richiesta è ancora pendente → mostra Rinnova/Rifiuta.
  final bool reopenActionable;

  /// Solo per il richiedente: esito della propria richiesta (in attesa /
  /// approvata / rifiutata) da mostrare sotto la bolla.
  final RequestStatus? reopenStatus;
  final VoidCallback? onReopenAccept;
  final VoidCallback? onReopenDeny;

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) return _deletedBubble(context, isMine);

    // Messaggi di sistema (richiesta/riapertura): niente reazioni, resa dedicata.
    if (message.type == MessageType.reopenRequest) {
      return _reopenRequestBubble(
        context,
        message: message,
        isMine: isMine,
        other: other,
        resolve: resolveReply,
        onQuoteTap: onQuoteTap,
        actionable: reopenActionable,
        status: reopenStatus,
        onAccept: onReopenAccept,
        onDeny: onReopenDeny,
      );
    }
    if (message.type == MessageType.reopened) {
      return _reopenedBubble(
        context,
        message: message,
        isMine: isMine,
        other: other,
        resolve: resolveReply,
        onQuoteTap: onQuoteTap,
      );
    }

    final Widget inner = message.type == MessageType.text
        ? _TextBubble(
            message: message,
            isMine: isMine,
            other: other,
            onReply: onReply,
            resolveReply: resolveReply,
            onQuoteTap: onQuoteTap)
        : _PhotoBubble(
            message: message,
            isMine: isMine,
            other: other,
            onReply: onReply,
            resolveReply: resolveReply,
            onQuoteTap: onQuoteTap);

    if (reactions.isEmpty) return inner;
    return Column(children: [inner, _reactionsRow(context, reactions, isMine)]);
  }
}

/// Bolla "richiesta di riapertura": cita la foto e, per il proprietario con
/// richiesta pendente, mostra Accetta/Rifiuta.
Widget _reopenRequestBubble(
  BuildContext context, {
  required Message message,
  required bool isMine,
  required Profile other,
  required Message? Function(String) resolve,
  required void Function(String) onQuoteTap,
  required bool actionable,
  RequestStatus? status,
  VoidCallback? onAccept,
  VoidCallback? onDeny,
}) {
  final cs = Theme.of(context).colorScheme;
  return _bubbleShell(
    context,
    mine: isMine,
    child: Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (message.replyTo != null)
          _quoteHeader(
              context, message.replyTo!, isMine, other, resolve, onQuoteTap),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_open_outlined, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                isMine
                    ? 'Hai chiesto di riaprire questa foto'
                    : 'Ti ha chiesto di riaprire questa foto',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        // Proprietario + richiesta pendente → azioni (Rinnova/Rifiuta).
        // Altrimenti mostra l'esito (a entrambi i lati).
        if (actionable) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onDeny,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Rifiuta'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.autorenew, size: 18),
                  label: const Text('Rinnova'),
                ),
              ),
            ],
          ),
        ] else if (status != null) ...[
          const SizedBox(height: 4),
          _reopenStatusChip(context, status, isMine),
        ],
      ],
    ),
  );
}

/// Esito di una richiesta di riapertura. `mine` = lo vede il richiedente
/// (parole diverse dal proprietario).
Widget _reopenStatusChip(BuildContext context, RequestStatus status, bool mine) {
  final cs = Theme.of(context).colorScheme;
  final IconData icon;
  final String label;
  final Color color;
  switch (status) {
    case RequestStatus.renewed:
    case RequestStatus.resent:
      icon = Icons.check_circle;
      label = mine ? 'Approvata' : 'Rinnovata';
      color = Colors.green;
    case RequestStatus.denied:
      icon = Icons.cancel;
      label = 'Rifiutata';
      color = cs.error;
    case RequestStatus.pending:
    case RequestStatus.unknown:
      icon = Icons.schedule;
      label = 'In attesa';
      color = cs.onSurfaceVariant;
  }
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    ],
  );
}

/// Segnaposto "foto riaperta": tocca per saltare alla foto (ora riapribile).
Widget _reopenedBubble(
  BuildContext context, {
  required Message message,
  required bool isMine,
  required Profile other,
  required Message? Function(String) resolve,
  required void Function(String) onQuoteTap,
}) {
  final cs = Theme.of(context).colorScheme;
  return GestureDetector(
    onTap: message.replyTo == null ? null : () => onQuoteTap(message.replyTo!),
    child: _bubbleShell(
      context,
      mine: isMine,
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (message.replyTo != null)
            _quoteHeader(
                context, message.replyTo!, isMine, other, resolve, onQuoteTap),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_open, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              const Flexible(
                child: Text('Foto riaperta — tocca per vederla',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Blocco citazione IN TESTA alla bolla (stile WhatsApp): barra colorata a
/// sinistra, nome del mittente citato e anteprima. Tap → salta all'originale.
Widget _quoteHeader(
  BuildContext context,
  String replyId,
  bool mine,
  Profile other,
  Message? Function(String) resolve,
  void Function(String) onTap,
) {
  return _QuoteHeader(
    replyId: replyId,
    mine: mine,
    other: other,
    resolve: resolve,
    onTap: onTap,
  );
}

/// Anteprima del messaggio citato. Se il messaggio non è nella pagina caricata
/// lo recupera dal server (così non resta "Messaggio" generico); per il testo
/// (mai protetto) lo decifra al volo per mostrarne l'anteprima; per le foto
/// mostra una miniatura solo se i byte sono già in cache (niente apertura).
class _QuoteHeader extends StatefulWidget {
  const _QuoteHeader({
    required this.replyId,
    required this.mine,
    required this.other,
    required this.resolve,
    required this.onTap,
  });

  final String replyId;
  final bool mine;
  final Profile other;
  final Message? Function(String) resolve;
  final void Function(String) onTap;

  @override
  State<_QuoteHeader> createState() => _QuoteHeaderState();
}

class _QuoteHeaderState extends State<_QuoteHeader> {
  Message? _ref;
  String? _text; // anteprima testo decifrata

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _QuoteHeader old) {
    super.didUpdateWidget(old);
    if (old.replyId != widget.replyId) {
      _ref = null;
      _text = null;
      _init();
    }
  }

  Future<void> _init() async {
    var ref = widget.resolve(widget.replyId);
    ref ??= await AppServices.instance.messages.getMessage(widget.replyId);
    if (!mounted) return;
    setState(() => _ref = ref);
    if (ref == null || ref.isDeleted || ref.type != MessageType.text) return;
    final cached = AppServices.instance.cachedText(ref.id);
    if (cached != null) {
      setState(() => _text = cached);
      return;
    }
    try {
      // Il testo non è mai protetto: decifrarlo per l'anteprima non consuma
      // aperture.
      final bytes = await AppServices.instance.openContentBytes(ref);
      final t = utf8.decode(bytes);
      AppServices.instance.cacheText(ref.id, t);
      if (mounted) setState(() => _text = t);
    } catch (_) {
      // resta l'etichetta generica
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = AppServices.instance.uid;
    final ref = _ref;
    final who =
        ref == null ? '' : (ref.senderId == me ? 'Tu' : widget.other.displayName);
    final onBubble = widget.mine ? cs.onPrimaryContainer : cs.onSurface;

    String label;
    Uint8List? thumb;
    if (ref == null) {
      label = 'Messaggio';
    } else if (ref.isDeleted) {
      label = 'Messaggio eliminato';
    } else if (ref.type == MessageType.photo) {
      label = '📷 Foto';
      thumb = AppServices.instance.cachedPhotoBytes(ref.id) ??
          AppServices.instance.photoEcho[ref.id];
    } else {
      label = _text ?? AppServices.instance.cachedText(ref.id) ?? 'Messaggio';
    }

    return GestureDetector(
      onTap: () => widget.onTap(widget.replyId),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: onBubble.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: cs.primary, width: 4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumb != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: WatermarkOverlay(
                  dense: true,
                  child: Image.memory(thumb,
                      width: 34, height: 34, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(who,
                      style: TextStyle(
                          color: cs.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: onBubble)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _deletedBubble(BuildContext context, bool mine) {
  final cs = Theme.of(context).colorScheme;
  return _bubbleShell(
    context,
    mine: mine,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.block, size: 15, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text('Messaggio eliminato',
            style: TextStyle(
                fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)),
      ],
    ),
  );
}

Widget _bubbleShell(
  BuildContext context, {
  required bool mine,
  required Widget child,
}) {
  final cs = Theme.of(context).colorScheme;
  return Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
      decoration: BoxDecoration(
        color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    ),
  );
}

Widget _spinnerBubble(BuildContext context, {required bool mine}) {
  return _bubbleShell(
    context,
    mine: mine,
    child: const SizedBox(
      height: 18,
      width: 40,
      child: Center(
        child: SizedBox(
          height: 14,
          width: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
  );
}

Widget _reactionsRow(
    BuildContext context, List<Reaction> reactions, bool mine) {
  // Raggruppa per emoji con conteggio.
  final counts = <String, int>{};
  for (final r in reactions) {
    counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
  }
  final cs = Theme.of(context).colorScheme;
  return Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: EdgeInsets.only(
          left: mine ? 0 : 16, right: mine ? 16 : 0, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        counts.entries
            .map((e) => e.value > 1 ? '${e.key}${e.value}' : e.key)
            .join(' '),
        style: const TextStyle(fontSize: 13),
      ),
    ),
  );
}

/// Messaggio d'errore leggibile per i fallimenti di decifratura: quasi sempre
/// significa che il contenuto è cifrato per un'ALTRA identità (es. hai aperto
/// l'app su un nuovo dispositivo e rigenerato le chiavi).
String _friendlyDecryptError(Object e) {
  // Si controlla il TIPO, non il testo dell'eccezione. Cercare "sodium",
  // "decrypt" o "mac" dentro un toString() qualunque faceva passare per
  // "problema di identità" errori che non lo erano affatto (una qualsiasi
  // eccezione con quelle lettere nel messaggio), mandando l'utente a caccia
  // del problema sbagliato.
  if (e is SodiumException) {
    return 'Contenuto cifrato per un\'altra identità: '
        'non apribile su questo dispositivo.';
  }
  // In debug stampa l'errore vero: altrimenti la causa reale si perde.
  assert(() {
    debugPrint('Bruma: decifratura fallita (${e.runtimeType}): $e');
    return true;
  }());
  return 'Errore: $e';
}

/// Vero se il testo è composto solo da emoji/simboli (niente lettere/cifre) ed
/// è corto: in tal caso lo mostriamo in grande, come WhatsApp.
bool _isEmojiOnly(String s) {
  final t = s.trim();
  if (t.isEmpty) return false;
  if (RegExp(r'[A-Za-z0-9]').hasMatch(t)) return false;
  final count = t.runes
      .where((r) => r != 0x200D && r != 0xFE0F && r != 0x20)
      .length;
  return count > 0 && count <= 8;
}

/// Selettore con TUTTE le emoji (bottom sheet). Ritorna l'emoji scelta.
Future<String?> _pickEmoji(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SizedBox(
      height: 320,
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) => Navigator.pop(ctx, emoji.emoji),
        config: brumaEmojiConfig(ctx),
      ),
    ),
  );
}

/// Menu azioni (long-press): reactions rapide + copia/modifica/elimina/revoca.
Future<void> showMessageActions(
  BuildContext context, {
  required Message message,
  required bool isMine,
  required Profile other,
  required void Function(Message) onReply,
}) async {
  final isText = message.type == MessageType.text;
  final cached = AppServices.instance.cachedText(message.id);
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      void snack(String m) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(m)));
      }

      final isFav = LocalPrefs.isFavorite(message.id);

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reaction picker rapido + "+" per tutte le emoji
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in _reactionEmojis)
                    InkWell(
                      onTap: () async {
                        Navigator.pop(ctx);
                        await AppServices.instance.messages
                            .setReaction(message.id, e);
                        AppServices.instance.reactionsTick.value++;
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                  InkWell(
                    onTap: () async {
                      Navigator.pop(ctx);
                      final picked = await _pickEmoji(context);
                      if (picked != null) {
                        await AppServices.instance.messages
                            .setReaction(message.id, picked);
                        AppServices.instance.reactionsTick.value++;
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.add_reaction_outlined, size: 26),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Rispondi'),
              onTap: () {
                Navigator.pop(ctx);
                onReply(message);
              },
            ),
            ListTile(
              leading: Icon(isFav ? favoriteIconOn : favoriteIconOff,
                  color: isFav ? Colors.amber : null),
              title: Text(
                  isFav ? 'Rimuovi dai preferiti' : 'Salva nei preferiti'),
              onTap: () async {
                Navigator.pop(ctx);
                if (isFav) {
                  await AppServices.instance
                      .setFavorite(message.conversationId, message.id, false);
                  await FavoriteNotes.set(message.id, null);
                  snack('Rimosso dai preferiti.');
                } else {
                  await AppServices.instance
                      .setFavorite(message.conversationId, message.id, true);
                  snack('Salvato nei preferiti.');
                  // Proponi una nota promemoria (facoltativa), utile per i
                  // contenuti protetti che non si potranno rivedere.
                  if (context.mounted) {
                    await editFavoriteNote(context, message.id);
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.mood_bad),
              title: const Text('Togli la mia reaction'),
              onTap: () {
                Navigator.pop(ctx);
                AppServices.instance.messages.removeReaction(message.id);
              },
            ),
            // Foto offerta alla galleria → salva/rimuovi dalla propria galleria.
            if (message.galleryOffered && !isText)
              FutureBuilder<bool>(
                future: AppServices.instance.gallery.isSaved(message.id),
                builder: (_, snap) {
                  final saved = snap.data ?? false;
                  return ListTile(
                    leading: Icon(saved
                        ? Icons.bookmark_remove_outlined
                        : Icons.bookmark_add_outlined),
                    title: Text(saved
                        ? 'Rimuovi dalla galleria'
                        : 'Aggiungi alla galleria'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        if (saved) {
                          await AppServices.instance
                              .removeFromGallery(message.id);
                          snack('Rimossa dalla galleria.');
                        } else {
                          await AppServices.instance.addToGallery(
                              message.id, message.conversationId);
                          snack('Aggiunta alla galleria.');
                        }
                      } catch (e) {
                        snack('Operazione non riuscita: $e');
                      }
                    },
                  );
                },
              ),
            // Foto mia NON ancora offerta → rendila disponibile in galleria.
            if (isMine && !isText && !message.galleryOffered)
              ListTile(
                leading: const Icon(Icons.collections_outlined),
                title: const Text('Rendi disponibile in galleria'),
                subtitle:
                    const Text('Senza limiti di aperture (revocabile)'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await AppServices.instance.offerPhotoToGallery(
                        message.id, message.conversationId);
                    snack('Ora è disponibile in galleria.');
                  } catch (e) {
                    snack('Operazione non riuscita: $e');
                  }
                },
              ),
            // Foto mia GIÀ in galleria → toglila senza cancellarla (torna protetta).
            if (isMine && !isText && message.galleryOffered)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Togli dalla galleria (resta protetta)'),
                subtitle: const Text(
                    'Torna una foto limitata, ma NON viene cancellata'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await AppServices.instance
                        .unofferPhotoFromGallery(message.id);
                    snack('Tolta dalla galleria: ora è protetta.');
                  } catch (e) {
                    snack('Operazione non riuscita: $e');
                  }
                },
              ),
            if (isText && cached != null)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copia'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: cached));
                  snack('Copiato.');
                },
              ),
            if (isMine && isText)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Modifica'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _editDialog(context, message, other);
                },
              ),
            if (isMine && !isText)
              ListTile(
                leading: Icon(Icons.delete_forever,
                    color: Theme.of(ctx).colorScheme.error),
                title: Text('Revoca: cancella la foto',
                    style:
                        TextStyle(color: Theme.of(ctx).colorScheme.error)),
                subtitle: const Text(
                    'Definitivo: la foto viene eliminata dal server, '
                    'irrecuperabile per tutti'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dctx) => AlertDialog(
                      title: const Text('Cancellare la foto?'),
                      content: const Text(
                          'Verrà eliminata definitivamente dal server e non '
                          'sarà più apribile da nessuno. Non è recuperabile. '
                          '(Per toglierla solo dalla galleria senza '
                          'cancellarla, usa "Togli dalla galleria".)'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dctx, false),
                            child: const Text('Annulla')),
                        FilledButton(
                            onPressed: () => Navigator.pop(dctx, true),
                            child: const Text('Cancella')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  await AppServices.instance.revokeMessage(message);
                  snack('Foto cancellata definitivamente.');
                },
              ),
            if (isMine)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(ctx).colorScheme.error),
                title: const Text('Elimina per tutti'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await AppServices.instance.deleteMessageForEveryone(message);
                  snack('Messaggio eliminato.');
                },
              ),
          ],
        ),
      );
    },
  );
}

Future<void> _editDialog(
    BuildContext context, Message message, Profile other) async {
  final controller = TextEditingController(
      text: AppServices.instance.cachedText(message.id) ?? '');
  final newText = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Modifica messaggio'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 5,
        minLines: 1,
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Salva')),
      ],
    ),
  );
  if (newText == null || newText.isEmpty) return;
  try {
    await AppServices.instance
        .editTextMessage(message: message, recipient: other, newText: newText);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Modifica non riuscita: $e')));
    }
  }
}

Widget _footer(BuildContext context, Message message, {required bool mine}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (LocalPrefs.isFavorite(message.id)) ...[
        const Icon(favoriteIconOn, size: 13, color: favoriteColor),
        const SizedBox(width: 4),
      ],
      if (message.isEdited) ...[
        Text('modificato · ',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontStyle: FontStyle.italic)),
      ],
      Text(formatTimestamp(message.createdAt),
          style: Theme.of(context).textTheme.labelSmall),
      if (mine) ...[
        const SizedBox(width: 6),
        _ReadReceipt(message: message),
      ],
    ],
  );
}

/// Doppia spunta (consegnato/letto), live via openEventsTick.
class _ReadReceipt extends StatefulWidget {
  const _ReadReceipt({required this.message});
  final Message message;

  @override
  State<_ReadReceipt> createState() => _ReadReceiptState();
}

class _ReadReceiptState extends State<_ReadReceipt> {
  @override
  void initState() {
    super.initState();
    AppServices.instance.openEventsTick.addListener(_onTick);
  }

  @override
  void dispose() {
    AppServices.instance.openEventsTick.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // "Letto" = il destinatario ha un evento 'granted'. Lo stato arriva
    // dall'insieme caricato una volta sola dalla conversazione: nessuna
    // richiesta al server per singola bolla.
    final m = widget.message;
    final svc = AppServices.instance;
    // Per i TESTI vale anche la soglia: se l'altro ha letto un mio messaggio
    // più recente, era in chat oltre questo punto. Senza, un messaggio rimasto
    // fuori dallo schermo restava a 2 spunte mentre il successivo ne aveva 3.
    // Per le FOTO no: l'apertura è deliberata e non si deduce.
    final read = svc.isReadByRecipient(m.id) ||
        (m.type == MessageType.text &&
            svc.isReadUpTo(m.conversationId, m.createdAt));
    // Distinzione per CONTEGGIO di spunte (accessibile anche ai daltonici):
    //   1 spunta grigia  = in invio (il server non ha ancora confermato)
    //   2 spunte grigie  = inviato (il server ha salvato il messaggio)
    //   3 spunte blu     = letto (il destinatario l'ha aperto)
    final bool pending = widget.message.pending;
    final int count = pending ? 1 : (read ? 3 : 2);
    final Color color = read ? _readBlue : cs.onSurfaceVariant;
    final String tip = pending ? 'In invio' : (read ? 'Letto' : 'Inviato');
    return Tooltip(
      message: tip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          count,
          (_) => Icon(Icons.check, size: 12, color: color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TESTO
// ---------------------------------------------------------------------------
class _TextBubble extends StatefulWidget {
  const _TextBubble({
    required this.message,
    required this.isMine,
    required this.other,
    required this.onReply,
    required this.resolveReply,
    required this.onQuoteTap,
  });
  final Message message;
  final bool isMine;
  final Profile other;
  final void Function(Message) onReply;
  final Message? Function(String) resolveReply;
  final void Function(String) onQuoteTap;

  @override
  State<_TextBubble> createState() => _TextBubbleState();
}

class _TextBubbleState extends State<_TextBubble> {
  bool _started = false;
  bool _loading = false;
  String? _error;

  String? get _cached => AppServices.instance.cachedText(widget.message.id);

  @override
  void initState() {
    super.initState();
    // Quando una revoca svuota la cache (purgeInaccessible) la bolla deve
    // ridisegnarsi: senza questo ascolto continuava a mostrare il testo già
    // in memoria, e la revoca sembrava non aver effetto.
    AppServices.instance.accessTick.addListener(_onAccessChanged);
  }

  @override
  void dispose() {
    AppServices.instance.accessTick.removeListener(_onAccessChanged);
    super.dispose();
  }

  void _onAccessChanged() {
    if (!mounted) return;
    // Il testo è stato tolto dalla cache → riparti da zero (rifarà la
    // richiesta al server, che negherà se il contenuto è stato revocato).
    if (_cached == null) {
      setState(() {
        _started = false;
        _loading = false;
        _error = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _TextBubble old) {
    super.didUpdateWidget(old);
    // Se il messaggio è stato modificato da ALTRI, ridecifra (le mie modifiche
    // sono già in cache).
    if (old.message.editedAt != widget.message.editedAt && !widget.isMine) {
      AppServices.instance.invalidateText(widget.message.id);
      _started = false;
      _error = null;
    }
  }

  void _ensureDecrypted() {
    if (_started || _cached != null) return;
    _started = true;
    _loading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _decrypt());
  }

  Future<void> _decrypt() async {
    try {
      final bytes =
          await AppServices.instance.openContentBytes(widget.message);
      AppServices.instance.cacheText(widget.message.id, utf8.decode(bytes));
      if (mounted) setState(() => _loading = false);
    } on KeyRequestException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.userMessage;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _friendlyDecryptError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cached = _cached;
    if (cached == null && _error == null) {
      _ensureDecrypted();
      if (_loading) return _spinnerBubble(context, mine: widget.isMine);
    }
    final body = cached ??
        (_error != null
            ? (widget.isMine ? '(messaggio inviato)' : _error!)
            : '');
    final placeholder = cached == null;
    // Emoji "grandi" come WhatsApp quando il messaggio è solo emoji e corto.
    final bigEmoji = !placeholder && _isEmojiOnly(body);
    return GestureDetector(
      onLongPress: () => showMessageActions(context,
          message: widget.message,
          isMine: widget.isMine,
          other: widget.other,
          onReply: widget.onReply),
      child: _bubbleShell(
        context,
        mine: widget.isMine,
        child: Column(
          crossAxisAlignment: widget.isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (widget.message.replyTo != null)
              _quoteHeader(context, widget.message.replyTo!, widget.isMine,
                  widget.other, widget.resolveReply, widget.onQuoteTap),
            if (placeholder || bigEmoji)
              Text(body,
                  style: placeholder
                      ? TextStyle(
                          fontStyle: FontStyle.italic,
                          color: cs.onSurfaceVariant)
                      : const TextStyle(fontSize: 40))
            else
              // Testo normale: link http/https cliccabili.
              LinkifiedText(body),
            const SizedBox(height: 4),
            _footer(context, widget.message, mine: widget.isMine),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FOTO (sessione: chiusa → anteprima → fullscreen)
// ---------------------------------------------------------------------------
class _PhotoBubble extends StatefulWidget {
  const _PhotoBubble({
    required this.message,
    required this.isMine,
    required this.other,
    required this.onReply,
    required this.resolveReply,
    required this.onQuoteTap,
  });
  final Message message;
  final bool isMine;
  final Profile other;
  final void Function(Message) onReply;
  final Message? Function(String) resolveReply;
  final void Function(String) onQuoteTap;

  @override
  State<_PhotoBubble> createState() => _PhotoBubbleState();
}

class _PhotoBubbleState extends State<_PhotoBubble> {
  late Future<MessageAccess?> _accessFuture;

  Uint8List? _bytes;
  DateTime? _expiresAt;
  bool _protected = false;
  bool _secured = false;
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _opening = false;
  bool _requested = false;
  bool _inGallery = false; // solo per foto galleryOffered

  @override
  void initState() {
    super.initState();
    // Bolla ottimistica ("in invio"): non c'è ancora nulla sul server da
    // interrogare, mostriamo l'anteprima locale.
    _accessFuture = widget.message.pending
        ? Future<MessageAccess?>.value(null)
        : AppServices.instance.access.getMyAccess(widget.message.id);
    // Aggiorna lo stato quando una richiesta viene gestita (rinnovo/reinvio).
    AppServices.instance.accessTick.addListener(_reloadAccess);
    if (widget.message.galleryOffered) {
      _loadGalleryState();
      AppServices.instance.galleryTick.addListener(_loadGalleryState);
    }
  }

  Future<void> _loadGalleryState() async {
    if (!widget.message.galleryOffered) return;
    try {
      final saved =
          await AppServices.instance.gallery.isSaved(widget.message.id);
      if (mounted) setState(() => _inGallery = saved);
    } catch (_) {}
  }

  void _reloadAccess() {
    if (!mounted) return;
    // Non disturbare una sessione aperta.
    if (_bytes != null) return;
    setState(() {
      _accessFuture =
          AppServices.instance.access.getMyAccess(widget.message.id);
    });
  }

  Future<void> _openSession() async {
    if (_opening) return;
    // Foto mia già in RAM (eco dell'invio): mostrala senza passare dal server
    // (evita "contenuto non disponibile" se manca la copia-chiave del mittente).
    if (widget.isMine) {
      final echo = AppServices.instance.photoEcho[widget.message.id];
      if (echo != null) {
        setState(() {
          _bytes = echo;
          _protected = false;
        });
        return;
      }
    }
    setState(() => _opening = true);
    try {
      final bytes =
          await AppServices.instance.openContentBytes(widget.message);
      final a = await AppServices.instance.access.getMyAccess(widget.message.id);
      // Se il widget è stato smontato durante le await, non acquisire il guard
      // né trattenere i byte: azzera e esci (evita leak di FLAG_SECURE/plaintext).
      if (!mounted) {
        for (var i = 0; i < bytes.length; i++) {
          bytes[i] = 0;
        }
        return;
      }
      final protected = a?.protectionEnabled ?? false;
      final expiresAt = protected ? a?.expiresAt : null;
      if (protected) {
        SecureScreenGuard.acquire();
        _secured = true;
      }
      _bytes = bytes;
      _protected = protected;
      _expiresAt = expiresAt;
      _opening = false;
      if (expiresAt != null) _startTimer(expiresAt);
      if (mounted) setState(() {});
    } on KeyRequestException catch (e) {
      _opening = false;
      if (mounted) {
        // Foto mia non trovata sul server = inviata con un'altra identità/
        // account: messaggio più chiaro del generico "non disponibile".
        final msg = (e.reason == KeyDenialReason.notFound && widget.isMine)
            ? 'Questa foto è stata inviata con un\'altra identità: non è '
                'apribile su questo dispositivo.'
            : e.userMessage;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
      _reloadAccess();
    } catch (e) {
      _opening = false;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyDecryptError(e))));
      }
    }
  }

  void _startTimer(DateTime expiresAt) {
    void tick() {
      final rem = expiresAt.toUtc().difference(DateTime.now().toUtc());
      if (rem.inMilliseconds <= 0) {
        _closeSession();
      } else if (mounted) {
        setState(() => _remaining = rem);
      }
    }

    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void _closeSession() {
    _timer?.cancel();
    _timer = null;
    if (_secured) {
      SecureScreenGuard.release();
      _secured = false;
    }
    final b = _bytes;
    if (b != null) {
      for (var i = 0; i < b.length; i++) {
        b[i] = 0;
      }
    }
    _bytes = null;
    _expiresAt = null;
    _reloadAccess();
  }

  Future<void> _openFullscreen() async {
    final bytes = _bytes;
    if (bytes == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ViewerScreen(
        bytes: bytes,
        expiresAt: _expiresAt,
        secure: _protected,
        message: widget.message, // abilita la 🌙 preferiti
      ),
    ));
  }

  Future<void> _requestAgain() async {
    setState(() => _requested = true);
    try {
      // Registra la richiesta (Notifiche/badge) E la mostra come messaggio in
      // chat, così il mittente la vede nel flusso della conversazione.
      await AppServices.instance.requestReopen(
        photoMessageId: widget.message.id,
        conversationId: widget.message.conversationId,
        ownerId: widget.message.senderId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Richiesta inviata al mittente.')));
      }
    } catch (e) {
      if (mounted) setState(() => _requested = false);
    }
  }

  @override
  void dispose() {
    AppServices.instance.accessTick.removeListener(_reloadAccess);
    AppServices.instance.galleryTick.removeListener(_loadGalleryState);
    _timer?.cancel();
    if (_secured) SecureScreenGuard.release();
    final b = _bytes;
    if (b != null) {
      for (var i = 0; i < b.length; i++) {
        b[i] = 0;
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.pending) return _pendingPhotoBubble(context);
    if (_bytes != null) {
      return GestureDetector(
        onLongPress: () => showMessageActions(context,
            message: widget.message,
            isMine: widget.isMine,
            other: widget.other,
            onReply: widget.onReply),
        child: _bubbleShell(
          context,
          mine: widget.isMine,
          child: Column(
            crossAxisAlignment: widget.isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (widget.message.replyTo != null)
                _quoteHeader(context, widget.message.replyTo!, widget.isMine,
                    widget.other, widget.resolveReply, widget.onQuoteTap),
              Stack(
                children: [
                  GestureDetector(
                    onTap: _openFullscreen,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: WatermarkOverlay(
                        child: Image.memory(_bytes!,
                            height: 220,
                            width: 260,
                            cacheWidth: 520,
                            fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: _closeSession,
                      child: const CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.black54,
                        child:
                            Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_protected && _expiresAt != null) ...[
                    const Icon(Icons.timer_outlined, size: 13),
                    const SizedBox(width: 3),
                    Text(formatHms(_remaining),
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(width: 8),
                  ],
                  _footer(context, widget.message, mine: widget.isMine),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<MessageAccess?>(
      future: _accessFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _spinnerBubble(context, mine: widget.isMine);
        }
        return _closedCard(context, snap.data);
      },
    );
  }

  /// Anteprima locale mentre la foto è "in invio" (bolla ottimistica): mostra
  /// l'immagine con un velo + spinner e il footer con 1 spunta.
  Widget _pendingPhotoBubble(BuildContext context) {
    final echo = AppServices.instance.photoEcho[widget.message.id];
    return _bubbleShell(
      context,
      mine: widget.isMine,
      child: Column(
        crossAxisAlignment: widget.isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (echo != null)
                  Image.memory(echo,
                      height: 220, width: 260, cacheWidth: 520, fit: BoxFit.cover)
                else
                  Container(height: 220, width: 260, color: Colors.black26),
                Container(
                  height: 220,
                  width: 260,
                  color: Colors.black.withValues(alpha: 0.25),
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _footer(context, widget.message, mine: widget.isMine),
        ],
      ),
    );
  }

  Widget _closedCard(BuildContext context, MessageAccess? a) {
    final cs = Theme.of(context).colorScheme;
    final openable = a?.isOpenable ?? false;
    final protected = a?.protectionEnabled ?? false;

    final gallery = widget.message.galleryOffered;
    String title;
    String subtitle;
    if (gallery && openable) {
      // Foto galleria: distingui "disponibile" (offerta) da "in galleria" (salvata).
      title = _inGallery ? 'In galleria' : 'Foto disponibile';
      subtitle = _inGallery
          ? 'Salvata · senza limiti'
          : 'Senza limiti · tieni premuto per salvarla';
    } else if (!protected) {
      title = 'Foto';
      subtitle = 'Tocca per aprire';
    } else if (!openable) {
      title = 'Foto protetta';
      if (a != null && !a.active) {
        subtitle = a.isExpired ? 'Scaduta' : 'Revocata dal mittente';
      } else if (a != null && a.isExpired) {
        subtitle = 'Scaduta';
      } else {
        subtitle = 'Aperture esaurite';
      }
    } else {
      title = 'Foto protetta';
      final opens = a!.unlimitedOpens
          ? 'aperture illimitate'
          : '${a.remainingOpens} aperture rimaste';
      final dur =
          a.unlimitedDuration ? 'senza scadenza' : '${a.maxDurationSeconds}s';
      subtitle = '$opens · $dur';
    }

    // Il destinatario può chiedere di riaprire un contenuto non disponibile —
    // MA non se è stato revocato (il blob è cancellato: irrecuperabile).
    final revoked = a != null && !a.active && !a.isExpired;
    final canRequest = !widget.isMine && a != null && !openable && !revoked;

    return GestureDetector(
      onLongPress: () => showMessageActions(context,
          message: widget.message,
          isMine: widget.isMine,
          other: widget.other,
          onReply: widget.onReply),
      child: _bubbleShell(
        context,
        mine: widget.isMine,
        child: Column(
          crossAxisAlignment: widget.isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (widget.message.replyTo != null)
              _quoteHeader(context, widget.message.replyTo!, widget.isMine,
                  widget.other, widget.resolveReply, widget.onQuoteTap),
            InkWell(
              onTap: (openable && !_opening) ? _openSession : null,
              borderRadius: BorderRadius.circular(12),
              child: Opacity(
                opacity: openable ? 1 : 0.55,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        (gallery && openable)
                            ? (_inGallery
                                ? Icons.bookmark
                                : Icons.collections_outlined)
                            : (protected
                                ? Icons.lock_outline
                                : Icons.photo_outlined),
                        color: (gallery && openable && _inGallery)
                            ? Colors.green
                            : cs.primary),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(openable ? 'Tocca per aprire' : title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(subtitle,
                              style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ),
                    ),
                    if (_opening) ...[
                      const SizedBox(width: 10),
                      const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ],
                ),
              ),
            ),
            if (canRequest)
              TextButton.icon(
                onPressed: _requested ? null : _requestAgain,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(_requested ? 'Richiesta inviata' : 'Richiedi di nuovo'),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact),
              ),
            const SizedBox(height: 4),
            _footer(context, widget.message, mine: widget.isMine),
          ],
        ),
      ),
    );
  }
}
