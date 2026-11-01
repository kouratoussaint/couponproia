import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// Coupon suivi : alerte quand la cote d'une sélection bouge fortement avant le match.
final couponWatchedProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, couponId) async {
  final client = ref.watch(supabaseClientProvider);
  if (client.auth.currentUser == null) return false;
  final row = await client
      .from('coupon_watches')
      .select('coupon_id')
      .eq('coupon_id', couponId)
      .maybeSingle();
  return row != null;
});

Future<bool> setCouponWatch(WidgetRef ref, String couponId, bool on) async {
  final res = await ref
      .read(supabaseClientProvider)
      .rpc('set_coupon_watch', params: {'p_coupon': couponId, 'p_on': on});
  ref.invalidate(couponWatchedProvider(couponId));
  return res == true;
}

/// Seuil d'alerte (réglage public alerts.odds_move_percent), 10 % par défaut.
double oddsMoveThreshold(Map<String, dynamic>? settings) {
  final v = settings?['alerts.odds_move_percent'];
  return (v is num ? v.toDouble() : 10) / 100;
}

/// Variation relative de la cote totale (cotes actuelles / cotes publiées − 1), ou null.
double? totalOddsMove(Iterable<({double published, double? current})> legs) {
  if (!legs.any((l) => l.current != null && l.current != l.published)) {
    return null;
  }
  final ratio = legs.fold<double>(
      1, (p, l) => p * ((l.current ?? l.published) / l.published));
  return ratio - 1;
}
