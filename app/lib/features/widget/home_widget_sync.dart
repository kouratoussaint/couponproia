// Widget Android de l'écran d'accueil (B5) : l'app prépare les textes et les confie au widget
// (home_widget). Mis à jour à l'ouverture, puis à chaque changement (coupon du jour, direct).
// Un toucher ouvre l'app sur le Coupon du jour (ou la liste des coupons).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/router/app_routes.dart';
import '../coupons/data/coupon_models.dart';
import '../coupons/data/coupon_phase.dart';
import '../coupons/data/coupon_repository.dart';
import '../matches/data/live_updates.dart';
import '../matches/data/sports_format.dart';
import '../matches/data/sports_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

const widgetProviderName = 'com.couponproia.coupon_pro_ia.CouponWidgetProvider';

/// Textes du widget (identiques à ce qui est enregistré pour Android).
@immutable
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.title,
    required this.odd,
    required this.line1,
    required this.line2,
    required this.route,
  });

  final String title;
  final String odd;
  final String line1;
  final String line2;
  final String route;

  @override
  bool operator ==(Object other) =>
      other is WidgetSnapshot &&
      other.title == title &&
      other.odd == odd &&
      other.line1 == line1 &&
      other.line2 == line2 &&
      other.route == route;

  @override
  int get hashCode => Object.hash(title, odd, line1, line2, route);
}

/// Coupon du jour à montrer : celui publié aujourd'hui (même décidé), sinon le plus récent
/// encore ouvert.
Coupon? widgetCoupon(List<Coupon> all, DateTime now) {
  final duJour = all
      .where((c) => c.category == 'du_jour' && !c.isWithdrawn)
      .toList()
    ..sort((a, b) =>
        (b.publishedAt ?? b.publishAt).compareTo(a.publishedAt ?? a.publishAt));
  final today = dateOnly(now);
  return duJour
          .where((c) => dateOnly(c.publishedAt ?? c.publishAt) == today)
          .firstOrNull ??
      duJour.where((c) => c.result == null).firstOrNull;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _time(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

WidgetSnapshot widgetSnapshot(
    Coupon? c, List<MatchSummary> today, DateTime now) {
  final live = today.where((m) => m.isLive).length;
  final n = today.length;
  final line2 = n == 0
      ? tr('Aucun match suivi aujourd’hui')
      : trf('{0} match{1} aujourd’hui{2}', [
          n,
          n > 1 ? 's' : '',
          live > 0 ? trf(' · {0} en direct', [live]) : ''
        ]);
  if (c == null) {
    return WidgetSnapshot(
      title: tr('Coupon du jour'),
      odd: '',
      line1: tr('Pas encore publié aujourd’hui : il arrive dans la matinée.'),
      line2: line2,
      route: AppRoutes.coupons,
    );
  }
  final odd = decimalLabel(
      c.result == 'won' && c.settledOdd != null ? c.settledOdd! : c.totalOdd);
  final first = kickoffLabel(c.firstKickoffAt, now);
  final String line1;
  final String title;
  switch (c.result) {
    case 'won':
      title = tr('Coupon du jour · Gagné');
      line1 = settledLine(c).isEmpty
          ? tr('Toutes les sélections validées')
          : settledLine(c);
    case 'lost':
      title = tr('Coupon du jour · Perdu');
      line1 = resultDetail(c).isEmpty ? tr('Coupon perdu') : resultDetail(c);
    case 'void':
      title = tr('Coupon du jour · Annulé');
      line1 = tr('Annulé (match reporté ou annulé)');
    default:
      title = tr('Coupon du jour');
      if (c.locked) {
        line1 = trf(
            'Réservé aux forfaits payants jusqu’à la fin des matchs · 1er match {0}',
            [first]);
      } else if (phaseOf(c, now) == CouponPhase.live) {
        final p = progressOf(c);
        line1 = trf('En cours : {0} sélection{1} validée{2} sur {3}',
            [p.won, p.won > 1 ? 's' : '', p.won > 1 ? 's' : '', p.total]);
      } else {
        final s = c.selections.length;
        line1 = trf('{0}1er match {1}', [
          s == 0 ? '' : trf('{0} sélection{1} · ', [s, s > 1 ? 's' : '']),
          first
        ]);
      }
  }
  return WidgetSnapshot(
    title: title,
    odd: odd,
    line1: line1,
    line2: line2,
    route: AppRoutes.couponDetailFor(c.id),
  );
}

/// « 18:00 » aujourd'hui, sinon « Demain 18:00 » / « sam. 08/11 18:00 ».
String kickoffLabel(DateTime t, DateTime now) =>
    dateOnly(t) == dateOnly(now) ? _time(t) : '${dayLabel(t, now)} ${_time(t)}';

String decimalLabel(double v) =>
    v.toStringAsFixed(2).replaceAll('.', decimalSeparator);

/// Textes du widget à partir des données de l'app (null tant que rien n'est chargé).
final widgetSnapshotProvider = Provider.autoDispose<WidgetSnapshot?>((ref) {
  final now = DateTime.now();
  final coupons = ref.watch(publishedCouponsProvider).valueOrNull;
  final matches =
      ref.watch(liveMatchesOfDayProvider(dateOnly(now))).valueOrNull;
  if (coupons == null && matches == null) return null;
  return widgetSnapshot(
      widgetCoupon(coupons ?? const [], now), matches ?? const [], now);
});

/// Enregistre les textes pour Android et redessine le widget (sans effet ailleurs).
Future<void> pushToHomeWidget(WidgetSnapshot s, DateTime now) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await Future.wait([
      HomeWidget.saveWidgetData<String>('title', s.title),
      HomeWidget.saveWidgetData<String>('odd', s.odd),
      HomeWidget.saveWidgetData<String>('line1', s.line1),
      HomeWidget.saveWidgetData<String>('line2', s.line2),
      HomeWidget.saveWidgetData<String>('route', s.route),
      HomeWidget.saveWidgetData<String>(
          'updated', trf('Mis à jour à {0}', [_time(now)])),
    ]);
    await HomeWidget.updateWidget(qualifiedAndroidName: widgetProviderName);
  } catch (_) {
    // Widget absent ou canal indisponible : sans conséquence pour l'app.
  }
}

/// Propose d'ajouter le widget à l'écran d'accueil (Android 8+, selon le lanceur).
/// Renvoie false si le téléphone ne le permet pas : l'ajout se fait alors à la main.
Future<bool> requestHomeWidget() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    if (await HomeWidget.isRequestPinWidgetSupported() != true) return false;
    await HomeWidget.requestPinWidget(qualifiedAndroidName: widgetProviderName);
    return true;
  } catch (_) {
    return false;
  }
}

/// Garde le widget à jour tant que l'app est ouverte.
class HomeWidgetSync extends ConsumerStatefulWidget {
  const HomeWidgetSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<HomeWidgetSync> createState() => _HomeWidgetSyncState();
}

class _HomeWidgetSyncState extends ConsumerState<HomeWidgetSync> {
  Timer? _debounce;

  void _schedule(WidgetSnapshot? s) {
    if (s == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2),
        () => unawaited(pushToHomeWidget(s, DateTime.now())));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? _schedule(ref.read(widgetSnapshotProvider)) : null);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(widgetSnapshotProvider, (before, after) {
      if (after != null && after != before) _schedule(after);
    });
    return widget.child;
  }
}
