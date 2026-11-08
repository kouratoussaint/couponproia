import '../../system/update_prompt.dart';
import 'package:coupon_pro_ia/features/auth/data/sign_out.dart';
import '../data/language_sync.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/monitoring/error_reporter.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/solid_buttons.dart';
import '../../../core/theme/text_scale_controller.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../billing/billing_repository.dart';
import '../../onboarding/data/preferences_repository.dart';
import '../../onboarding/presentation/onboarding_sheet.dart';
import 'responsible_gaming_screen.dart';
import '../../assistant/data/assistant_repository.dart';
import '../../system/system_providers.dart';
import '../data/profile_repository.dart';
import '../../shell/app_drawer.dart';
import '../../widget/home_widget_sync.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(myProfileProvider);
    final user = ref.watch(currentUserProvider);
    final permissions =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    final themeMode = ref.watch(themeModeProvider);
    final version = ref.watch(installedPackageProvider).valueOrNull;

    return Scaffold(
      appBar:
          AppBar(leading: const DrawerMenuButton(), title: Text(tr('Profil'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myProfileProvider);
          ref.invalidate(myPermissionsProvider);
          await ref.read(myProfileProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: profile.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(userMessageFor(e)),
                  data: (p) => Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        foregroundImage: p?.avatarUrl == null
                            ? null
                            : NetworkImage(p!.avatarUrl!),
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.15),
                        child: Text(
                          p?.initials ?? '?',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p?.displayName ?? '—',
                                style: theme.textTheme.titleLarge),
                            const SizedBox(height: 4),
                            Text(
                              user?.email ?? '',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Modifier le profil'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: p == null
                            ? null
                            : () => context.push(AppRoutes.profileEdit),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _GroupTitle(tr('Mon jeu')),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(tr('Mon carnet de paris')),
                    subtitle: Text(tr('Vos mises notées et votre bilan réel')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.journal),
                  ),
                  ListTile(
                    leading: const Icon(Icons.star_outline),
                    title: Text(tr('Équipes suivies')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.favoriteTeams),
                  ),
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: Text(tr('Mes préférences')),
                    subtitle: Text(() {
                      final p = ref.watch(myPreferencesProvider).valueOrNull;
                      final n = p?.favoriteCompetitions.length ?? 0;
                      return [
                        n == 0
                            ? tr('Aucune compétition suivie')
                            : trf('{0} compétition{1} suivie{2}',
                                [n, n > 1 ? 's' : '', n > 1 ? 's' : '']),
                        if (p?.level != null)
                          trf('niveau {0}', [p!.level!.label.toLowerCase()]),
                      ].join(' · ');
                    }()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showOnboarding(context, fromProfile: true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.health_and_safety_outlined),
                    title: Text(tr('Jeu responsable')),
                    subtitle:
                        Text(tr('Budget mensuel, plafond par pari, conseils')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.responsibleGaming),
                  ),
                ],
              ),
            ),
            _GroupTitle(tr('Mon compte')),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: Text(tr('Abonnement')),
                    subtitle: Text(
                      ref.watch(entitlementsProvider).when(
                            data: (e) => e.periodEnd == null
                                ? trf('Forfait {0}',
                                    [e.plan.replaceAll('_', ' ')])
                                : trf('Forfait {0} · jusqu’au {1}/{2}/{3}', [
                                    e.plan.replaceAll('_', ' '),
                                    e.periodEnd!.day.toString().padLeft(2, '0'),
                                    e.periodEnd!.month
                                        .toString()
                                        .padLeft(2, '0'),
                                    e.periodEnd!.year
                                  ]),
                            loading: () => '…',
                            error: (_, __) => tr('Forfait indisponible'),
                          ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.billing),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bolt),
                    title: Text(tr('Crédits IA')),
                    subtitle: Text(
                      ref.watch(myCreditsProvider).when(
                            data: (c) => c.unlimited
                                ? tr('Illimités (compte équipe)')
                                : trf(
                                    '{0} disponible(s) · {1} du forfait ce mois-ci + {2} supplémentaire(s)',
                                    [c.total, c.planCredits, c.extraCredits]),
                            loading: () => '…',
                            error: (_, __) => tr('Solde indisponible'),
                          ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_none),
                    title: Text(tr('Notifications')),
                    subtitle: Text(tr('Ce que je reçois, heures calmes')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.notificationSettings),
                  ),
                  if (permissions.contains('admin.access'))
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: Text(tr('Console d’administration')),
                      subtitle: Text(
                          tr('Utilisateurs, coupons, paiements, réglages')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(AppRoutes.adminConsole),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Apparence'), style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Text(tr('Langue'), style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    const LanguageSelector(),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text(tr('Système')),
                            icon: Icon(Icons.brightness_auto_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text(tr('Clair')),
                            icon: Icon(Icons.light_mode_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text(tr('Sombre')),
                            icon: Icon(Icons.dark_mode_outlined),
                          ),
                        ],
                        selected: {themeMode},
                        onSelectionChanged: (s) => ref
                            .read(themeModeProvider.notifier)
                            .setMode(s.first),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(tr('Taille du texte'),
                        style: theme.textTheme.titleSmall),
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
                        selected: {ref.watch(textSizeProvider)},
                        onSelectionChanged: (s) =>
                            ref.read(textSizeProvider.notifier).set(s.first),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      trf('{0} : voici à quoi ressemble le texte de l’app.',
                          [ref.watch(textSizeProvider).label]),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    const ErrorReportsSwitch(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
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
                  ],
                ),
              ),
            ),
            _GroupTitle(tr('Communauté')),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: Text(tr('Mon profil Tipster')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.myTipsterProfile),
                  ),
                  ListTile(
                    leading: const Icon(Icons.block),
                    title: Text(tr('Utilisateurs bloqués')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.blockedUsers),
                  ),
                ],
              ),
            ),
            const UpdateSettingsSlot(),
            _GroupTitle(tr('Aide')),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: Text(tr('Aide et questions fréquentes')),
                    subtitle: Text(
                        tr('Crédits, coupons, analyses, forfaits, widget…')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.help),
                  ),
                  ListTile(
                    leading: const Icon(Icons.support_agent),
                    title: Text(tr('Contacter le support')),
                    subtitle:
                        Text(tr('Signaler un problème ou poser une question')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => contactSupport(context, ref),
                  ),
                  ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: Text(tr('Conditions et mentions')),
                    subtitle: Text(tr(
                        'CGU, confidentialité, règles de la communauté, avertissements')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.legal),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: solidButtonStyle(context, SolidTone.orange).copyWith(
                  minimumSize:
                      const WidgetStatePropertyAll(Size.fromHeight(48))),
              onPressed: () => _confirmDeletion(context, ref),
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(tr('Supprimer mon compte')),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: solidButtonStyle(context, SolidTone.red).copyWith(
                  minimumSize:
                      const WidgetStatePropertyAll(Size.fromHeight(48))),
              onPressed: () async {
                await signOutEverywhere(ref);
              },
              icon: const Icon(Icons.logout),
              label: Text(tr('Se déconnecter')),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                version == null
                    ? ''
                    : trf('Version {0} ({1})',
                        [version.version, version.buildNumber]),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeletion(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(profileRepositoryProvider).deleteAccount();
      if (context.mounted) {
        showMessage(context, tr('Votre compte a été supprimé.'));
      }
    } catch (e) {
      if (context.mounted) showMessage(context, userMessageFor(e), error: true);
    }
  }
}

/// Titre d'un groupe du profil (Mon jeu, Mon compte, Communauté, Aide).
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(text,
          style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller.text.trim() == 'SUPPRIMER';
    return AlertDialog(
      title: Text(tr('Supprimer mon compte ?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Votre profil, vos préférences et votre historique seront effacés définitivement. Cette action est irréversible.'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
                labelText: tr('Tapez SUPPRIMER pour confirmer')),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Annuler'))),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
            minimumSize: const Size(0, 44),
          ),
          onPressed: ready ? () => Navigator.of(context).pop(true) : null,
          child: Text(tr('Supprimer')),
        ),
      ],
    );
  }
}

/// Choix de la langue (français ou anglais). La langue est appliquée au redémarrage :
/// elle est enregistrée sur le téléphone et sur le profil, puis l'app propose de se fermer.
class LanguageSelector extends ConsumerStatefulWidget {
  const LanguageSelector({super.key});

  @override
  ConsumerState<LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends ConsumerState<LanguageSelector> {
  SharedPreferences? get _prefs {
    try {
      return ref.read(sharedPreferencesProvider);
    } catch (_) {
      return null;
    }
  }

  Future<void> _choose(String lang) async {
    await _prefs?.setString(languagePrefKey, lang);
    try {
      await syncAccountLanguage(ref.read(supabaseClientProvider), lang: lang);
    } catch (_) {
      // Sans session (tests) : la langue reste enregistrée sur le téléphone.
    }
    if (!mounted) return;
    setState(() {});
    final en = lang == 'en';
    final restart = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(en
            ? 'Close the app to apply the language?'
            : 'Fermer l’application pour appliquer la langue ?'),
        content: Text(en
            ? 'The language will be applied when the app restarts. Then reopen Coupon Pro IA.'
            : 'La langue sera appliquée au redémarrage de l’application. Rouvrez ensuite Coupon Pro IA.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: Text(en ? 'Later' : 'Plus tard')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(en ? 'Restart now' : 'Redémarrer maintenant')),
        ],
      ),
    );
    if (restart == true) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final saved = _prefs?.getString(languagePrefKey) ?? appLanguage;
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        segments: [
          for (final e in appLanguages.entries)
            ButtonSegment(value: e.key, label: Text(e.value)),
        ],
        selected: {saved},
        onSelectionChanged: (sel) {
          if (sel.first != saved) _choose(sel.first);
        },
      ),
    );
  }
}

/// Rapports d'erreurs : plantages et lenteurs envoyés sans contenu personnel (activé par défaut).
class ErrorReportsSwitch extends ConsumerStatefulWidget {
  const ErrorReportsSwitch({super.key});

  @override
  ConsumerState<ErrorReportsSwitch> createState() => _ErrorReportsSwitchState();
}

class _ErrorReportsSwitchState extends ConsumerState<ErrorReportsSwitch> {
  @override
  Widget build(BuildContext context) {
    final ErrorReporter reporter;
    try {
      reporter = ref.watch(errorReporterProvider);
    } catch (_) {
      return const SizedBox.shrink();
    }
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(tr('Rapports d’erreurs')),
      subtitle: Text(tr(
          'Envoyer les plantages et lenteurs pour nous aider à corriger l’app. Aucun contenu personnel.')),
      value: reporter.enabled,
      onChanged: (v) async {
        await reporter.setEnabled(v);
        setState(() {});
      },
    );
  }
}
