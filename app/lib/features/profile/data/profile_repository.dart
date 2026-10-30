import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';

class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.countryCode,
    required this.createdAt,
    this.avatarUrl,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        countryCode: json['country_code'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        avatarUrl: json['avatar_url'] as String?,
      );

  final String id;
  final String displayName;
  final String countryCode;
  final DateTime createdAt;
  final String? avatarUrl;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<Profile?> fetchMine() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client
        .from('profiles')
        .select('id, display_name, country_code, created_at, avatar_url')
        .eq('id', user.id)
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<void> updateDisplayName(String name) async {
    final user = _client.auth.currentUser;
    if (user == null) throw AuthException('Session expirée');
    await _client.from('profiles').update({'display_name': name.trim()}).eq('id', user.id);
  }

  /// Suppression définitive, exécutée côté serveur (Edge Function `delete-account`).
  Future<void> deleteAccount() async {
    await _client.functions.invoke('delete-account', body: {'confirmation': 'SUPPRIMER'});
    await _client.auth.signOut();
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(supabaseClientProvider)),
);

final myProfileProvider = FutureProvider<Profile?>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(profileRepositoryProvider).fetchMine();
});
