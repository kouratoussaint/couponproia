import 'package:flutter/material.dart';

/// Conteneur des onglets : on passe d'un onglet à l'autre en balayant l'écran
/// vers la gauche ou la droite. Chaque onglet garde son état (défilement, saisie).
class SwipeBranchContainer extends StatefulWidget {
  const SwipeBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
    required this.onPageChanged,
  });

  final int currentIndex;
  final List<Widget> children;
  final ValueChanged<int> onPageChanged;

  @override
  State<SwipeBranchContainer> createState() => _SwipeBranchContainerState();
}

class _SwipeBranchContainerState extends State<SwipeBranchContainer> {
  late final PageController _controller =
      PageController(initialPage: widget.currentIndex);

  /// Vrai pendant un changement d'onglet déclenché par un toucher (barre ou menu) :
  /// les pages traversées pendant l'animation ne doivent pas changer l'onglet.
  bool _programmatic = false;

  @override
  void didUpdateWidget(covariant SwipeBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_controller.hasClients) return;
    final page = (_controller.page ?? widget.currentIndex.toDouble()).round();
    if (page != widget.currentIndex) _goTo(widget.currentIndex, from: page);
  }

  Future<void> _goTo(int index, {required int from}) async {
    _programmatic = true;
    if ((index - from).abs() == 1) {
      await _controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      _controller.jumpToPage(index);
    }
    _programmatic = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _controller,
      onPageChanged: (index) {
        if (!_programmatic && index != widget.currentIndex) {
          widget.onPageChanged(index);
        }
      },
      children: [for (final child in widget.children) _KeepAlive(child: child)],
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
