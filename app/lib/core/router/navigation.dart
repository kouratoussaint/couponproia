import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'app_routes.dart';

/// Règle unique de navigation (lot 27) : tout écran ouvert depuis un autre s'empile et
/// le retour revient exactement à l'écran précédent.
///
/// - Adresse d'un onglet (Accueil, Matchs, Coupons, Assistant IA, Profil) : on change
///   d'onglet dans la coque. Si des écrans plein écran étaient ouverts (Aide, détail d'un
///   coupon…), ils sont mémorisés : le retour depuis l'onglet les rouvre.
/// - Toute autre adresse : l'écran s'empile au-dessus de l'écran actuel.

/// Chemins des cinq onglets, dans l'ordre de la barre du bas.
const tabPaths = [
  AppRoutes.home,
  AppRoutes.matches,
  AppRoutes.coupons,
  AppRoutes.assistant,
  AppRoutes.profile,
];

/// Index de l'onglet visé par [location], ou null pour un écran plein écran.
int? tabIndexOf(String location) {
  final i = tabPaths.indexOf(Uri.parse(location).path);
  return i < 0 ? null : i;
}

/// Anciennes adresses (notifications déjà envoyées, liens) → adresse actuelle.
/// Mes coupons et le Laboratoire n'existent plus qu'en onglets de l'Assistant IA ;
/// les mentions légales s'ouvrent en plein écran.
String normalizeLocation(String location) {
  final uri = Uri.parse(location);
  switch (uri.path) {
    case AppRoutes.oldLab:
      return AppRoutes.labFor(uri.queryParameters['coupon']);
    case AppRoutes.oldMyCoupons:
      return AppRoutes.assistantMyCoupons;
    case AppRoutes.oldCompetitions:
      return AppRoutes.matchesCompetitions;
    case AppRoutes.oldLegal:
      return AppRoutes.legal;
  }
  return location;
}

/// Écrans plein écran empilés au-dessus des onglets, du plus bas au plus haut.
List<String> pushedStack(GoRouter router) => [
      for (final m in router.routerDelegate.currentConfiguration.matches)
        if (m is ImperativeRouteMatch) m.matches.uri.toString(),
    ];

/// Ouvre [location] selon la règle unique (voir en tête de fichier).
void openLocation(GoRouter router, String location) {
  final target = normalizeLocation(location);
  if (tabIndexOf(target) != null) {
    TabBackHistory.pendingStack = pushedStack(router);
    router.go(target);
  } else {
    router.push(target);
  }
}

extension AppNavigation on BuildContext {
  /// Ouvre un écran ou un onglet ; le retour revient ici.
  void openRoute(String location) => openLocation(GoRouter.of(this), location);
}

/// Étape de retour : onglet à afficher, puis écrans plein écran à rouvrir par-dessus.
class BackEntry {
  const BackEntry(this.tab, [this.stack = const []]);

  final int tab;
  final List<String> stack;
}

/// Retour depuis un onglet : revient à l'onglet précédent (et aux écrans qui y étaient
/// ouverts), puis à l'Accueil ; sur l'Accueil, un premier appui prévient, un second
/// (dans les 2 s) quitte l'app.
class TabBackHistory {
  /// Écrans plein écran ouverts juste avant un changement d'onglet demandé par
  /// [openLocation] ; la coque les rattache à l'onglet quitté.
  static List<String>? pendingStack;

  final List<BackEntry> _visited = [];
  DateTime? _lastExitRequest;

  /// Changement d'onglet [from] → [to]. [stack] : écrans ouverts sur [from].
  void visited(int from, int to, {List<String> stack = const []}) {
    if (from == to && stack.isEmpty) return;
    _visited.removeWhere((e) => e.tab == to && e.stack.isEmpty);
    _visited.add(BackEntry(from, stack));
  }

  /// Où revenir, ou null si l'utilisateur est sur l'Accueil sans historique.
  BackEntry? backEntry(int current) {
    while (_visited.isNotEmpty) {
      final previous = _visited.removeLast();
      if (previous.tab != current || previous.stack.isNotEmpty) {
        return previous;
      }
    }
    return current == 0 ? null : const BackEntry(0);
  }

  /// Onglet où revenir (sans les écrans à rouvrir).
  int? back(int current) => backEntry(current)?.tab;

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

/// Retour dans les onglets qui ont des sous-onglets (Matchs, Assistant IA) : chaque
/// écran déclare, pour son onglet, une fonction qui ramène au premier sous-onglet et
/// renvoie true si elle a agi.
abstract final class SubTabBack {
  static final Map<int, bool Function()> _handlers = {};

  static void register(int tab, bool Function() handler) =>
      _handlers[tab] = handler;

  static void unregister(int tab, bool Function() handler) {
    if (identical(_handlers[tab], handler)) _handlers.remove(tab);
  }

  /// true si le retour a été consommé par un sous-onglet de [tab].
  static bool handle(int tab) => _handlers[tab]?.call() ?? false;
}
