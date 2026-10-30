import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_mode_controller.dart';
import '../system/maintenance_screen.dart';
import '../system/system_providers.dart';
import '../system/update_prompt.dart';
import 'app_drawer.dart';

/// Coque de l'app : menu latéral, barre à cinq onglets (Accueil, Matchs, Coupons,
/// Assistant IA, Profil) et balayage gauche / droite entre les onglets.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(themeModeProvider.notifier).pullRemote();
      checkForUpdate(context, ref);
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
    final flags = ref.watch(featureFlagsProvider).valueOrNull ?? const <String, bool>{};
    final permissions = ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if ((flags['maintenance_mode'] ?? false) && !permissions.contains('admin.access')) {
      return MaintenanceScreen(onRetry: () => ref.invalidate(featureFlagsProvider));
    }

    return Scaffold(
      key: shellScaffoldKey,
      drawer: AppDrawer(
        currentIndex: widget.navigationShell.currentIndex,
        onSelectTab: _selectTab,
      ),
      drawerEdgeDragWidth: 24,
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_soccer_outlined),
            selectedIcon: Icon(Icons.sports_soccer),
            label: 'Matchs',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Coupons',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: 'Assistant IA',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
