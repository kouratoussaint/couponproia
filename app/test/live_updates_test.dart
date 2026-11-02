// Direct en temps réel : état des matchs appliqué sans actualisation manuelle.
import 'package:coupon_pro_ia/features/matches/data/live_updates.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_format.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/match_fixtures.dart';

LivePatch _patch(
        {String status = 'live',
        String short = '2H',
        int elapsed = 65,
        int hg = 1,
        int ag = 0,
        String at = '2026-10-30T21:10:00+00:00'}) =>
    LivePatch.fromJson({
      'id': 5988,
      'kickoff_at': '2099-10-30T20:05:00+00:00',
      'status': status,
      'status_short': short,
      'elapsed': elapsed,
      'home_goals': hg,
      'away_goals': ag,
      'source_updated_at': at,
    });

class _Fixed extends LiveUpdates {
  _Fixed(Map<int, LivePatch> initial) : super(null) {
    state = initial;
  }
}

void main() {
  test('état en direct plus récent appliqué au match', () {
    final m = lilleLens(status: 'live', hg: 0, ag: 0);
    final live = withLive(m, _patch());
    expect(live.elapsed, 65);
    expect(statusLabel(live), '65’');
    expect(live.homeGoals, 1);
    expect(live.home.name, 'Lille', reason: 'le reste du match est conservé');
    // Un état plus ancien que les données chargées est ignoré.
    expect(
        withLive(m, _patch(at: '2026-10-30T17:00:00+00:00')).elapsed, isNull);
    expect(withLive(m, null), same(m));
  });

  test('rythme de lecture : 30 s pendant un match, 2 min sinon', () {
    final now = DateTime.now();
    expect(pollInterval([_patch()], now), const Duration(seconds: 30));
    expect(pollInterval([_patch(status: 'finished', short: 'FT')], now),
        const Duration(minutes: 2));
    expect(pollInterval(const [], now), const Duration(minutes: 2));
  });

  test('changement de score ou de statut, pas seulement de minute', () {
    final before = {5988: _patch(elapsed: 60)};
    expect(outcomeChanges(before, {5988: _patch(elapsed: 61)}), isEmpty);
    expect(outcomeChanges(before, {5988: _patch(elapsed: 62, hg: 2)}), {5988});
    expect(
        outcomeChanges(before, {5988: _patch(status: 'finished', short: 'FT')}),
        {5988});
    expect(outcomeChanges(const {}, {5988: _patch()}), isEmpty,
        reason: 'premier chargement');
  });

  test('listes et fiche : minute à jour sans actualiser', () async {
    final day = DateTime(2099, 10, 30);
    final container = ProviderContainer(overrides: [
      matchesOfDayProvider.overrideWith(
          (ref, d) async => [lilleLens(status: 'live', hg: 0, ag: 0)]),
      matchProvider.overrideWith((ref, id) async => lilleLens(status: 'live')),
      liveUpdatesProvider.overrideWith((ref) => _Fixed({5988: _patch()})),
    ]);
    addTearDown(container.dispose);
    await container.read(matchesOfDayProvider(day).future);
    await container.read(matchProvider(5988).future);
    expect(container.read(liveMatchesOfDayProvider(day)).value!.single.elapsed,
        65);
    expect(container.read(liveMatchProvider(5988)).value!.homeGoals, 1);
  });
}
