import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/data/sports_models.dart';
import '../../matches/data/sports_repository.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../profile/data/profile_repository.dart';
import '../data/preferences_repository.dart';

/// Ouvre le parcours (au premier lancement, ou depuis le profil pour modifier ses choix).
Future<void> showOnboarding(BuildContext context, {bool fromProfile = false}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: fromProfile,
      enableDrag: fromProfile,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => OnboardingSheet(fromProfile: fromProfile),
    );

/// Premier lancement en 3 étapes : pseudo, compétitions suivies, niveau.
class OnboardingSheet extends ConsumerStatefulWidget {
  const OnboardingSheet({super.key, this.fromProfile = false});

  final bool fromProfile;

  @override
  ConsumerState<OnboardingSheet> createState() => _OnboardingSheetState();
}

class _OnboardingSheetState extends ConsumerState<OnboardingSheet> {
  final _name = TextEditingController();
  int _step = 0;
  Set<int> _favorites = {};
  UserLevel? _level;
  bool _busy = false;
  bool _loaded = false;
  bool _showAll = false;
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _initFrom(UserPreferences? prefs, String? name) {
    if (_loaded) return;
    _loaded = true;
    _name.text = name ?? '';
    _favorites = {...?prefs?.favoriteCompetitions};
    _level = prefs?.level;
  }

  Future<void> _next() async {
    if (_step == 0) {
      final error = Validators.displayName(_name.text);
      setState(() => _nameError = error);
      if (error != null) return;
    }
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    await _finish(skipped: false);
  }

  Future<void> _finish({required bool skipped}) async {
    setState(() => _busy = true);
    try {
      final current = ref.read(myProfileProvider).valueOrNull?.displayName;
      if (!skipped && _name.text.trim() != current) {
        await ref.read(profileRepositoryProvider).updateDisplayName(_name.text);
        ref.invalidate(myProfileProvider);
      }
      await ref.read(preferencesRepositoryProvider).save(
            favoriteCompetitions: skipped ? null : _favorites,
            level: skipped ? null : _level,
            markOnboarded: true,
          );
      ref.invalidate(myPreferencesProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showMessage(context, userMessageFor(e), error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = ref.watch(myPreferencesProvider);
    final profile = ref.watch(myProfileProvider);
    if (prefs.isLoading || profile.isLoading) {
      return const SizedBox(
          height: 240, child: Center(child: CircularProgressIndicator()));
    }
    _initFrom(prefs.valueOrNull, profile.valueOrNull?.displayName);

    final step = switch (_step) {
      0 => _NameStep(controller: _name, error: _nameError),
      1 => _CompetitionsStep(
          selected: _favorites,
          showAll: _showAll,
          onShowAll: () => setState(() => _showAll = true),
          onToggle: (id) => setState(() => _favorites.contains(id)
              ? _favorites.remove(id)
              : _favorites.add(id)),
        ),
      _ => _LevelStep(
          selected: _level, onSelected: (l) => setState(() => _level = l)),
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Container(
                    height: 5,
                    margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Étape ${_step + 1} sur 3', style: theme.textTheme.labelMedium),
          const SizedBox(height: 12),
          Flexible(child: SingleChildScrollView(child: step)),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          Row(
            children: [
              Expanded(
                child: _step == 0
                    ? TextButton(
                        onPressed: _busy
                            ? null
                            : () => widget.fromProfile
                                ? Navigator.of(context).pop()
                                : _finish(skipped: true),
                        child:
                            Text(widget.fromProfile ? 'Annuler' : 'Plus tard'),
                      )
                    : OutlinedButton.icon(
                        onPressed: _busy ? null : () => setState(() => _step--),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Retour'),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _next,
                  icon: Icon(_step < 2 ? Icons.arrow_forward : Icons.check),
                  label: Text(_step < 2 ? 'Suivant' : 'Terminer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader(
      {required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, size: 30, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 14),
        Text(title,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _NameStep extends StatelessWidget {
  const _NameStep({required this.controller, this.error});

  final TextEditingController controller;
  final String? error;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepHeader(
            icon: Icons.waving_hand_outlined,
            title: 'Bienvenue sur Coupon Pro IA',
            subtitle: 'Comment souhaitez-vous qu’on vous appelle ?',
          ),
          TextField(
            controller: controller,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration:
                InputDecoration(labelText: 'Votre pseudo', errorText: error),
          ),
        ],
      );
}

class _CompetitionsStep extends ConsumerWidget {
  const _CompetitionsStep({
    required this.selected,
    required this.showAll,
    required this.onShowAll,
    required this.onToggle,
  });

  final Set<int> selected;
  final bool showAll;
  final VoidCallback onShowAll;
  final ValueChanged<int> onToggle;

  static const _initial = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final competitions = ref.watch(competitionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeader(
          icon: Icons.emoji_events_outlined,
          title: 'Vos compétitions',
          subtitle: 'Leurs matchs passeront en premier sur l’accueil.',
        ),
        competitions.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(userMessageFor(e)),
          data: (all) {
            final List<CompetitionRef> shown =
                showAll ? all : all.take(_initial).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 3.2,
                  children: [
                    for (final c in shown)
                      _CompetitionTile(
                        competition: c,
                        selected: selected.contains(c.id),
                        onTap: () => onToggle(c.id),
                      ),
                  ],
                ),
                if (!showAll && all.length > _initial)
                  TextButton(
                      onPressed: onShowAll,
                      child: Text('Voir les ${all.length} compétitions')),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text('Facultatif : vous pouvez passer cette étape.',
            style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _CompetitionTile extends StatelessWidget {
  const _CompetitionTile(
      {required this.competition, required this.selected, required this.onTap});

  final CompetitionRef competition;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              SportsLogo(
                  url: competition.logoUrl,
                  size: 26,
                  fallback: Icons.emoji_events_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  competition.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelStep extends StatelessWidget {
  const _LevelStep({required this.selected, required this.onSelected});

  final UserLevel? selected;
  final ValueChanged<UserLevel> onSelected;

  static const _icons = {
    UserLevel.debutant: Icons.school_outlined,
    UserLevel.intermediaire: Icons.bar_chart,
    UserLevel.expert: Icons.psychology_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeader(
          icon: Icons.menu_book_outlined,
          title: 'Votre niveau',
          subtitle:
              'On adapte les explications. Les chiffres restent les mêmes pour tout le monde.',
        ),
        for (final l in UserLevel.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: selected == l
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color:
                        selected == l ? scheme.primary : scheme.outlineVariant,
                    width: selected == l ? 2 : 1),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                leading: Icon(_icons[l], color: scheme.primary),
                title: Text(l.label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(l.description),
                trailing: selected == l
                    ? Icon(Icons.check_circle, color: scheme.primary)
                    : null,
                onTap: () => onSelected(l),
              ),
            ),
          ),
      ],
    );
  }
}
