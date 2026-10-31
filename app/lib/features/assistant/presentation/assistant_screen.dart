import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../analysis/data/analysis_format.dart';
import '../../coupons/presentation/coupon_widgets.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../shell/app_drawer.dart';
import '../../system/system_providers.dart';
import '../data/assistant_models.dart';
import '../data/assistant_repository.dart';

const _suggestions = [
  'Faites-moi un coupon de 3 matchs avec une cote totale proche de 4',
  'Je veux un coupon prudent pour demain',
  'Analyse les matchs de ce week-end',
  'Construis un coupon uniquement avec la Premier League',
  'Propose-moi trois versions d’un coupon équilibré',
  'C’est quoi la double chance ?',
];

/// Mon Assistant IA : conversation en langage naturel. L'IA comprend la demande, le moteur
/// statistique compose et vérifie ; l'utilisateur garde la main (enregistrer, modifier, analyser).
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen>
    with AutomaticKeepAliveClientMixin {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _conversationId;
  final List<AssistantMessage> _messages = [];
  bool _sending = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String text,
      {String? couponId, Map<String, dynamic>? quick}) async {
    final message = text.trim();
    if (message.isEmpty || _sending) return;
    final pending = AssistantMessage(
        id: 'local', role: 'user', content: message, createdAt: DateTime.now());
    setState(() {
      _sending = true;
      _messages.add(pending);
      _input.clear();
    });
    _scrollToEnd();
    try {
      final reply = await ref.read(assistantRepositoryProvider).send(message,
          conversationId: _conversationId, couponId: couponId, quick: quick);
      if (!mounted) return;
      setState(() {
        _conversationId = reply.conversationId;
        _messages
          ..remove(pending)
          ..addAll(reply.messages);
      });
      ref.invalidate(myCreditsProvider);
      ref.invalidate(conversationsProvider);
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.remove(pending));
      _input.text = message;
      showMessage(
          context, e is AssistantException ? e.message : userMessageFor(e),
          error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openConversation(Conversation c) async {
    try {
      final messages =
          await ref.read(assistantRepositoryProvider).messages(c.id);
      if (!mounted) return;
      setState(() {
        _conversationId = c.id;
        _messages
          ..clear()
          ..addAll(messages);
      });
      _scrollToEnd();
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    }
  }

  void _newConversation() => setState(() {
        _conversationId = null;
        _messages.clear();
      });

  Future<void> _showHistory() async {
    final picked = await showModalBottomSheet<Conversation>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _HistorySheet(),
    );
    if (picked != null) await _openConversation(picked);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final flags =
        ref.watch(featureFlagsProvider).valueOrNull ?? const <String, bool>{};
    final credits = ref.watch(myCreditsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('Mon Assistant IA'),
        actions: [
          if (credits != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ActionChip(
                avatar: const Icon(Icons.bolt, size: 18),
                label: Text(credits.unlimited ? '∞' : '${credits.total}'),
                tooltip: 'Crédits IA : ${credits.label}',
                onPressed: () => showMessage(
                  context,
                  credits.unlimited
                      ? 'Compte équipe : actions illimitées (journalisées).'
                      : 'Forfait ${credits.plan} : ${credits.planCredits} crédit(s) du mois + ${credits.extraCredits} supplémentaire(s). '
                          'Une proposition, une modification ou une analyse réussie coûte 1 crédit ; les questions sont gratuites.',
                ),
              ),
            ),
          IconButton(
            tooltip: 'Mes coupons',
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () => context.push(AppRoutes.myCoupons),
          ),
          IconButton(
              tooltip: 'Historique',
              icon: const Icon(Icons.history),
              onPressed: _showHistory),
          IconButton(
              tooltip: 'Nouvelle conversation',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _newConversation),
        ],
      ),
      body: flags['assistant_ia'] == false
          ? const InfoMessage(
              icon: Icons.pause_circle_outline,
              title: 'Assistant momentanément indisponible')
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Icon(Icons.smart_toy_outlined,
                                size: 48, color: theme.colorScheme.primary),
                            const SizedBox(height: 12),
                            Text('Décrivez le coupon que vous voulez',
                                style: theme.textTheme.titleMedium,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 6),
                            Text(
                              'L’IA comprend votre demande ; le moteur statistique choisit les sélections parmi les vrais '
                              'matchs cotés et vérifie tout. Vous gardez la main : enregistrer, modifier, analyser.',
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final s in _suggestions)
                                  ActionChip(
                                      label: Text(s),
                                      onPressed: () => _send(s)),
                              ],
                            ),
                          ],
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          itemCount: _messages.length + (_sending ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == _messages.length) return const _Typing();
                            final m = _messages[i];
                            return m.isUser
                                ? _UserBubble(text: m.content)
                                : _AssistantBubble(
                                    message: m,
                                    onAction: (label, couponId, quick) => _send(
                                        label,
                                        couponId: couponId,
                                        quick: quick),
                                    busy: _sending,
                                  );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 600,
                            textInputAction: TextInputAction.send,
                            onSubmitted: _send,
                            decoration: const InputDecoration(
                              hintText:
                                  'Ex. : 5 matchs, cote proche de 10, risque modéré',
                              border: OutlineInputBorder(),
                              isDense: true,
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          tooltip: 'Envoyer',
                          onPressed: _sending ? null : () => _send(_input.text),
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('L’assistant analyse les matchs…'),
          ],
        ),
      );
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 48, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: scheme.primary, borderRadius: BorderRadius.circular(16)),
        child: Text(text, style: TextStyle(color: scheme.onPrimary)),
      ),
    );
  }
}

typedef _Action = void Function(
    String label, String? couponId, Map<String, dynamic>? quick);

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble(
      {required this.message, required this.onAction, required this.busy});

  final AssistantMessage message;
  final _Action onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = message;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.content, style: theme.textTheme.bodyMedium),
                for (final w in m.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('⚠ $w', style: muted),
                  ),
                if (m.creditsCharged > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child:
                        Text('${m.creditsCharged} crédit débité', style: muted),
                  ),
              ],
            ),
          ),
          if (m.diagnosis != null) _DiagnosisCard(diagnosis: m.diagnosis!),
          for (final o in m.opportunities) _OpportunityTile(opportunity: o),
          for (final id in m.couponIds)
            _ProposalCard(couponId: id, onAction: onAction, busy: busy),
        ],
      ),
    );
  }
}

class _DiagnosisCard extends StatelessWidget {
  const _DiagnosisCard({required this.diagnosis});

  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title, List<String> items, IconData icon) =>
        items.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(icon, size: 16),
                      const SizedBox(width: 6),
                      Text(title, style: theme.textTheme.labelLarge)
                    ]),
                    for (final i in items)
                      Padding(
                          padding: const EdgeInsets.only(top: 3, left: 22),
                          child: Text(i, style: theme.textTheme.bodySmall)),
                  ],
                ),
              );
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section('Sélections les plus fragiles', diagnosis.fragiles,
                Icons.trending_down),
            section(
                'À vérifier', diagnosis.alerts, Icons.warning_amber_outlined),
            section(
                'Qualité des données', diagnosis.quality, Icons.info_outline),
          ],
        ),
      ),
    );
  }
}

class _OpportunityTile extends StatelessWidget {
  const _OpportunityTile({required this.opportunity});

  final Opportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = opportunity;
    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: ListTile(
        dense: true,
        onTap: () => context.push(AppRoutes.matchDetailFor(o.matchId)),
        title: Text('${o.match} · ${o.selection}'),
        subtitle: Text(
          '${o.competition} · ${dayLabel(o.kickoffAt, DateTime.now())} ${timeLabel(o.kickoffAt)} · '
          'modèle ${pct(o.modelProbability)}${o.impliedProbability == null ? '' : ' / marché ${pct(o.impliedProbability!)}'}',
        ),
        trailing: Text(decimal(o.odd),
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.primary)),
      ),
    );
  }
}

class _ProposalCard extends ConsumerWidget {
  const _ProposalCard(
      {required this.couponId, required this.onAction, required this.busy});

  final String couponId;
  final _Action onAction;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final coupon = ref.watch(userCouponProvider(couponId));
    return coupon.when(
      loading: () => const Padding(
          padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      error: (e, _) => Text(userMessageFor(e)),
      data: (c) {
        if (c == null) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.only(top: 8),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                        child:
                            Text(c.title, style: theme.textTheme.titleSmall)),
                    RiskBadge(risk: c.riskLevel, compact: true),
                  ],
                ),
                const SizedBox(height: 8),
                for (final s in c.selections)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${s.position}. ${s.match.home} – ${s.match.away} · ${outcomeKeyLabel(s.key, s.match.home, s.match.away)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Text(decimal(s.odd), style: theme.textTheme.labelLarge),
                        const SizedBox(width: 8),
                        Text(pct(s.modelProbability),
                            style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                const Divider(height: 16),
                Text(
                  'Cote ${decimal(c.totalOdd)} · probabilité estimée ${pct(c.combinedProbability)}'
                  '${c.impliedProbability == null ? '' : ' (marché ${pct(c.impliedProbability!)})'}',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                if (c.summary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(c.summary, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    c.isSaved
                        ? const Chip(
                            avatar: Icon(Icons.check, size: 16),
                            label: Text('Enregistré'))
                        : FilledButton.tonalIcon(
                            onPressed: () async {
                              try {
                                await ref
                                    .read(assistantRepositoryProvider)
                                    .setStatus(c.id, 'saved');
                                ref.invalidate(userCouponProvider(c.id));
                                ref.invalidate(savedCouponsProvider);
                              } catch (e) {
                                if (context.mounted) {
                                  showMessage(context, userMessageFor(e),
                                      error: true);
                                }
                              }
                            },
                            icon: const Icon(Icons.bookmark_add_outlined,
                                size: 18),
                            label: const Text('Enregistrer'),
                          ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => onAction(
                                  'Remplace les sélections les plus fragiles',
                                  c.id, {
                                'intent': 'modifier_coupon',
                                'modification': {
                                  'remplacer_plus_fragiles':
                                      c.selections.length >= 4 ? 2 : 1
                                },
                              }),
                      child: const Text('Remplacer les plus fragiles'),
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => onAction('Analyse ce coupon', c.id,
                              {'intent': 'analyser_coupon'}),
                      child: const Text('Analyser'),
                    ),
                    TextButton(
                      onPressed: () =>
                          context.push(AppRoutes.myCouponFor(c.id)),
                      child: const Text('Détail'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(conversationsProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(userMessageFor(e))),
          data: (items) => items.isEmpty
              ? const InfoMessage(
                  icon: Icons.forum_outlined,
                  title: 'Aucune conversation pour l’instant')
              : ListView(
                  children: [
                    for (final c in items)
                      ListTile(
                        leading: const Icon(Icons.forum_outlined),
                        title: Text(c.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${shortDate(c.updatedAt)} à ${timeLabel(c.updatedAt)}'),
                        onTap: () => Navigator.pop(context, c),
                        trailing: IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await ref
                                .read(assistantRepositoryProvider)
                                .deleteConversation(c.id);
                            ref.invalidate(conversationsProvider);
                          },
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
