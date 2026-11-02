import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.countryCode,
    required this.createdAt,
    this.avatarUrl,
    this.timezone = 'Africa/Ouagadougou',
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        countryCode: json['country_code'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        avatarUrl: json['avatar_url'] as String?,
        timezone: json['timezone'] as String? ?? 'Africa/Ouagadougou',
      );

  final String id;
  final String displayName;
  final String countryCode;
  final DateTime createdAt;
  final String? avatarUrl;
  final String timezone;

  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
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
        .select(
            'id, display_name, country_code, created_at, avatar_url, timezone')
        .eq('id', user.id)
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<void> updateDisplayName(String name) async {
    final user = _client.auth.currentUser;
    if (user == null) throw AuthException(tr('Session expirée'));
    await _client
        .from('profiles')
        .update({'display_name': name.trim()}).eq('id', user.id);
  }

  /// Pseudo, pays, fuseau horaire et photo (colonnes modifiables par l'utilisateur).
  Future<void> updateProfile({
    required String displayName,
    required String countryCode,
    required String timezone,
    required String? avatarUrl,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw AuthException(tr('Session expirée'));
    await _client.from('profiles').update({
      'display_name': displayName.trim(),
      'country_code': countryCode,
      'timezone': timezone,
      'avatar_url': avatarUrl,
    }).eq('id', user.id);
  }

  static const avatarBucket = 'profile-avatars';

  /// Envoie la photo dans son dossier et renvoie son adresse publique.
  Future<String> uploadAvatar(Uint8List bytes, String extension) async {
    final user = _client.auth.currentUser;
    if (user == null) throw AuthException(tr('Session expirée'));
    final ext = extension.toLowerCase() == 'png' ? 'png' : 'jpg';
    final path =
        '${user.id}/photo-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from(avatarBucket).uploadBinary(path, bytes,
        fileOptions: FileOptions(
            contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
            upsert: true));
    return _client.storage.from(avatarBucket).getPublicUrl(path);
  }

  /// Supprime les anciennes photos (celle gardée exceptée).
  Future<void> cleanAvatars(String? keepUrl) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final files = await _client.storage.from(avatarBucket).list(path: user.id);
    final old = [
      for (final f in files)
        if (keepUrl == null || !keepUrl.endsWith('/${user.id}/${f.name}'))
          '${user.id}/${f.name}'
    ];
    if (old.isNotEmpty) await _client.storage.from(avatarBucket).remove(old);
  }

  /// Vérifie le mot de passe actuel avant un changement sensible (e-mail, mot de passe).
  Future<void> verifyPassword(String password) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) throw AuthException(tr('Session expirée'));
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Nouvelle adresse : un code à 6 chiffres y est envoyé.
  Future<void> requestEmailChange(String newEmail) =>
      _client.auth.updateUser(UserAttributes(email: newEmail.trim()));

  Future<void> confirmEmailChange(String newEmail, String code) =>
      _client.auth.verifyOTP(
          type: OtpType.emailChange,
          email: newEmail.trim(),
          token: code.trim());

  Future<void> changePassword(String newPassword) =>
      _client.auth.updateUser(UserAttributes(password: newPassword));

  /// Suppression définitive, exécutée côté serveur (Edge Function `delete-account`).
  Future<void> deleteAccount() async {
    await _client.functions
        .invoke('delete-account', body: {'confirmation': 'SUPPRIMER'});
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
