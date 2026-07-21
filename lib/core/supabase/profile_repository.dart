import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Future<Profile?> getMyProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row =
        await _client.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  Future<Profile?> getProfile(String uid) async {
    final row =
        await _client.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  Future<Map<String, Profile>> getProfilesByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows =
        await _client.from('profiles').select().inFilter('id', ids);
    final map = <String, Profile>{};
    for (final r in rows) {
      final p = Profile.fromMap(r);
      map[p.id] = p;
    }
    return map;
  }

  Future<void> createProfile({
    required String displayName,
    required String publicKeyB64,
  }) async {
    await _client.from('profiles').upsert({
      'id': _uid,
      'display_name': displayName,
      'public_key': publicKeyB64,
    });
  }

  Future<void> updatePublicKey(String publicKeyB64) async {
    await _client
        .from('profiles')
        .update({'public_key': publicKeyB64}).eq('id', _uid);
  }
}
