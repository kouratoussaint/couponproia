import 'package:flutter/material.dart';

import '../../core/i18n/tr.dart';
import '../../core/theme/solid_buttons.dart';

/// LOT 26 : éléments visibles de la mise à jour téléchargée par l'application.

/// Réglage du téléchargement automatique.
enum AutoDownload { wifi, always, never }

String autoDownloadLabel(AutoDownload a) => switch (a) {
      AutoDownload.wifi => tr('Wi-Fi'),
      AutoDownload.always => tr('Wi-Fi + mobile'),
      AutoDownload.never => tr('Jamais'),
    };

String _mb(double v) =>
    v.toStringAsFixed(v < 10 ? 1 : 0).replaceAll('.', decimalSeparator);

/// Barre de progression du téléchargement.
class UpdateProgress extends StatelessWidget {
  const UpdateProgress(
      {super.key, required this.received, required this.total});

  /// Mo reçus et taille totale.
  final double received;
  final double total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = total <= 0 ? 0.0 : (received / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: p, minHeight: 8),
        ),
        const SizedBox(height: 6),
        Text(
            trf('{0} sur {1} Mo · {2}',
                [_mb(received), _mb(total), percentLabel((p * 100).round())]),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Proposition d'une version facultative (remplace l'ancien dialogue « Télécharger »).
class UpdateOfferDialog extends StatelessWidget {
  const UpdateOfferDialog({
    super.key,
    required this.versionName,
    required this.sizeMb,
    this.notes,
    this.onLater,
    this.onUpdate,
    this.received,
  });

  final String versionName;
  final double sizeMb;
  final String? notes;
  final VoidCallback? onLater;
  final VoidCallback? onUpdate;

  /// Mo déjà reçus : null tant que le téléchargement n'a pas commencé.
  final double? received;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloading = received != null;
    return AlertDialog(
      icon: Icon(Icons.system_update, color: theme.colorScheme.primary),
      title: Text(trf('Nouvelle version {0}', [versionName])),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((notes ?? '').isNotEmpty) ...[
            Text(notes!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
          ],
          if (downloading)
            UpdateProgress(received: received!, total: sizeMb)
          else
            Text(
              trf('{0} Mo. Le téléchargement continue si vous quittez l’application ; vous serez prévenu quand la mise à jour sera prête.',
                  [_mb(sizeMb)]),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: onLater,
            child: Text(downloading
                ? tr('Continuer en arrière-plan')
                : tr('Plus tard'))),
        if (!downloading)
          FilledButton.icon(
            onPressed: onUpdate,
            icon: const Icon(Icons.download),
            label: Text(tr('Mettre à jour')),
          ),
      ],
    );
  }
}

/// Bandeau en haut de l'accueil quand la mise à jour est téléchargée et vérifiée.
class UpdateReadyBanner extends StatelessWidget {
  const UpdateReadyBanner(
      {super.key, required this.versionName, this.onInstall, this.onLater});

  final String versionName;
  final VoidCallback? onInstall;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trf('Mise à jour {0} prête', [versionName]),
                          style: theme.textTheme.titleSmall),
                      Text(
                          tr('Téléchargée et vérifiée. L’installation prend quelques secondes ; l’application se ferme, puis une notification permet de la rouvrir.'),
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onLater, child: Text(tr('Plus tard'))),
                const SizedBox(width: 4),
                FilledButton(
                  style: solidButtonStyle(context, SolidTone.green),
                  onPressed: onInstall,
                  child: Text(tr('Installer')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Première installation : Android demande d'autoriser Coupon Pro IA à installer.
class InstallPermissionSheet extends StatelessWidget {
  const InstallPermissionSheet({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                  radius: 12,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text('$n',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.primary))),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Une autorisation, une seule fois'),
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
                tr('Pour installer ses mises à jour, Coupon Pro IA doit être autorisée par Android à « installer des applis inconnues ». Ce réglage ne concerne que Coupon Pro IA et peut être retiré à tout moment.'),
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            step(1, tr('Touchez « Ouvrir le réglage ».')),
            step(2, tr('Activez « Autoriser cette source ».')),
            step(3, tr('Revenez : l’installation reprend toute seule.')),
            const SizedBox(height: 8),
            Text(tr('Les mises à jour suivantes pourront s’installer sans confirmation sur Android 12 et plus récent.'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
                label: Text(tr('Ouvrir le réglage')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mise à jour obligatoire : écran bloquant, téléchargement intégré.
class RequiredUpdateScreen extends StatelessWidget {
  const RequiredUpdateScreen(
      {super.key,
      required this.versionName,
      required this.sizeMb,
      this.received,
      this.onUpdate,
      this.onInstall,
      this.error});

  final String versionName;
  final double sizeMb;
  final double? received;
  final VoidCallback? onUpdate;

  /// Fichier prêt : bouton « Installer ».
  final VoidCallback? onInstall;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.system_update,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 20),
              Text(tr('Mise à jour obligatoire'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                  trf('Cette version n’est plus prise en charge. Installez la version {0} pour continuer.',
                      [versionName]),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 28),
              if (error != null) ...[
                Text(error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
                const SizedBox(height: 12),
              ],
              if (onInstall != null)
                FilledButton.icon(
                  onPressed: onInstall,
                  icon: const Icon(Icons.install_mobile),
                  label: Text(tr('Installer')),
                )
              else if (received != null)
                UpdateProgress(received: received!, total: sizeMb)
              else
                FilledButton.icon(
                  onPressed: onUpdate,
                  icon: const Icon(Icons.download),
                  label: Text(trf('Mettre à jour ({0} Mo)', [_mb(sizeMb)])),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Profil : groupe « Mises à jour ».
class UpdateSettingsCard extends StatelessWidget {
  const UpdateSettingsCard({
    super.key,
    required this.mode,
    required this.installedVersion,
    this.onModeChanged,
    this.onCheck,
    this.status,
  });

  final AutoDownload mode;
  final String installedVersion;
  final ValueChanged<AutoDownload>? onModeChanged;
  final VoidCallback? onCheck;

  /// Ex. « À jour » ou « Version 0.34.0 prête ».
  final String? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Mises à jour'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                trf('Version installée : {0}{1}',
                    [installedVersion, status == null ? '' : ' · $status']),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(tr('Téléchargement automatique'),
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<AutoDownload>(
              showSelectedIcon: false,
              segments: [
                for (final a in AutoDownload.values)
                  ButtonSegment(value: a, label: Text(autoDownloadLabel(a))),
              ],
              selected: {mode},
              onSelectionChanged: (s) => onModeChanged?.call(s.first),
            ),
            const SizedBox(height: 6),
            Text(tr('Les mises à jour obligatoires sont toujours proposées. Une mise à jour pèse environ 33 Mo.'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onCheck,
              icon: const Icon(Icons.refresh),
              label: Text(tr('Rechercher une mise à jour')),
            ),
          ],
        ),
      ),
    );
  }
}
