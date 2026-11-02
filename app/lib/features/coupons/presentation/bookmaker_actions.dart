import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/form_widgets.dart';
import '../../system/system_providers.dart';
import '../data/bookmaker_format.dart';
import '../data/coupon_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Lien bookmaker réglé par l'équipe, ou null (aucun bouton « Ouvrir … » dans ce cas).
final bookmakerLinkProvider = Provider<BookmakerLink?>((ref) =>
    BookmakerLink.fromSetting(
        ref.watch(publicSettingsProvider).valueOrNull?['bookmaker.link']));

/// Copie le coupon au format bookmaker, puis propose d'ouvrir le site réglé par l'équipe.
/// Aucun site de paris ne permet de pré-remplir un ticket depuis une autre application :
/// l'utilisateur colle ou recopie lui-même ses choix.
Future<void> copyForBookmaker(BuildContext context, WidgetRef ref, String title,
    double totalOdd, List<CouponSelection> selections) async {
  await Clipboard.setData(
      ClipboardData(text: bookmakerText(title, totalOdd, selections)));
  if (!context.mounted) return;
  final link = ref.read(bookmakerLinkProvider);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(tr(
          'Coupon copié au format bookmaker. Vérifiez chaque cote sur le site avant de valider.')),
      duration: const Duration(seconds: 6),
      action: link == null
          ? null
          : SnackBarAction(
              label: trf('Ouvrir {0}', [link.name]),
              onPressed: () => openBookmaker(context, link)),
    ));
}

Future<void> openBookmaker(BuildContext context, BookmakerLink link) async {
  final ok = await launchUrl(link.url, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showMessage(context, trf('Impossible d’ouvrir {0}.', [link.name]),
        error: true);
  }
}

/// Boutons « Copier pour mon bookmaker » et, si réglé, « Ouvrir {site} ».
class BookmakerButtons extends ConsumerWidget {
  const BookmakerButtons(
      {super.key,
      required this.title,
      required this.totalOdd,
      required this.selections});

  final String title;
  final double totalOdd;
  final List<CouponSelection> selections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selections.isEmpty) return const SizedBox.shrink();
    final link = ref.watch(bookmakerLinkProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.tonalIcon(
          onPressed: () =>
              copyForBookmaker(context, ref, title, totalOdd, selections),
          icon: const Icon(Icons.content_paste_go_outlined),
          label: Text(tr('Copier pour mon bookmaker')),
        ),
        if (link != null)
          OutlinedButton.icon(
            onPressed: () => openBookmaker(context, link),
            icon: const Icon(Icons.open_in_new),
            label: Text(trf('Ouvrir {0}', [link.name])),
          ),
      ],
    );
  }
}
