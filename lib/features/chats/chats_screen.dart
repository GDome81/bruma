import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/app_services.dart';
import '../../core/local_prefs.dart';
import '../../core/models/models.dart';
import '../../shared/widgets.dart';
import '../contacts/add_contact_screen.dart';
import '../contacts/contacts_screen.dart';
import '../conversation/conversation_screen.dart';

/// Lista delle conversazioni, in stile WhatsApp semplificato.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  late Future<List<ConversationView>> _future;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _future = AppServices.instance.conversations.listConversationViews();
    // Aggiorna la lista quando arrivano/partono messaggi.
    _sub = AppServices.instance.conversations
        .watchAllMyMessages()
        .listen((_) => _reload());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = AppServices.instance.conversations.listConversationViews();
    });
  }

  Future<void> _openAddContact() async {
    final convId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AddContactScreen()),
    );
    _reload();
    if (convId != null && mounted) {
      // Apri direttamente la conversazione appena creata.
      final views = await AppServices.instance.conversations
          .listConversationViews();
      final match = views.where((v) => v.conversation.id == convId).toList();
      if (match.isNotEmpty && mounted) {
        _openConversation(match.first);
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleBiometric() async {
    final enabling = !LocalPrefs.biometricEnabled;
    if (enabling) {
      try {
        final supported = await LocalAuthentication().isDeviceSupported();
        if (!supported) {
          _snack('Nessun blocco schermo o biometria configurato sul dispositivo.');
          return;
        }
      } catch (_) {
        _snack('Biometria non disponibile su questo dispositivo.');
        return;
      }
    }
    await LocalPrefs.setBiometricEnabled(enabling);
    if (!mounted) return;
    setState(() {});
    _snack(enabling
        ? 'Blocco biometrico attivato (attivo alla prossima riapertura).'
        : 'Blocco biometrico disattivato.');
  }

  void _openConversation(ConversationView v) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ConversationScreen(
            conversationId: v.conversation.id,
            other: v.other,
          ),
        ))
        .then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bruma'),
        actions: [
          IconButton(
            tooltip: 'Contatti',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ContactsScreen()),
              );
              _reload();
            },
            icon: const Icon(Icons.people_alt_outlined),
          ),
          IconButton(
            tooltip: 'Aggiungi contatto',
            onPressed: _openAddContact,
            icon: const Icon(Icons.person_add_alt_1),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'signout') AppServices.instance.signOut();
              if (v == 'biometric') _toggleBiometric();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  AppServices.instance.myProfile?.displayName ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: 'biometric',
                checked: LocalPrefs.biometricEnabled,
                child: const Text('Blocco biometrico'),
              ),
              const PopupMenuItem(value: 'signout', child: Text('Esci')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddContact,
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<ConversationView>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done &&
                !snap.hasData) {
              return const LoadingView();
            }
            if (snap.hasError) {
              return ErrorView(
                  message: 'Errore: ${snap.error}', onRetry: _reload);
            }
            final views = snap.data ?? [];
            if (views.isEmpty) {
              return LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: c.maxHeight,
                    child: EmptyView(
                      icon: Icons.forum_outlined,
                      title: 'Nessuna chat',
                      subtitle:
                          'Aggiungi un contatto con il suo codice o QR per '
                          'iniziare a scriverti.',
                      action: FilledButton.icon(
                        onPressed: _openAddContact,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Aggiungi contatto'),
                      ),
                    ),
                  ),
                ),
              );
            }
            return ListView.separated(
              itemCount: views.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _tile(views[i]),
            );
          },
        ),
      ),
    );
  }

  Widget _tile(ConversationView v) {
    final me = AppServices.instance.uid;
    final last = v.lastMessage;
    String preview;
    if (last == null) {
      preview = 'Nessun messaggio';
    } else {
      final mine = last.senderId == me;
      final body = last.type == MessageType.photo
          ? 'Foto'
          : 'Messaggio cifrato';
      preview = mine ? 'Tu: $body' : body;
    }
    final trimmed = v.other.displayName.trim();
    final initials = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
    return ListTile(
      leading: CircleAvatar(child: Text(initials)),
      title: Text(v.other.displayName),
      subtitle: Row(
        children: [
          Icon(
            last?.type == MessageType.photo
                ? Icons.photo_camera_outlined
                : Icons.lock_outline,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(preview,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      trailing: last == null
          ? null
          : Text(formatTimestamp(last.createdAt),
              style: Theme.of(context).textTheme.labelSmall),
      onTap: () => _openConversation(v),
    );
  }
}
