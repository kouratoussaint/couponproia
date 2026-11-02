import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/data/sports_models.dart';
import '../../matches/data/sports_repository.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/admin_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Match offert d'un jour : identifiant, heure du choix, choisi par l'équipe ou automatiquement.
typedef FeaturedChoice = ({int matchId, DateTime chosenAt, bool manual});

String isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final featuredChoiceProvider = FutureProvider.autoDispose
    .family<FeaturedChoice?, DateTime>((ref, day) async {
  final row = await ref
      .watch(supabaseClientProvider)
      .from('featured_matches')
      .select('match_id, chosen_at, chosen_by')
      .eq('day', isoDay(day))
      .maybeSingle();
  if (row == null) return null;
  return (
    matchId: (row['match_id'] as num).toInt(),
    chosenAt: DateTime.parse(row['chosen_at'] as String).toLocal(),
    manual: row['chosen_by'] != null,
  );
});

final featuredAutoHourProvider = FutureProvider.autoDispose<int>((ref) async {
  final row = await ref
      .watch(supabaseClientProvider)
      .from('app_settings')
      .select('value')
      .eq('key', 'featured.auto_pick_hour')
      .maybeSingle();
  return (row?['value'] as num?)?.toInt() ?? 9;
});

/// Console → Analyse offerte : le super administrateur choisit le match du jour (ou de demain) ;
/// sans choix avant l'heure réglée, l'application choisit automatiquement.
class FeaturedAdminScreen extends ConsumerStatefulWidget {
  const FeaturedAdminScreen({super.key});

  @override
  ConsumerState<FeaturedAdminScreen> createState() =>
      _FeaturedAdminScreenState();
}

class _FeaturedAdminScreenState extends ConsumerState<FeaturedAdminScreen> {
  bool _tomorrow = false;
  int? _saving;

  DateTime get _day {
    final t = dateOnly(DateTime.now());
    return _tomorrow ? DateTime(t.year, t.month, t.day + 1) : t;
  }

  Future<void> _choose(MatchSummary m) async {
    setState(() => _saving = m.id);
    try {
      await ref.read(supabaseClientProvider).rpc('admin_set_featured',
          params: {'p_match': m.id, 'p_day': isoDay(_day)});
      ref.invalidate(featuredChoiceProvider(_day));
      ref.invalidate(featuredMatchProvider);
      if (mounted) {
        showMessage(
            context,
            trf(
                '{0} – {1} : analyse offerte {2}. Elle sera préparée dans les 15 minutes.',
                [
                  m.home.name,
                  m.away.name,
                  _tomorrow ? 'demain' : tr('aujourd’hui')
                ]));
      }
    } catch (e) {
      if (mounted) showMessage(context, adminErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  Future<void> _setHour(int h) async {
    try {
      await ref
          .read(adminRepositoryProvider)
          .setSetting('featured.auto_pick_hour', h);
      ref.invalidate(featuredAutoHourProvider);
      if (mounted) showMessage(context, trf('Choix automatique à {0} h.', [h]));
    } catch (e) {
      if (mounted) showMessage(context, adminErrorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final perms =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if (!perms.contains('featured.manage')) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Analyse offerte'))),
        body: InfoMessage(
            icon: Icons.lock_outline,
            title: tr('Écran réservé au super administrateur')),
      );
    }
    final day = _day;
    final choice = ref.watch(featuredChoiceProvider(day)).valueOrNull;
    final hour = ref.watch(featuredAutoHourProvider).valueOrNull ?? 9;
    final matches = ref.watch(matchesOfDayProvider(day));
    final markets =
        ref.watch(market1x2OfDayProvider(day)).valueOrNull ?? const {};
    final now = DateTime.now();
    final all = matches.valueOrNull ?? const <MatchSummary>[];
    final chosen = all.where((m) => m.id == choice?.matchId).firstOrNull;
    final open = [
      for (final m in all)
        if (m.status == MatchStatus.scheduled &&
            m.kickoffAt.isAfter(now.add(const Duration(minutes: 30))))
          m
    ]..sort((a, b) {
        final p = a.competition.priority.compareTo(b.competition.priority);
        return p != 0 ? p : a.kickoffAt.compareTo(b.kickoffAt);
      });
    return Scaffold(
      appBar: AppBar(title: Text(tr('Analyse offerte du jour'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(tr('Aujourd’hui'))),
              ButtonSegment(value: true, label: Text(tr('Demain'))),
            ],
            selected: {_tomorrow},
            onSelectionChanged: (s) => setState(() => _tomorrow = s.first),
          ),
          const SizedBox(height: 12),
          Card(
            color: BrandColors.orange.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: BrandColors.orange),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard, color: BrandColors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      choice == null
                          ? trf(
                              'Aucun match choisi. Sans choix de votre part, l’application en choisira un à {0} h.',
                              [hour])
                          : trf('{0}\n{1} le {2} à {3}.', [
                              chosen == null
                                  ? trf('Match n° {0}', [choice.matchId])
                                  : '${chosen.home.name} – ${chosen.away.name}',
                              choice.manual
                                  ? tr('Choisi par l’équipe')
                                  : tr('Choisi automatiquement'),
                              shortDate(choice.chosenAt),
                              timeLabel(choice.chosenAt)
                            ]),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(tr('Choix automatique')),
              subtitle: Text(trf(
                  'Sans choix avant {0} h (heure locale), le match le plus suivi avec des cotes est retenu.',
                  [hour])),
              trailing: DropdownButton<int>(
                value: hour,
                underline: const SizedBox.shrink(),
                items: [
                  for (var h = 5; h <= 20; h++)
                    DropdownMenuItem(value: h, child: Text(trf('{0} h', [h]))),
                ],
                onChanged: (h) {
                  if (h != null && h != hour) _setHour(h);
                },
              ),
            ),
          ),
          SectionTitle(tr('Choisir le match')),
          ...matches.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(userMessageFor(e))],
            data: (_) => open.isEmpty
                ? [
                    Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(tr(
                          'Aucun match programmé à plus de 30 minutes du coup d’envoi ce jour-là.')),
                    )
                  ]
                : [
                    for (final m in open)
                      Card(
                        shape: m.id == choice?.matchId
                            ? RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                    color: BrandColors.orange, width: 1.5))
                            : null,
                        clipBehavior: Clip.antiAlias,
                        child: MatchCard(
                          match: m,
                          market: markets[m.id],
                          action: m.id == choice?.matchId
                              ? const Icon(Icons.card_giftcard,
                                  color: BrandColors.orange)
                              : FilledButton.tonal(
                                  onPressed:
                                      _saving == null ? () => _choose(m) : null,
                                  child: _saving == m.id
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : Text(tr('Choisir')),
                                ),
                        ),
                      ),
                  ],
          ),
          const SizedBox(height: 8),
          Text(
            tr('Le match offert reste modifiable tant qu’il n’a pas commencé. Son analyse est préparée automatiquement et ouverte à tous, sans crédit.'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
