import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/admin_repository.dart';
import '../data/competitions_admin_repository.dart';

/// Libellé, couleur et explication de chaque état.
String statusLabel(CompetitionStatus s) => switch (s) {
      CompetitionStatus.active => tr('Actif'),
      CompetitionStatus.observation => tr('En observation'),
      CompetitionStatus.inactive => tr('Inactif'),
    };

String _filterLabel(CompetitionStatus s, int n) => switch (s) {
      CompetitionStatus.active => trf('Actives ({0})', [n]),
      CompetitionStatus.observation => trf('En observation ({0})', [n]),
      CompetitionStatus.inactive => trf('Inactives ({0})', [n]),
    };

String statusHelp(CompetitionStatus s) => switch (s) {
      CompetitionStatus.active => tr(
          'Matchs, analyses et coupons automatiques (avec un verdict positif du moteur).'),
      CompetitionStatus.observation => tr(
          'Données chargées et visibles dans l’app, analyse IA et coupons composés à la main ; aucun coupon automatique.'),
      CompetitionStatus.inactive => tr(
          'Plus rien n’est synchronisé ni affiché. Les matchs des coupons non réglés restent suivis jusqu’au règlement.'),
    };

Color statusColor(ColorScheme scheme, CompetitionStatus s) => switch (s) {
      CompetitionStatus.active => scheme.primary,
      CompetitionStatus.observation => scheme.secondary,
      CompetitionStatus.inactive => scheme.onSurfaceVariant,
    };

String _brier(double? v) =>
    v == null ? '–' : v.toStringAsFixed(3).replaceAll('.', decimalSeparator);

/// Phrase sur la qualité du moteur pour une compétition.
String qualityLine(AdminCompetition c) {
  final q = c.quality;
  final measured = q == null || q.matches == 0
      ? tr('Moteur : aucun match évalué')
      : q.verdict == null
          ? trf('Moteur : {0} matchs évalués sur 100 nécessaires', [q.matches])
          : q.verdict!
              ? trf(
                  'Moteur : verdict positif sur {0} matchs (Brier {1} contre {2})',
                  [
                      q.matches,
                      _brier(q.brierModel),
                      _brier(q.brierBaseline)
                    ])
              : trf(
                  'Moteur : ne bat pas la référence sur {0} matchs (Brier {1} contre {2})',
                  [q.matches, _brier(q.brierModel), _brier(q.brierBaseline)]);
  return c.qualityOverride
      ? '$measured · ${tr('admise par le super administrateur')}'
      : measured;
}

String _ago(DateTime? t) {
  if (t == null) return tr('jamais synchronisée');
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 60) return trf('synchro il y a {0} min', [d.inMinutes]);
  if (d.inHours < 48) return trf('synchro il y a {0} h', [d.inHours]);
  return trf('synchro il y a {0} j', [d.inDays]);
}

/// Console → Données sportives → Compétitions (LOT 25).
class CompetitionsAdminScreen extends ConsumerStatefulWidget {
  const CompetitionsAdminScreen({super.key});

  @override
  ConsumerState<CompetitionsAdminScreen> createState() =>
      _CompetitionsAdminScreenState();
}

class _CompetitionsAdminScreenState
    extends ConsumerState<CompetitionsAdminScreen> {
  CompetitionStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = ref.watch(adminCompetitionsProvider);
    final permissions =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Compétitions')),
        actions: [
          IconButton(
            tooltip: tr('Actualiser'),
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminCompetitionsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const CatalogSearchScreen())),
        icon: const Icon(Icons.add),
        label: Text(tr('Ajouter')),
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: tr('Liste indisponible'),
            body: adminErrorMessage(e)),
        data: (all) {
          final n = {
            for (final s in CompetitionStatus.values)
              s: all.where((c) => c.status == s).length
          };
          final tracked = all.length - n[CompetitionStatus.inactive]!;
          final shown = _filter == null
              ? all
              : all.where((c) => c.status == _filter).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(adminCompetitionsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            tracked == 1
                                ? tr('1 compétition suivie')
                                : trf('{0} compétitions suivies', [tracked]),
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          trf(
                              'Actives : {0} · en observation : {1} · inactives : {2} · environ {3} requêtes API-Football par jour',
                              [
                                n[CompetitionStatus.active],
                                n[CompetitionStatus.observation],
                                n[CompetitionStatus.inactive],
                                tracked * 14,
                              ]),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in [null, ...CompetitionStatus.values])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f == null
                                ? trf('Toutes ({0})', [all.length])
                                : _filterLabel(f, n[f]!)),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                for (final c in shown)
                  _CompetitionTile(
                    competition: c,
                    canOverride: permissions.contains('competitions.override'),
                  ),
                if (shown.isEmpty)
                  InfoMessage(
                      icon: Icons.emoji_events_outlined,
                      title: tr('Aucune compétition dans cet état')),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);

  final CompetitionStatus status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(Theme.of(context).colorScheme, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(statusLabel(status),
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo(this.url);

  final String? url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: 18,
      backgroundColor: scheme.surfaceContainerHigh,
      child: Icon(Icons.emoji_events_outlined,
          size: 18, color: scheme.onSurfaceVariant),
    );
    if (url == null) return fallback;
    return SizedBox(
      width: 36,
      height: 36,
      child: Image.network(url!, errorBuilder: (_, __, ___) => fallback),
    );
  }
}

class _CompetitionTile extends ConsumerWidget {
  const _CompetitionTile(
      {required this.competition, required this.canOverride});

  final AdminCompetition competition;
  final bool canOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = competition;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final verdictOk = c.qualityOverride || c.quality?.verdict == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showCompetitionActions(context, ref, c, canOverride),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Logo(c.logoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(c.displayName,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        _StatusPill(c.status),
                      ],
                    ),
                    if (c.country != null &&
                        c.country != 'World' &&
                        !c.displayName.contains(c.country!))
                      Text(c.country!, style: muted),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          verdictOk
                              ? Icons.verified_outlined
                              : c.quality?.verdict == false
                                  ? Icons.report_outlined
                                  : Icons.hourglass_empty,
                          size: 16,
                          color: verdictOk
                              ? theme.colorScheme.primary
                              : c.quality?.verdict == false
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(qualityLine(c),
                                style: theme.textTheme.bodySmall)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        trf('{0} matchs dans les 14 jours', [c.matches14d]),
                        _ago(c.lastSyncAt),
                        trf('ordre {0}', [c.priority]),
                        if (c.status == CompetitionStatus.active &&
                            !c.inAutomaticCoupons)
                          tr('hors coupons automatiques'),
                      ].join(' · '),
                      style: muted,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Feuille d'actions d'une compétition : état, ordre, forçage.
Future<void> showCompetitionActions(
    BuildContext context, WidgetRef ref, AdminCompetition c, bool canOverride) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ActionsSheet(competition: c, canOverride: canOverride),
  );
}

class _ActionsSheet extends ConsumerStatefulWidget {
  const _ActionsSheet({required this.competition, required this.canOverride});

  final AdminCompetition competition;
  final bool canOverride;

  @override
  ConsumerState<_ActionsSheet> createState() => _ActionsSheetState();
}

class _ActionsSheetState extends ConsumerState<_ActionsSheet> {
  late CompetitionStatus _status = widget.competition.status;
  late final _priority =
      TextEditingController(text: '${widget.competition.priority}');
  late bool _override = widget.competition.qualityOverride;
  bool _busy = false;

  @override
  void dispose() {
    _priority.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = widget.competition;
    final repo = ref.read(competitionsAdminRepositoryProvider);
    setState(() => _busy = true);
    try {
      String? warning;
      if (_status != c.status) {
        warning = (await repo.setStatus(c.id, _status)).warning;
      }
      final p = int.tryParse(_priority.text.trim());
      if (p != null && p != c.priority) await repo.setPriority(c.id, p);
      if (widget.canOverride && _override != c.qualityOverride) {
        await repo.setOverride(c.id, _override);
      }
      ref.invalidate(adminCompetitionsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context,
          warning == null ? tr('Compétition mise à jour.') : tr(warning));
    } catch (e) {
      if (mounted) showMessage(context, adminErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.competition;
    final deactivating = _status == CompetitionStatus.inactive &&
        c.status != CompetitionStatus.inactive;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.displayName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(qualityLine(c), style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Text(tr('État'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final s in CompetitionStatus.values)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: _status == s
                    ? statusColor(theme.colorScheme, s).withValues(alpha: 0.10)
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: _status == s
                          ? statusColor(theme.colorScheme, s)
                          : theme.colorScheme.outlineVariant),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _status = s),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                            _status == s
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: statusColor(theme.colorScheme, s)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(statusLabel(s),
                                  style: theme.textTheme.titleSmall),
                              Text(statusHelp(s),
                                  style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_status == CompetitionStatus.active &&
                c.status != CompetitionStatus.active &&
                !c.qualityOverride &&
                c.quality?.verdict != true)
              _Notice(
                icon: Icons.info_outline,
                text: tr(
                    'Sans verdict positif du moteur, elle reste hors des coupons automatiques. Conseillé : attendre l’évaluation du lundi.'),
              ),
            if (deactivating && c.openCoupons > 0)
              _Notice(
                icon: Icons.warning_amber_outlined,
                text: trf(
                    '{0} coupon(s) non réglé(s) contiennent un de ses matchs : ces matchs resteront suivis jusqu’au règlement.',
                    [c.openCoupons]),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _priority,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('Ordre d’affichage'),
                helperText:
                    tr('Plus petit = plus haut dans les listes de l’app.'),
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.canOverride) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _override,
                onChanged: (v) => setState(() => _override = v),
                title: Text(tr('Admettre sans verdict du moteur')),
                subtitle: Text(tr(
                    'Super administrateur : la compétition entre dans les coupons automatiques même sans 100 matchs évalués. Tracé dans l’audit.')),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(tr('Enregistrer')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.secondary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// Ajout d'une compétition depuis le catalogue du fournisseur.
class CatalogSearchScreen extends ConsumerStatefulWidget {
  const CatalogSearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<CatalogSearchScreen> createState() =>
      _CatalogSearchScreenState();
}

class _CatalogSearchScreenState extends ConsumerState<CatalogSearchScreen> {
  late final _q = TextEditingController(text: widget.initialQuery);
  late String _query = widget.initialQuery;
  String? _adding;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _add(CatalogLeague l) async {
    setState(() => _adding = l.providerRef);
    try {
      await ref.read(competitionsAdminRepositoryProvider).add(l.providerRef);
      ref.invalidate(adminCompetitionsProvider);
      ref.invalidate(catalogSearchProvider(_query));
      if (mounted) {
        showMessage(
            context,
            trf('{0} ajoutée en observation : saison, classement et historique se chargent maintenant.',
                [l.name]));
      }
    } catch (e) {
      if (mounted) showMessage(context, adminErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _adding = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final res = _query.trim().length >= 2
        ? ref.watch(catalogSearchProvider(_query.trim()))
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Ajouter une compétition'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          TextField(
            controller: _q,
            autofocus: widget.initialQuery.isEmpty,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr('Nom ou pays (ex. Ligue 1, Burkina, Saudi)'),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) => setState(() => _query = v),
            onChanged: (v) {
              if (v.trim().length >= 3) setState(() => _query = v);
            },
          ),
          const SizedBox(height: 8),
          Text(tr('Ajoutée en observation : visible dans l’app, hors coupons automatiques. Coût : environ 14 requêtes API-Football par jour, plus 4 au chargement.'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          if (res == null)
            InfoMessage(
                icon: Icons.travel_explore_outlined,
                title: tr('Recherchez dans le catalogue d’API-Football')),
          if (res != null)
            ...res.when(
              loading: () => const [
                Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()))
              ],
              error: (e, _) => [
                InfoMessage(
                    icon: Icons.cloud_off_outlined,
                    title: tr('Recherche indisponible'),
                    body: adminErrorMessage(e))
              ],
              data: (s) => [
                if (s.size == 0)
                  InfoMessage(
                    icon: Icons.inventory_2_outlined,
                    title: tr('Catalogue pas encore chargé'),
                    body: tr(
                        'Il se met à jour chaque lundi à 3 h 10. Vous pouvez le charger tout de suite (1 requête).'),
                    action: OutlinedButton.icon(
                      onPressed: () async {
                        await ref
                            .read(competitionsAdminRepositoryProvider)
                            .refreshCatalog();
                        if (context.mounted) {
                          showMessage(context,
                              tr('Catalogue en cours de chargement : relancez la recherche dans une minute.'));
                        }
                      },
                      icon: const Icon(Icons.download),
                      label: Text(tr('Charger le catalogue')),
                    ),
                  )
                else if (s.results.isEmpty)
                  InfoMessage(
                      icon: Icons.search_off,
                      title: tr('Aucune compétition trouvée'))
                else ...[
                  Text(
                      trf('{0} résultat(s) · catalogue du {1}', [
                        s.results.length,
                        s.refreshedAt == null ? '–' : shortDate(s.refreshedAt!)
                      ]),
                      style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  for (final l in s.results)
                    _CatalogTile(
                        league: l,
                        busy: _adding == l.providerRef,
                        onAdd: _adding == null ? () => _add(l) : null),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({required this.league, required this.busy, this.onAdd});

  final CatalogLeague league;
  final bool busy;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = league;
    Widget cover(String label, bool ok) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ok ? Icons.check_circle : Icons.cancel_outlined,
                size: 14,
                color: ok
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 3),
            Text(label, style: theme.textTheme.bodySmall),
          ]),
        );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _Logo(l.logoUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.name, style: theme.textTheme.titleSmall),
                  Text(
                    [
                      l.country ?? '–',
                      if (l.type == 'cup') tr('coupe') else tr('championnat'),
                      if (l.currentSeason != null)
                        trf('saison {0}', [l.currentSeason]),
                      'ID ${l.providerRef}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Wrap(children: [
                    cover(tr('Cotes'), l.odds),
                    cover(tr('Compositions'), l.lineups),
                    cover(tr('Statistiques'), l.statistics),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (l.tracked)
              _StatusPill(l.status!)
            else
              FilledButton.tonal(
                onPressed: onAdd,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.status == CompetitionStatus.inactive
                        ? tr('Réactiver')
                        : tr('Ajouter')),
              ),
          ],
        ),
      ),
    );
  }
}
