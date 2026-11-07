import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/form_widgets.dart';
import 'app_updater.dart';
import 'system_providers.dart';
import 'update_widgets.dart';
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

/// Dernière version proposée pendant cette session (pas de nouvelle proposition au
/// retour dans l'app pour la même version, sauf si elle est obligatoire).
int? _lastPromptedBuild;
bool _requiredScreenOpen = false;

/// Vérifie si une nouvelle version est publiée et la propose (LOT 26) : téléchargement
/// en arrière-plan selon le réglage, bandeau « prête » sur l'accueil, écran bloquant si
/// la version installée n'est plus prise en charge. Sans empreinte publiée ou hors
/// Android, l'ancien dialogue ouvre le lien dans le navigateur.
Future<void> checkForUpdate(BuildContext context, WidgetRef ref,
    {bool refresh = false, bool userInitiated = false}) async {
  try {
    final s = await ref
        .read(updateControllerProvider.notifier)
        .check(userInitiated: userInitiated);
    final latest = s.latest;
    if (!context.mounted || latest == null) {
      if (userInitiated && context.mounted && s.phase == UpdatePhase.idle) {
        showMessage(context, tr('Vous avez la dernière version.'));
      }
      return;
    }
    if (s.required) {
      if (s.phase == UpdatePhase.browser) {
        await _browserDialog(context, UpdateKind.required, latest);
      } else if (!_requiredScreenOpen) {
        _requiredScreenOpen = true;
        await Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => const RequiredUpdatePage()));
        _requiredScreenOpen = false;
      }
      return;
    }
    final already = _lastPromptedBuild == latest.buildNumber && !userInitiated;
    if (s.phase == UpdatePhase.browser && !already) {
      _lastPromptedBuild = latest.buildNumber;
      await _browserDialog(context, UpdateKind.optional, latest);
    } else if (s.phase == UpdatePhase.offer && !already) {
      _lastPromptedBuild = latest.buildNumber;
      await showDialog<void>(
          context: context, builder: (_) => const UpdateOfferHost());
    } else if (userInitiated &&
        (s.phase == UpdatePhase.downloading || s.phase == UpdatePhase.ready)) {
      showMessage(
          context,
          s.phase == UpdatePhase.ready
              ? trf('Mise à jour {0} prête', [latest.versionName])
              : trf('Téléchargement de la mise à jour {0}',
                  [latest.versionName]));
    }
  } catch (_) {
    // La vérification ne doit jamais bloquer l'app (hors ligne, serveur indisponible).
  }
}

/// Ancien parcours : lien de téléchargement ouvert dans le navigateur.
Future<void> _browserDialog(
    BuildContext context, UpdateKind kind, AppVersionInfo latest) {
  final optional = kind == UpdateKind.optional;
  return showDialog<void>(
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
}

/// Installation, avec l'autorisation Android demandée la première fois.
Future<void> startInstall(BuildContext context, WidgetRef ref) async {
  final ctrl = ref.read(updateControllerProvider.notifier);
  if (await ctrl.needsPermission()) {
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => InstallPermissionSheet(onOpenSettings: () {
        Navigator.of(sheet).pop();
        ctrl.openPermissionSettings();
      }),
    );
    return;
  }
  final r = await ctrl.install();
  if (!context.mounted || r == 'installing') return;
  showMessage(
      context,
      r == 'corrupt'
          ? tr(
              'Le fichier reçu n’est pas conforme : il a été supprimé. Relancez la mise à jour.')
          : tr('L’installation n’a pas abouti. Réessayez dans un instant.'),
      error: true);
}

/// Dialogue de proposition : avant puis pendant le téléchargement.
class UpdateOfferHost extends ConsumerWidget {
  const UpdateOfferHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updateControllerProvider);
    final latest = s.latest;
    if (latest == null) return const SizedBox.shrink();
    if (s.phase == UpdatePhase.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
    }
    final downloading = s.phase == UpdatePhase.downloading;
    return UpdateOfferDialog(
      versionName: latest.versionName,
      sizeMb: s.totalMb,
      notes: latest.releaseNotes,
      received: downloading ? s.receivedMb : null,
      onLater: () => Navigator.of(context).pop(),
      onUpdate: () =>
          ref.read(updateControllerProvider.notifier).download(latest),
    );
  }
}

/// Écran bloquant d'une mise à jour obligatoire.
class RequiredUpdatePage extends ConsumerWidget {
  const RequiredUpdatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updateControllerProvider);
    final latest = s.latest;
    final ctrl = ref.read(updateControllerProvider.notifier);
    return PopScope(
      canPop: false,
      child: latest == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : RequiredUpdateScreen(
              versionName: latest.versionName,
              sizeMb: s.totalMb,
              received: s.phase == UpdatePhase.downloading ||
                      s.phase == UpdatePhase.installing
                  ? s.receivedMb
                  : null,
              error: s.phase == UpdatePhase.failed
                  ? tr('Le téléchargement n’a pas abouti. Réessayez.')
                  : null,
              onUpdate: () => ctrl.download(latest),
              onInstall: s.phase == UpdatePhase.ready
                  ? () => startInstall(context, ref)
                  : null,
            ),
    );
  }
}

/// Accueil : bandeau « Mise à jour prête ».
class UpdateReadyBannerSlot extends ConsumerWidget {
  const UpdateReadyBannerSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updateControllerProvider);
    if (s.phase != UpdatePhase.ready || s.latest == null || s.required) {
      return const SizedBox.shrink();
    }
    return UpdateReadyBanner(
      versionName: s.latest!.versionName,
      onInstall: () => startInstall(context, ref),
      onLater: () => ref.read(updateControllerProvider.notifier).postpone(),
    );
  }
}

/// Profil : groupe « Mises à jour » (Android seulement).
class UpdateSettingsSlot extends ConsumerWidget {
  const UpdateSettingsSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(nativeUpdaterProvider) == null) {
      return const SizedBox.shrink();
    }
    final s = ref.watch(updateControllerProvider);
    final mode = ref.watch(autoDownloadProvider);
    final version = ref.watch(installedPackageProvider).valueOrNull?.version;
    final status = switch (s.phase) {
      UpdatePhase.downloading => s.waitingForWifi
          ? trf('version {0} en attente du Wi-Fi', [s.latest?.versionName])
          : trf('téléchargement de la version {0}', [s.latest?.versionName]),
      UpdatePhase.ready ||
      UpdatePhase.installing =>
        trf('version {0} prête', [s.latest?.versionName]),
      UpdatePhase.offer ||
      UpdatePhase.browser ||
      UpdatePhase.failed =>
        trf('version {0} disponible', [s.latest?.versionName]),
      UpdatePhase.idle => s.latest == null ? tr('à jour') : null,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: UpdateSettingsCard(
        mode: mode,
        installedVersion: version ?? '–',
        status: status,
        onModeChanged: (m) => ref.read(autoDownloadProvider.notifier).set(m),
        onCheck: () => checkForUpdate(context, ref, userInitiated: true),
      ),
    );
  }
}
