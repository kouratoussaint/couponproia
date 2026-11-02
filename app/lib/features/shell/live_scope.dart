import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../assistant/data/assistant_repository.dart';
import '../coupons/data/coupon_repository.dart';
import '../journal/data/journal_repository.dart';
import '../matches/data/live_updates.dart';

/// Lecture en direct tant que l'app est au premier plan (pause en arrière-plan). Quand un
/// score ou un statut change, les coupons et le carnet sont relus (au plus toutes les 20 s).
class LiveUpdatesScope extends ConsumerStatefulWidget {
  const LiveUpdatesScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LiveUpdatesScope> createState() => _LiveUpdatesScopeState();
}

class _LiveUpdatesScopeState extends ConsumerState<LiveUpdatesScope> {
  late final AppLifecycleListener _lifecycle;
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(liveUpdatesProvider.notifier).start(),
      onPause: () => ref.read(liveUpdatesProvider.notifier).pause(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(liveUpdatesProvider.notifier).start();
    });
  }

  void _refreshDependents() {
    final now = DateTime.now();
    if (now.difference(_lastRefresh) < const Duration(seconds: 20)) return;
    _lastRefresh = now;
    ref.invalidate(activeCouponsProvider);
    ref.invalidate(publishedCouponsProvider);
    ref.invalidate(decidedCouponsProvider);
    ref.invalidate(couponProvider);
    ref.invalidate(savedCouponsProvider);
    ref.invalidate(userCouponProvider);
    ref.invalidate(journalProvider);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(liveUpdatesProvider, (before, after) {
      if (outcomeChanges(before, after).isNotEmpty) _refreshDependents();
    });
    return widget.child;
  }
}
