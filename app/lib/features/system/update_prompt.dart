import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'system_providers.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Texte du dialogue de mise à jour.
String updateMessage(UpdateKind kind, AppVersionInfo latest) {
  final parts = <String>[
    if (kind == UpdateKind.required)
      trf('Cette version n’est plus prise en charge. Installez la version {0} pour continuer.',
          [latest.versionName]),
    if ((latest.releaseNotes ?? '').trim().isNotEmpty)
      latest.releaseNotes!.trim(),
  ];
  return parts.isEmpty
      ? tr('Une nouvelle version est disponible.')
      : parts.join('\n\n');
}

/// Vérifie une fois par lancement si une nouvelle version de l'APK est publiée
/// (table `app_versions`) et propose ou impose la mise à jour.
Future<void> checkForUpdate(BuildContext context, WidgetRef ref) async {
  try {
    final package = await ref.read(installedPackageProvider.future);
    final latest = await ref.read(latestAndroidVersionProvider.future);
    final kind = updateKindFor(
      installedBuild: int.tryParse(package.buildNumber) ?? 0,
      latest: latest,
    );
    if (kind == UpdateKind.none || latest == null || !context.mounted) return;
    final optional = kind == UpdateKind.optional;
    await showDialog<void>(
      context: context,
      barrierDismissible: optional,
      builder: (dialogContext) => PopScope(
        canPop: optional,
        child: AlertDialog(
          title: Text(optional
              ? trf('Nouvelle version {0}', [latest.versionName])
              : tr('Mise à jour obligatoire')),
          content: Text(updateMessage(kind, latest)),
          actions: [
            if (optional)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(tr('Plus tard')),
              ),
            FilledButton(
              onPressed: latest.downloadUrl == null
                  ? null
                  : () => launchUrl(
                        Uri.parse(latest.downloadUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
              child: Text(tr('Télécharger')),
            ),
          ],
        ),
      ),
    );
  } catch (_) {
    // La vérification ne doit jamais bloquer l'app (hors ligne, serveur indisponible).
  }
}
