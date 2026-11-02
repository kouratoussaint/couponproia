import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_mode_controller.dart';
import '../auth/data/auth_repository.dart';
import '../legal/legal_repository.dart';
import '../legal/legal_screens.dart';
import '../notifications/data/push_service.dart';
import '../system/maintenance_screen.dart';
import '../system/system_providers.dart';
import '../system/update_prompt.dart';
import 'app_drawer.dart';
import 'live_scope.dart';
import '../widget/home_widget_sync.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Coque de l'app : menu latéral, barre à cinq onglets (Accueil, Matchs, Coupons,
/// Assistant IA, Profil) et balayage gauche / droite entre les onglets.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

/// Retour depuis un onglet : revient à l'onglet précédent, puis à l'Accueil ;
/// sur l'Accueil, un premier appui prévient, un second (dans les 2 s) quitte l'app.
class TabBackHistory {
  final List<int> _visited = [];
  DateTime? _lastExitRequest;

  void visited(int from, int to) {
    if (from == to) return;
    _visited
      ..remove(to)
      ..add(from);
  }

  /// Onglet où revenir, ou null si l'utilisateur est sur l'Accueil sans historique.
  int? back(int current) {
    while (_visited.isNotEmpty) {
      final previous = _visited.removeLast();
      if (previous != current) return previous;
    }
    return current == 0 ? null : 0;
  }

  /// true si ce second appui doit quitter l'app.
  bool confirmExit(DateTime now) {
    final last = _lastExitRequest;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      _lastExitRequest = null;
      return true;
    }
    _lastExitRequest = now;
    return false;
  }
}

class _HomeShellState extends ConsumerState<HomeShell> {
  final _history = TabBackHistory();
  bool _goingBack = false;

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final from = oldWidget.navigationShell.currentIndex;
    final to = widget.navigationShell.currentIndex;
    if (!_goingBack) _history.visited(from, to);
    _goingBack = false;
  }

  void _onBack() {
    final scaffold = shellScaffoldKey.currentState;
    if (scaffold?.isDrawerOpen ?? false) {
      scaffold!.closeDrawer();
      return;
    }
    final target = _history.back(widget.navigationShell.currentIndex);
    if (target != null) {
      _goingBack = true;
      widget.navigationShell.goBranch(target);
      return;
    }
    if (_history.confirmExit(DateTime.now())) {
      SystemNavigator.pop();
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(tr('Appuyez encore sur Retour pour quitter')),
        duration: Duration(seconds: 2),
      ));
  }

  /// Notifications sur le téléphone (si le projet Firebase est configuré).
  Future<void> _startPush() async {
    final version = ref.read(installedPackageProvider).valueOrNull?.version;
    await ref.read(pushServiceProvider).start(
          appVersion: version,
          onOpen: (route) {
            if (mounted) context.push(route);
          },
          onForeground: (title, route) {
            if (!mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text(title),
                action: route == null
                    ? null
                    : SnackBarAction(
                        label: tr('Voir'),
                        onPressed: () => context.push(route)),
              ));
          },
        );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(themeModeProvider.notifier).pullRemote();
      checkForUpdate(context, ref);
      _startPush();
    });
  }

  void _selectTab(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final flags =
        ref.watch(featureFlagsProvider).valueOrNull ?? const <String, bool>{};
    final permissions =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if ((flags['maintenance_mode'] ?? false) &&
        !permissions.contains('admin.access')) {
      return MaintenanceScreen(
          onRetry: () => ref.invalidate(featureFlagsProvider));
    }

    // CGU et politique de confidentialité en vigueur à accepter (première connexion ou mise à jour).
    // Hors ligne ou en erreur, l'app reste utilisable : la demande reviendra plus tard.
    final pendingLegal =
        ref.watch(legalStatusProvider).valueOrNull ?? const <PendingDocument>[];
    if (pendingLegal.isNotEmpty) {
      return LegalAcceptanceScreen(
        pending: pendingLegal,
        onSignOut: () async {
          await ref.read(pushServiceProvider).stop();
          await ref.read(authRepositoryProvider).signOut();
        },
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return LiveUpdatesScope(
        child: HomeWidgetSync(
            child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        key: shellScaffoldKey,
        drawer: AppDrawer(
          currentIndex: widget.navigationShell.currentIndex,
          onSelectTab: _selectTab,
        ),
        drawerEdgeDragWidth: 24,
        body: widget.navigationShell,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outline)),
          ),
          child: NavigationBar(
            selectedIndex: widget.navigationShell.currentIndex,
            onDestinationSelected: _selectTab,
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: tr('Accueil'),
              ),
              NavigationDestination(
                icon: Icon(Icons.sports_soccer_outlined),
                selectedIcon: Icon(Icons.sports_soccer),
                label: tr('Matchs'),
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: tr('Coupons'),
              ),
              NavigationDestination(
                icon: Icon(Icons.smart_toy_outlined),
                selectedIcon: Icon(Icons.smart_toy),
                label: tr('Assistant IA'),
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: tr('Profil'),
              ),
            ],
          ),
        ),
      ),
    )));
  }
}
