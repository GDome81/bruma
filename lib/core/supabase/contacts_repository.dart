import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'profile_repository.dart';

class ContactsRepository {
  ContactsRepository(this._client, this._profiles);
  final SupabaseClient _client;
  final ProfileRepository _profiles;

  String get _uid => _client.auth.currentUser!.id;

  /// Alfabeto senza caratteri ambigui (no 0/O/1/I/L).
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  String _generateCode() {
    final rnd = Random.secure();
    final buf = StringBuffer('BRU-');
    for (var i = 0; i < 8; i++) {
      buf.write(_alphabet[rnd.nextInt(_alphabet.length)]);
      if (i == 3) buf.write('-');
    }
    return buf.toString();
  }

  Future<String> getOrCreateMyInviteCode() async {
    final existing = await _client
        .from('invite_codes')
        .select('code')
        .eq('owner', _uid)
        .limit(1)
        .maybeSingle();
    if (existing != null) return existing['code'] as String;

    // Ritenta in caso di collisione del codice (primary key).
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = _generateCode();
      try {
        await _client
            .from('invite_codes')
            .insert({'code': code, 'owner': _uid});
        return code;
      } on PostgrestException catch (e) {
        if (e.code == '23505') continue; // unique_violation
        rethrow;
      }
    }
    throw Exception('Impossibile generare un codice invito univoco.');
  }

  /// Riscatta il codice di un altro utente: crea contatto + conversazione e
  /// restituisce il profilo del contatto (con chiave pubblica).
  Future<RedeemResult> redeemInvite(String code) async {
    final res =
        await _client.rpc('redeem_invite', params: {'p_code': code.trim()});
    return RedeemResult.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<List<Profile>> myContacts() async {
    final rows =
        await _client.from('contacts').select('contact').eq('owner', _uid);
    final ids = rows.map((r) => r['contact'] as String).toList();
    final map = await _profiles.getProfilesByIds(ids);
    return map.values.toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  }
}
