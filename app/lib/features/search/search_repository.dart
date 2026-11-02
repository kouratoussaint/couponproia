// Recherche (B4) : équipes, compétitions, matchs proches, coupons. Lecture seule ;
// les correspondances ignorent la casse et les accents.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../assistant/data/assistant_models.dart';
import '../coupons/data/coupon_models.dart';
import '../matches/data/sports_format.dart';
import '../matches/data/sports_models.dart';
import '../matches/data/sports_repository.dart';

/// Requête utile : au moins 2 caractères (espaces retirés).
bool searchable(String q) => q.trim().length >= 2;

/// Le texte contient-il la recherche (casse et accents ignorés) ?
bool matchesText(String text, String query) =>
    simplify(text).contains(simplify(query.trim()));

/// Équipes dont le nom correspond, celles qui commencent par la recherche d'abord.
List<TeamRef> searchTeams(List<TeamRef> teams, String query, {int max = 12}) {
  if (!searchable(query)) return const [];
  final q = simplify(query.trim());
  final found = teams.where((t) => simplify(t.name).contains(q)).toList()
    ..sort((a, b) {
      final sa = simplify(a.name).startsWith(q) ? 0 : 1;
      final sb = simplify(b.name).startsWith(q) ? 0 : 1;
      return sa != sb ? sa - sb : a.name.compareTo(b.name);
    });
  return found.take(max).toList();
}

List<CompetitionRef> searchCompetitions(
        List<CompetitionRef> list, String query) =>
    !searchable(query)
        ? const []
        : [
            for (final c in list)
              if (matchesText(c.name, query) ||
                  matchesText(c.country ?? '', query))
                c
          ];

/// Coupons de la plateforme : nom ou une équipe des sélections (coupons réservés exclus).
List<Coupon> searchCoupons(List<Coupon> list, String query) =>
    !searchable(query)
        ? const []
        : [
            for (final c in list)
              if (!c.locked &&
                  (matchesText(c.title, query) ||
                      c.selections.any((s) =>
                          matchesText(s.match.home, query) ||
                          matchesText(s.match.away, query))))
                c
          ];

/// Vos coupons : nom ou une équipe des sélections.
List<UserCoupon> searchMyCoupons(List<UserCoupon> list, String query) =>
    !searchable(query)
        ? const []
        : [
            for (final c in list)
              if (matchesText(c.title, query) ||
                  c.selections.any((s) =>
                      matchesText(s.match.home, query) ||
                      matchesText(s.match.away, query)))
                c
          ];

/// Toutes les équipes suivies par l'application (quelques centaines de lignes, chargées une fois).
final allTeamsProvider = FutureProvider<List<TeamRef>>((ref) async {
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('teams')
      .select('id, name, logo_url')
      .order('name')
      .limit(2000);
  return rows.map(TeamRef.fromJson).toList();
});

/// Matchs des équipes trouvées : 3 jours avant à 10 jours après aujourd'hui.
/// Clé : identifiants triés, séparés par des virgules.
final teamMatchesProvider = FutureProvider.autoDispose
    .family<List<MatchSummary>, String>((ref, ids) async {
  if (ids.isEmpty) return const [];
  final now = DateTime.now().toUtc();
  return ref.watch(sportsRepositoryProvider).matchesOfTeams(
      ids.split(',').map(int.parse).toList(),
      from: now.subtract(const Duration(days: 3)),
      to: now.add(const Duration(days: 10)));
});
