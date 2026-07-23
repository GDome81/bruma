import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/local_prefs.dart';
import '../../core/models/models.dart';
import '../../shared/widgets.dart';
import '../auth/export_identity_screen.dart';
import '../auth/import_identity_screen.dart';
import '../contacts/add_contact_screen.dart';
import '../contacts/contacts_screen.dart';
import '../conversation/conversation_screen.dart';
import '../settings/app_settings_screen.dart';
import '../tutorial/tutorial_screen.dart';

/// Lista delle conversazioni, in stile WhatsApp semplificato.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen>
    with WidgetsBindingObserver {
  late Future<List<ConversationView>> _future;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = AppServices.instance.conversations.listConversationViews();
    // Aggiorna la lista quando arrivano/partono messaggi.
    _sub = AppServices.instance.conversations
        .watchAllMyMessages()
        .listen((_) => _reload());
    _maybeShowTutorial();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al rientro in primo piano il socket realtime potrebbe essersi chiuso in
    // background: ricarico la lista per non restare con conteggi non letti o
    // chat mancanti finché non arriva il prossimo evento.
    if (state == AppLifecycleState.resumed) _reload();
  }

  /// Al primo accesso (una sola volta) mostra il tutorial, appena la home è
  /// pronta.
  void _maybeShowTutorial() {
    if (LocalPrefs.tutorialSeen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || LocalPrefs.tutorialSeen) return;
      Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const TutorialScreen(),
      ));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
              if (v == 'security') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AppSettingsScreen()));
              }
              if (v == 'export') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ExportIdentityScreen()));
              }
              if (v == 'import') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ImportIdentityScreen(
                    // La schermata si chiude da sola: qui solo la notifica.
                    onCompleted: () => _snack(
                        'Identità importata. Riapri l\'app per aggiornare tutte le chat.'),
                  ),
                ));
              }
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
              const PopupMenuItem(
                  value: 'security', child: Text('Sicurezza')),
              const PopupMenuItem(
                  value: 'export', child: Text('Esporta identità')),
              const PopupMenuItem(
                  value: 'import', child: Text('Importa identità')),
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
    final cs = Theme.of(context).colorScheme;
    final last = v.lastMessage;
    final unread = v.unread;
    final hasUnread = unread > 0;
    final trimmed = v.other.displayName.trim();
    final initials = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
    // Nessuna anteprima del contenuto: solo nome, orario e "pallino" col
    // numero di messaggi da leggere.
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(child: Text(initials)),
          if (hasUnread)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        v.other.displayName,
        style: TextStyle(
            fontWeight: hasUnread ? FontWeight.bold : FontWeight.w500),
      ),
      // Larghezza fissa: evita l'assert "Trailing widget consumes the entire
      // tile width" di ListTile e tiene orario e badge sempre allineati.
      trailing: SizedBox(
        width: 62,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (last != null)
            Text(
              formatTimestamp(last.createdAt),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: hasUnread ? cs.primary : null,
                  fontWeight: hasUnread ? FontWeight.bold : null),
            ),
          const SizedBox(height: 6),
          if (hasUnread) _unreadBadge(unread, cs) else const SizedBox(height: 18),
        ],
        ),
      ),
      onTap: () => _openConversation(v),
    );
  }

  Widget _unreadBadge(int n, ColorScheme cs) {
    final label = n > 99 ? '99+' : '$n';
    // NB: niente `alignment` qui — un Container con alignment sotto vincoli
    // "loose" si allarga a tutta la larghezza disponibile (era la causa del
    // pallino a barra piena e del titolo schiacciato). Così si adatta al testo.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
            color: cs.onPrimary,
            fontSize: 12,
            height: 1.0,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}
