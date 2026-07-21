import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models/models.dart';
import '../../shared/widgets.dart';
import '../conversation/conversation_screen.dart';
import 'add_contact_screen.dart';

/// Elenco dei contatti aggiunti; toccandone uno si apre la conversazione.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late Future<List<Profile>> _future;

  @override
  void initState() {
    super.initState();
    _future = AppServices.instance.contacts.myContacts();
  }

  void _reload() {
    setState(() => _future = AppServices.instance.contacts.myContacts());
  }

  Future<void> _openChat(Profile contact) async {
    final conv =
        await AppServices.instance.conversations.getWithUser(contact.id);
    if (!mounted) return;
    if (conv == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversazione non trovata.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationScreen(
        conversationId: conv.id,
        other: contact,
      ),
    ));
  }

  Future<void> _add() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddContactScreen()),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contatti'),
        actions: [
          IconButton(
            tooltip: 'Aggiungi contatto',
            onPressed: _add,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<Profile>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const LoadingView();
            }
            if (snap.hasError) {
              return ErrorView(message: 'Errore: ${snap.error}', onRetry: _reload);
            }
            final contacts = snap.data ?? [];
            if (contacts.isEmpty) {
              return LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: c.maxHeight,
                    child: EmptyView(
                      icon: Icons.people_outline,
                      title: 'Nessun contatto',
                      subtitle: 'Aggiungi qualcuno con il suo codice o QR.',
                      action: FilledButton.icon(
                        onPressed: _add,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Aggiungi contatto'),
                      ),
                    ),
                  ),
                ),
              );
            }
            return ListView.separated(
              itemCount: contacts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = contacts[i];
                final initials = c.displayName.trim().isNotEmpty
                    ? c.displayName.trim()[0].toUpperCase()
                    : '?';
                return ListTile(
                  leading: CircleAvatar(child: Text(initials)),
                  title: Text(c.displayName),
                  onTap: () => _openChat(c),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
