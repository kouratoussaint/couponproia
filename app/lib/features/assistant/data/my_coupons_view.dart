// Mes coupons : présentation (fonctions pures, testées unitairement).
import '../../matches/data/sports_format.dart';
import 'assistant_models.dart';

enum CouponOrigin { assistant, manual, optimized }

CouponOrigin originOf(UserCoupon c) {
  if (c.variantOf != null) return CouponOrigin.optimized;
  if (c.conversationId != null) return CouponOrigin.assistant;
  return CouponOrigin.manual;
}

String originLabel(CouponOrigin o) => switch (o) {
      CouponOrigin.assistant => 'Coupon de l’assistant',
      CouponOrigin.manual => 'Coupon manuel',
      CouponOrigin.optimized => 'Version optimisée',
    };

String selectionsLabel(int n) => '$n sélection${n > 1 ? 's' : ''}';

/// Anciens titres automatiques (« Mon coupon · 3 sélections · cote 3,66 »,
/// « Coupon 3 sélections · cote 4,10 ») : remplacés par l'origine.
final _legacyTitle =
    RegExp(r'^(Mon coupon|Coupon) .*· cote [0-9]+([,.][0-9]+)?$');

/// Titre affiché : votre nom s'il a été choisi, sinon l'origine et le nombre de sélections.
String displayTitle(UserCoupon c) => _legacyTitle.hasMatch(c.title.trim())
    ? '${originLabel(originOf(c))} · ${selectionsLabel(c.selections.length)}'
    : c.title;

/// Équipes du coupon, deux matchs au plus puis « +N matchs ».
String matchesLine(UserCoupon c, {int max = 2}) {
  final names = [
    for (final s in c.selections) '${s.match.home} – ${s.match.away}'
  ];
  if (names.length <= max) return names.join(' · ');
  final rest = names.length - max;
  return '${names.take(max).join(' · ')} · +$rest match${rest > 1 ? 's' : ''}';
}

/// « Créé le 01/11/2026 à 14:32 » puis, si décidé, « Payé le … » ou « Terminé le … ».
String myCouponDateLine(UserCoupon c) {
  final parts = ['Créé le ${dateTimeLabel(c.createdAt)}'];
  if (c.result != null && c.settledAt != null) {
    parts.add(
        '${c.result == 'won' ? 'Payé' : 'Terminé'} le ${dateTimeLabel(c.settledAt!)}');
  }
  return parts.join(' · ');
}

/// Bilan de vos coupons enregistrés, pertes comprises.
class MyCouponsSummary {
  const MyCouponsSummary(
      {required this.total,
      required this.inProgress,
      required this.won,
      required this.lost,
      required this.voided,
      required this.averageOdd});

  final int total;
  final int inProgress;
  final int won;
  final int lost;
  final int voided;

  /// Cote moyenne des coupons gagnés ou perdus (null s'il n'y en a pas).
  final double? averageOdd;

  int get decided => won + lost;

  /// Part des coupons gagnés parmi les gagnés et perdus (annulés exclus).
  double? get successRate => decided == 0 ? null : won / decided;
}

MyCouponsSummary summarize(List<UserCoupon> list) {
  final decided = list.where((c) => c.result == 'won' || c.result == 'lost');
  final odds = [for (final c in decided) c.totalOdd];
  return MyCouponsSummary(
    total: list.length,
    inProgress: list.where((c) => c.result == null).length,
    won: list.where((c) => c.result == 'won').length,
    lost: list.where((c) => c.result == 'lost').length,
    voided: list.where((c) => c.result == 'void').length,
    averageOdd:
        odds.isEmpty ? null : odds.reduce((a, b) => a + b) / odds.length,
  );
}

/// Coupons décidés groupés par jour de règlement (à défaut, de création), du plus récent.
List<(DateTime, List<UserCoupon>)> decidedByDay(List<UserCoupon> list) {
  final byDay = <DateTime, List<UserCoupon>>{};
  for (final c in list.where((c) => c.result != null)) {
    byDay.putIfAbsent(dateOnly(c.settledAt ?? c.createdAt), () => []).add(c);
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final d in days)
      (
        d,
        byDay[d]!
          ..sort((a, b) => (b.settledAt ?? b.createdAt)
              .compareTo(a.settledAt ?? a.createdAt))
      )
  ];
}
