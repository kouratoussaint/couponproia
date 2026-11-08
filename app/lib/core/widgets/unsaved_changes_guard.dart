import 'package:flutter/material.dart';

import '../i18n/tr.dart';

/// Retour depuis un formulaire (lot 27) : si quelque chose a été modifié et pas
/// enregistré, demande « Quitter sans enregistrer ? ». Sinon, le retour est immédiat.
///
/// Les enregistrements qui ferment l'écran (`context.pop()`, `Navigator.pop`) ne
/// passent pas par cette question.
class UnsavedChangesGuard extends StatelessWidget {
  const UnsavedChangesGuard(
      {super.key, required this.isDirty, required this.child});

  /// true si la saisie diffère de ce qui est enregistré.
  final bool Function() isDirty;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final navigator = Navigator.of(context);
          if (!isDirty() || await confirmLeaveWithoutSaving(context)) {
            navigator.pop();
          }
        },
        child: child,
      );
}

/// Boîte « Quitter sans enregistrer ? » : true si l'utilisateur choisit de quitter.
Future<bool> confirmLeaveWithoutSaving(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Quitter sans enregistrer ?')),
        content: Text(tr('Vos modifications seront perdues.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('Quitter'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('Continuer la saisie'))),
        ],
      ),
    ) ??
    false;
