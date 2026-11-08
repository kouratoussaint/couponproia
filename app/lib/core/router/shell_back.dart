import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../i18n/tr.dart';
import 'navigation.dart';

/// Bouton retour dans les onglets (lot 27), dans cet ordre :
/// 1. menu latéral ouvert : il se ferme ;
/// 2. sous-onglet autre que le premier (Matchs, Assistant IA) : retour au premier ;
/// 3. onglet précédent, et les écrans plein écran qui y étaient ouverts ;
/// 4. sur l'Accueil sans historique : « Appuyez encore sur Retour pour quitter ».
class ShellBackScope extends StatefulWidget {
  const ShellBackScope({
    super.key,
    required this.navigationShell,
    required this.child,
    this.scaffoldKey,
    this.onExit,
  });

  final StatefulNavigationShell navigationShell;
  final GlobalKey<ScaffoldState>? scaffoldKey;
  final Widget child;

  /// Sortie de l'app (par défaut : fermeture par Android). Remplacé dans les tests.
  final VoidCallback? onExit;

  @override
  State<ShellBackScope> createState() => _ShellBackScopeState();
}

class _ShellBackScopeState extends State<ShellBackScope> {
  final _history = TabBackHistory();
  bool _goingBack = false;

  @override
  void didUpdateWidget(covariant ShellBackScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    final from = oldWidget.navigationShell.currentIndex;
    final to = widget.navigationShell.currentIndex;
    // Écrans plein écran fermés par un changement d'onglet (openRoute) : rattachés à
    // l'onglet quitté, pour que le retour les rouvre.
    final stack = TabBackHistory.pendingStack ?? const <String>[];
    TabBackHistory.pendingStack = null;
    if (!_goingBack) _history.visited(from, to, stack: stack);
    _goingBack = false;
  }

  void _onBack() {
    final scaffold = widget.scaffoldKey?.currentState;
    if (scaffold?.isDrawerOpen ?? false) {
      scaffold!.closeDrawer();
      return;
    }
    final shell = widget.navigationShell;
    final current = shell.currentIndex;
    if (SubTabBack.handle(current)) return;
    final target = _history.backEntry(current);
    if (target != null) {
      if (target.tab != current) {
        _goingBack = true;
        shell.goBranch(target.tab);
      }
      if (target.stack.isNotEmpty) {
        final router = GoRouter.of(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final location in target.stack) {
            router.push(location);
          }
        });
      }
      return;
    }
    if (_history.confirmExit(DateTime.now())) {
      (widget.onExit ?? SystemNavigator.pop)();
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(tr('Appuyez encore sur Retour pour quitter')),
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBack();
        },
        child: widget.child,
      );
}
