import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/share_links.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../admin/data/admin_repository.dart';
import '../../analysis/data/analysis_format.dart';
import '../../system/system_providers.dart';
import '../data/coupon_models.dart';
import '../data/coupon_repository.dart';
import '../../simulator/presentation/sim_entries.dart';
import '../../simulator/presentation/stake_simulator_sheet.dart';
import 'bookmaker_actions.dart';

/// Texte d'un coupon pour le partage ou le presse-papiers (jamais pour un coupon réservé :
/// son contenu est masqué par le serveur).
String couponShareText(Coupon c, {String? link}) => [
      'Coupon Pro IA · ${categoryLabels[c.category] ?? c.category}',
      c.title,
      for (final s in c.selections)
        '• ${s.match.home} – ${s.match.away} : ${outcomeKeyLabel(s.key, s.match.home, s.match.away)} (cote ${decimal(s.odd)})',
      'Cote totale ${decimal(c.totalOdd)} · probabilité estimée ${pct(c.combinedProbability)}',
      if (link != null) 'Ouvrir dans l’app : $link',
      'Estimations, aucune certitude. Pariez de façon responsable.',
    ].join('\n');

/// Menu d'actions d'un coupon (appui long). Les actions d'équipe n'apparaissent qu'avec la
/// permission correspondante ; le serveur vérifie de toute façon.
Future<void> showCouponActions(
    BuildContext context, WidgetRef ref, Coupon c) async {
  final perms = ref.read(myPermissionsProvider).valueOrNull ?? const <String>{};
  final readable = !c.locked && c.selections.isNotEmpty;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(c.title,
                style: Theme.of(sheet).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Ouvrir le coupon'),
            onTap: () => Navigator.pop(sheet, 'open'),
          ),
          if (readable) ...[
            if (!c.isWithdrawn)
              ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: const Text('Simuler une mise'),
                onTap: () => Navigator.pop(sheet, 'simulate'),
              ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Partager en texte'),
              onTap: () => Navigator.pop(sheet, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copier les sélections'),
              onTap: () => Navigator.pop(sheet, 'copy'),
            ),
            if (!c.isWithdrawn)
              ListTile(
                leading: const Icon(Icons.content_paste_go_outlined),
                title: const Text('Copier pour mon bookmaker'),
                subtitle: const Text('Codes 1 / X / 2, 1X, Plus de 2,5…'),
                onTap: () => Navigator.pop(sheet, 'bookmaker'),
              ),
            if (!c.isWithdrawn)
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Créer un visuel'),
                onTap: () => Navigator.pop(sheet, 'studio'),
              ),
          ],
          if (c.status == 'published' && perms.contains('generation.manage'))
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Retirer ce coupon'),
              subtitle: const Text('Équipe · motif affiché aux utilisateurs'),
              onTap: () => Navigator.pop(sheet, 'withdraw'),
            ),
          if (c.isWithdrawn && perms.contains('coupons.publish'))
            ListTile(
              leading: Icon(Icons.delete_forever_outlined,
                  color: Theme.of(sheet).colorScheme.error),
              title: Text('Supprimer définitivement',
                  style: TextStyle(color: Theme.of(sheet).colorScheme.error)),
              subtitle: const Text('Équipe · coupon retiré uniquement'),
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'open':
      await context.push(AppRoutes.couponDetailFor(c.id));
    case 'share':
      await SharePlus.instance.share(ShareParams(
          text: couponShareText(c, link: shareLink(ref, couponId: c.id))));
    case 'copy':
      await Clipboard.setData(ClipboardData(
          text: couponShareText(c, link: shareLink(ref, couponId: c.id))));
      if (context.mounted) showMessage(context, 'Sélections copiées.');
    case 'simulate':
      await showStakeSimulator(context, [couponSim(c)]);
    case 'bookmaker':
      await copyForBookmaker(context, ref, c.title, c.totalOdd, c.selections);
    case 'studio':
      await context.push(AppRoutes.studioFor('platform', c.id));
    case 'withdraw':
      await withdrawCoupon(context, ref, c);
    case 'delete':
      await deleteWithdrawnCoupons(context, ref, [c]);
  }
}

/// Retrait d'un coupon publié (équipe), avec motif affiché aux utilisateurs.
Future<void> withdrawCoupon(
    BuildContext context, WidgetRef ref, Coupon coupon) async {
  final controller = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Retirer le coupon'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
            labelText: 'Motif (affiché aux utilisateurs)'),
        maxLines: 2,
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Retirer')),
      ],
    ),
  );
  controller.dispose();
  if (reason == null || reason.isEmpty) return;
  try {
    await ref.read(couponRepositoryProvider).withdraw(coupon.id, reason);
    ref.invalidate(couponProvider(coupon.id));
    invalidateCouponLists(ref);
    if (context.mounted) showMessage(context, 'Coupon retiré.');
  } catch (e) {
    if (context.mounted) {
      showMessage(context, adminErrorMessage(e), error: true);
    }
  }
}

/// Suppression définitive de coupons retirés (équipe). Le contenu reste au journal d'audit.
Future<bool> deleteWithdrawnCoupons(
    BuildContext context, WidgetRef ref, List<Coupon> coupons) async {
  final targets = coupons.where((c) => c.isWithdrawn).toList();
  if (targets.isEmpty) return false;
  final controller =
      TextEditingController(text: 'Nettoyage des coupons retirés');
  final n = targets.length;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(n == 1
          ? 'Supprimer ce coupon retiré ?'
          : 'Supprimer $n coupons retirés ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              '${n == 1 ? 'Il disparaîtra' : 'Ils disparaîtront'} de l’application pour tout le monde. '
              'Cette action est définitive ; une copie du contenu est conservée au journal d’audit.'),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Motif (journalisé)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  final reason = controller.text.trim();
  controller.dispose();
  if (ok != true || !context.mounted) return false;
  if (reason.isEmpty) {
    showMessage(context, 'Le motif est obligatoire.', error: true);
    return false;
  }
  try {
    final deleted = await ref
        .read(couponRepositoryProvider)
        .deleteWithdrawn([for (final c in targets) c.id], reason);
    invalidateCouponLists(ref);
    if (context.mounted) {
      showMessage(context,
          deleted == 1 ? 'Coupon supprimé.' : '$deleted coupons supprimés.');
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      showMessage(context, adminErrorMessage(e), error: true);
    }
    return false;
  }
}
