import 'package:coupon_pro_ia/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/text_scale_controller.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../system/app_updater.dart';
import '../../system/system_providers.dart';
import '../../system/update_prompt.dart';
import '../../system/update_widgets.dart';
import '../../widget/home_widget_sync.dart';
import 'profile_screen.dart';

/// Profil → « Réglages de l'application » : une ligne par réglage, avec sa valeur actuelle.
/// Langue, Apparence et Mises à jour s'ouvrent dans un panneau.
class AppSettingsSection extends ConsumerWidget {
  const AppSettingsSection({super.key});

  String _language(WidgetRef ref) {
    SharedPreferences? prefs;
    try {
      prefs = ref.read(sharedPreferencesProvider);
    } catch (_) {}
    final code = prefs?.getString(languagePrefKey) ?? appLanguage;
    return appLanguages[code] ?? appLanguages['fr']!;
  }

  static String themeLabel(ThemeMode m) => switch (m) {
        ThemeMode.system => tr('Système'),
        ThemeMode.light => tr('Clair'),
        ThemeMode.dark => tr('Sombre'),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final textSize = ref.watch(textSizeProvider);
    final hasUpdater = ref.watch(nativeUpdaterProvider) != null;
    final update = ref.watch(updateControllerProvider);
    final auto = ref.watch(autoDownloadProvider);
    final version = ref.watch(installedPackageProvider).valueOrNull?.version;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: Text(tr('Notifications')),
            subtitle: Text(tr('Ce que je reçois, heures calmes')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.notificationSettings),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(tr('Langue')),
            subtitle: Text(_language(ref)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _sheet(
              context,
              title: tr('Langue'),
              child: const LanguageSelector(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(tr('Apparence')),
            subtitle: Text(trf('{0} · texte {1}',
                [themeLabel(themeMode), textSize.label.toLowerCase()])),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _sheet(context,
                title: tr('Apparence'), child: const AppearanceSettings()),
          ),
          if (hasUpdater)
            ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: Text(tr('Mises à jour')),
              subtitle: Text([
                if (version != null) trf('Version {0}', [version]),
                if (updateStatusText(update) case final s?) s,
                autoDownloadLabel(auto),
              ].join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _sheet(context,
                  title: null, child: const UpdateSettingsSlot()),
            ),
          ListTile(
            leading: const Icon(Icons.widgets_outlined),
            title: Text(tr('Widget sur l’écran d’accueil')),
            subtitle: Text(tr(
                'Coupon du jour, matchs du jour et en direct, sans ouvrir l’app')),
            onTap: () async {
              final ok = await requestHomeWidget();
              if (!ok && context.mounted) {
                showMessage(context,
                    tr('Ajout manuel : appui long sur l’écran d’accueil → Widgets → Coupon Pro IA.'));
              }
            },
          ),
          const ErrorReportsSwitch(
              contentPadding: EdgeInsets.symmetric(horizontal: 16),
              icon: Icon(Icons.bug_report_outlined)),
        ],
      ),
    );
  }
}

Future<void> _sheet(BuildContext context,
        {required String? title, required Widget child}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(title, style: Theme.of(c).textTheme.titleMedium),
                const SizedBox(height: 12),
              ],
              child,
            ],
          ),
        ),
      ),
    );

/// Thème et taille du texte (panneau « Apparence »).
class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final textSize = ref.watch(textSizeProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Thème'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(tr('Système')),
                  icon: const Icon(Icons.brightness_auto_outlined)),
              ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(tr('Clair')),
                  icon: const Icon(Icons.light_mode_outlined)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(tr('Sombre')),
                  icon: const Icon(Icons.dark_mode_outlined)),
            ],
            selected: {themeMode},
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).setMode(s.first),
          ),
        ),
        const SizedBox(height: 20),
        Text(tr('Taille du texte'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<TextSize>(
            showSelectedIcon: false,
            segments: [
              for (final t in TextSize.values)
                ButtonSegment(
                  value: t,
                  label: Text('A',
                      style: TextStyle(
                          fontSize: 14 * t.factor,
                          fontWeight: FontWeight.w700)),
                  tooltip: t.label,
                ),
            ],
            selected: {textSize},
            onSelectionChanged: (s) =>
                ref.read(textSizeProvider.notifier).set(s.first),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          trf('{0} : voici à quoi ressemble le texte de l’app.',
              [textSize.label]),
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}
