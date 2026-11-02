import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/error_messages.dart';
import '../../core/providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/widgets/form_widgets.dart';
import '../matches/data/sports_format.dart';
import '../system/system_providers.dart';
import 'legal_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Documents vus et acceptés à l'inscription : acceptés automatiquement à la première connexion.
const legalSignupKey = 'legal_signup_ids';

void openLegalDocument(BuildContext context, String code) =>
    context.push(AppRoutes.legalDocumentFor(code));

/// Mise en forme simple des documents : « ## » titre, « - » puce, **gras**, paragraphes.
class LegalText extends StatelessWidget {
  const LegalText(this.body, {super.key});

  final String body;

  static List<TextSpan> _inline(String line, TextStyle? base) {
    final spans = <TextSpan>[];
    final parts = line.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(TextSpan(
          text: parts[i],
          style: i.isOdd ? base?.copyWith(fontWeight: FontWeight.w700) : base));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme.bodyMedium?.copyWith(height: 1.45);
    final children = <Widget>[];
    for (final raw in body.trim().split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      if (line.startsWith('## ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(line.substring(3),
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
        ));
      } else if (line.startsWith('- ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('•  ', style: text),
            Expanded(
                child: Text.rich(
                    TextSpan(children: _inline(line.substring(2), text)))),
          ]),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text.rich(TextSpan(children: _inline(line, text))),
        ));
      }
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// Lecture d'un document (accessible connecté ou non).
class LegalDocumentScreen extends ConsumerWidget {
  const LegalDocumentScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(legalDocumentProvider(code));
    final settings = ref.watch(publicSettingsProvider).valueOrNull ??
        const <String, dynamic>{};
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(legalTitles[code] ?? tr('Document'))),
      body: doc.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(userMessageFor(e), textAlign: TextAlign.center))),
        data: (d) => d == null
            ? Center(child: Text(tr('Document indisponible.')))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Text(
                      trf('Version du {0}/{1}',
                          [shortDate(d.publishedAt), d.publishedAt.year]),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  LegalText(fillLegalPlaceholders(d.body, settings)),
                ],
              ),
      ),
    );
  }
}

/// Liens « Conditions générales d'utilisation » et « Politique de confidentialité » dans une phrase.
class LegalConsentText extends StatelessWidget {
  const LegalConsentText(
      {super.key,
      this.prefix = 'J’ai lu et j’accepte les ',
      this.withAge = true});

  final String prefix;
  final bool withAge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = TextStyle(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
        fontWeight: FontWeight.w600);
    return Text.rich(TextSpan(
      style: theme.textTheme.bodyMedium,
      children: [
        TextSpan(text: tr(prefix)),
        TextSpan(
            text: tr('Conditions générales d’utilisation'),
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => openLegalDocument(context, 'terms')),
        TextSpan(text: tr(' et la ')),
        TextSpan(
            text: tr('Politique de confidentialité'),
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => openLegalDocument(context, 'privacy')),
        TextSpan(text: withAge ? tr(', et je confirme être majeur(e).') : '.'),
      ],
    ));
  }
}

/// Écran bloquant tant que la version en vigueur des CGU ou de la politique de confidentialité
/// n'a pas été acceptée (première connexion ou nouvelle version).
class LegalAcceptanceScreen extends ConsumerStatefulWidget {
  const LegalAcceptanceScreen(
      {super.key, required this.pending, required this.onSignOut});

  final List<PendingDocument> pending;
  final Future<void> Function() onSignOut;

  @override
  ConsumerState<LegalAcceptanceScreen> createState() =>
      _LegalAcceptanceScreenState();
}

class _LegalAcceptanceScreenState extends ConsumerState<LegalAcceptanceScreen> {
  bool _checked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Acceptées à l'inscription (mêmes versions) : enregistrement automatique.
    final prefs = ref.read(sharedPreferencesProvider);
    final seen = (prefs.getString(legalSignupKey) ?? '')
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    if (seen.isNotEmpty && widget.pending.every((p) => seen.contains(p.id))) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _accept());
    }
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(legalRepositoryProvider)
          .accept([for (final p in widget.pending) p.id]);
      await ref.read(sharedPreferencesProvider).remove(legalSignupKey);
      ref.invalidate(legalStatusProvider);
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          children: [
            Icon(Icons.gavel_outlined,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(tr('Conditions d’utilisation'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(
              tr('Coupon Pro IA fournit des analyses et des estimations. Aucun pari n’est pris dans l’application et aucun gain n’est garanti. Merci de lire et d’accepter les documents suivants pour continuer.'),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(children: [
                for (final p in widget.pending)
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(legalTitles[p.code] ?? p.title),
                    subtitle: Text(trf('Version du {0}', [_day(p.version)])),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openLegalDocument(context, p.code),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _checked,
              onChanged:
                  _busy ? null : (v) => setState(() => _checked = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const LegalConsentText(),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _checked && !_busy ? _accept : null,
              child: Text(tr('Accepter et continuer')),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : widget.onSignOut,
              child: Text(tr('Se déconnecter')),
            ),
          ],
        ),
      ),
    );
  }

  static String _day(String version) {
    final p = version.split('.').first.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : version;
  }
}
