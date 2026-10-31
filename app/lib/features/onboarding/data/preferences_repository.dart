import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';

/// Niveau déclaré : règle les explications affichées, jamais les chiffres.
enum UserLevel {
  debutant('Débutant', 'Je découvre les paris sportifs'),
  intermediaire('Intermédiaire', 'Je suis les stats et les cotes'),
  expert('Expert', 'Je fais mes propres analyses');

  const UserLevel(this.label, this.description);

  final String label;
  final String description;

  static UserLevel? fromName(String? name) {
    for (final l in values) {
      if (l.name == name) return l;
    }
    return null;
  }
}

class UserPreferences {
  const UserPreferences({
    this.favoriteCompetitions = const {},
    this.level,
    this.onboardedAt,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> j) => UserPreferences(
        favoriteCompetitions: {
          for (final c in (j['favorite_competitions'] as List? ?? const []))
            (c as num).toInt(),
        },
        level: UserLevel.fromName(j['level'] as String?),
        onboardedAt: j['onboarded_at'] == null
            ? null
            : DateTime.parse(j['onboarded_at'] as String),
      );

  final Set<int> favoriteCompetitions;
  final UserLevel? level;
  final DateTime? onboardedAt;

  bool get needsOnboarding => onboardedAt == null;

  /// Définitions affichées sauf pour un expert.
  bool get showExplanations => level != UserLevel.expert;
}

class PreferencesRepository {
  PreferencesRepository(this._client);

  final SupabaseClient _client;

  Future<UserPreferences?> mine() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client
        .from('user_preferences')
        .select('favorite_competitions, level, onboarded_at')
        .eq('user_id', user.id)
        .maybeSingle();
    return row == null ? null : UserPreferences.fromJson(row);
  }

  Future<void> save({
    Set<int>? favoriteCompetitions,
    UserLevel? level,
    bool markOnboarded = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw AuthException('Session expirée');
    await _client.from('user_preferences').update({
      if (favoriteCompetitions != null)
        'favorite_competitions': favoriteCompetitions.toList()..sort(),
      if (level != null) 'level': level.name,
      if (markOnboarded)
        'onboarded_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', user.id);
  }
}

final preferencesRepositoryProvider = Provider<PreferencesRepository>(
    (ref) => PreferencesRepository(ref.watch(supabaseClientProvider)));

final myPreferencesProvider = FutureProvider<UserPreferences?>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(preferencesRepositoryProvider).mine();
});
