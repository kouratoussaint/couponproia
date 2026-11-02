import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../matches/presentation/sports_widgets.dart';
import '../billing/credit_costs.dart';
import '../profile/presentation/responsible_gaming_screen.dart';
import 'help_content.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Centre d'aide : recherche, articles par thème, contact du support.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _search.text.trim();
    final found = searchHelp(q);
    Widget tile(HelpArticle a) => ListTile(
          title: Text(a.title),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.helpArticleFor(a.id)),
        );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Aide et questions fréquentes'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: tr('Rechercher : crédits, coupon du jour, widget…'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: tr('Effacer'),
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_search.clear)),
            ),
          ),
          const SizedBox(height: 8),
          if (q.length >= 2) ...[
            if (found.isEmpty)
              InfoMessage(
                icon: Icons.search_off,
                title: tr('Aucun article'),
                body: tr(
                    'Essayez un autre mot, ou écrivez-nous : nous répondons à chaque message.'),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [for (final a in found) tile(a)]),
              ),
          ] else
            for (final cat in helpCategories) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                child: Text(cat,
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800)),
              ),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (final a in helpArticles.where((a) => a.category == cat))
                    tile(a)
                ]),
              ),
            ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => contactSupport(context, ref),
            icon: const Icon(Icons.support_agent),
            label: Text(tr('Contacter le support')),
          ),
        ],
      ),
    );
  }
}

/// Un article de l'aide (coûts en crédits à jour).
class HelpArticleScreen extends ConsumerWidget {
  const HelpArticleScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final a = helpArticle(id);
    if (a == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Aide'))),
        body: InfoMessage(
            icon: Icons.help_outline, title: tr('Article introuvable')),
      );
    }
    String fill(String t) => fillCosts(t,
        analysis: creditsLabel(ref.watch(analysisCostProvider)),
        lab: creditsLabel(ref.watch(labCostProvider)),
        assistant: creditsLabel(ref.watch(assistantCostProvider)));
    final related = [
      for (final r in helpArticles)
        if (r.category == a.category && r.id != a.id) r
    ];
    return Scaffold(
      appBar: AppBar(title: Text(a.category)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(a.title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final b in a.blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: b.startsWith('• ')
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8, left: 4),
                          child: Text('•',
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(color: theme.colorScheme.primary)),
                        ),
                        Expanded(
                            child: Text(fill(b.substring(2)),
                                style: theme.textTheme.bodyLarge)),
                      ],
                    )
                  : Text(fill(b), style: theme.textTheme.bodyLarge),
            ),
          if (a.action case (final label, final route)) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                  onPressed: () => route.contains('?') ||
                          route == AppRoutes.coupons ||
                          route == AppRoutes.assistant ||
                          route == AppRoutes.profile
                      ? context.go(route)
                      : context.push(route),
                  child: Text(label)),
            ),
          ],
          if (related.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(tr('Dans le même thème'),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            for (final r in related)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    context.pushReplacement(AppRoutes.helpArticleFor(r.id)),
              ),
          ],
        ],
      ),
    );
  }
}

/// Bouton « ? » d'un écran : ouvre l'article d'aide correspondant.
class HelpButton extends StatelessWidget {
  const HelpButton(this.articleId, {super.key});

  final String articleId;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tr('Aide'),
        icon: const Icon(Icons.help_outline),
        onPressed: () => context.push(AppRoutes.helpArticleFor(articleId)),
      );
}
