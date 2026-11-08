import 'package:flutter/material.dart';

import '../router/navigation.dart';

/// Retour dans un écran à sous-onglets (lot 27) : sur un autre sous-onglet que le
/// premier, le retour ramène d'abord au premier, puis suit l'historique habituel.
///
/// À placer sous le [DefaultTabController] de l'écran.
/// - Dans un onglet de la coque ([shellTab] = index de l'onglet), la coque gère le
///   bouton retour : l'écran s'y déclare.
/// - Dans un écran plein écran ([shellTab] nul), un [PopScope] suffit.
class SubTabBackScope extends StatefulWidget {
  const SubTabBackScope({super.key, this.shellTab, required this.child});

  final int? shellTab;
  final Widget child;

  @override
  State<SubTabBackScope> createState() => _SubTabBackScopeState();
}

class _SubTabBackScopeState extends State<SubTabBackScope> {
  TabController? _tabs;

  bool _back() {
    final tabs = _tabs;
    if (!mounted || tabs == null || tabs.index == 0) return false;
    tabs.animateTo(0);
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tabs = DefaultTabController.maybeOf(context);
    final tab = widget.shellTab;
    if (tab != null) SubTabBack.register(tab, _back);
  }

  @override
  void dispose() {
    final tab = widget.shellTab;
    if (tab != null) SubTabBack.unregister(tab, _back);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (widget.shellTab != null || tabs == null) return widget.child;
    return AnimatedBuilder(
      animation: tabs,
      child: widget.child,
      builder: (context, child) => PopScope(
        canPop: tabs.index == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: child!,
      ),
    );
  }
}
