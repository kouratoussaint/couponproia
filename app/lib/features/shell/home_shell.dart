import '../system/app_updater.dart';
import 'package:coupon_pro_ia/features/auth/data/sign_out.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_mode_controller.dart';
import '../legal/legal_repository.dart';
import '../legal/legal_screens.dart';
import '../notifications/data/push_service.dart';
import '../system/maintenance_screen.dart';
import '../system/system_providers.dart';
import '../system/update_prompt.dart';
import '../../core/router/navigation.dart';
import '../../core/router/shell_back.dart';
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

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  DateTime _lastUpdateCheck = DateTime.now();

  /// Retour dans l'app : nouvelle vérification de version, au plus toutes les 15 minutes
  /// (une app restée ouverte en arrière-plan voit ainsi une version publiée entre-temps).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    // Retour du réglage « installer des applis inconnues » : l'installation reprend.
    ref.read(updateControllerProvider.notifier).resumeAfterPermission();
    // Téléchargement terminé pendant l'absence : bandeau à jour tout de suite.
    ref.read(updateControllerProvider.notifier).refresh();
    final now = DateTime.now();
    if (now.difference(_lastUpdateCheck) < const Duration(minutes: 15)) return;
    _lastUpdateCheck = now;
    checkForUpdate(context, ref, refresh: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Notifications sur le téléphone (si le projet Firebase est configuré).
  Future<void> _startPush() async {
    final version = ref.read(installedPackageProvider).valueOrNull?.version;
    await ref.read(pushServiceProvider).start(
          appVersion: version,
          onOpen: (route) {
            if (mounted) context.openRoute(route);
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
                        onPressed: () => context.openRoute(route)),
              ));
          },
        );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
          await signOutEverywhere(ref);
        },
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return LiveUpdatesScope(
        child: HomeWidgetSync(
            child: ShellBackScope(
      navigationShell: widget.navigationShell,
      scaffoldKey: shellScaffoldKey,
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
