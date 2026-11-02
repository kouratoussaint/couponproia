import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Segments d'utilisateurs : (code, libellé, description).
final campaignSegments = [
  ('all', tr('Tous les utilisateurs'), tr('Comptes actifs (non suspendus)')),
  ('free', tr('Sans forfait payant'), tr('Forfait FREE aujourd’hui')),
  (
    'paying',
    tr('Forfait payant en cours'),
    tr('STARTER, PRO TIPSTER, BUSINESS')
  ),
  (
    'expiring',
    tr('Forfait qui se termine'),
    tr('Dans les 7 jours, sans prolongation')
  ),
  ('expired', tr('Forfait terminé récemment'), tr('Depuis moins de 30 jours')),
  ('never_paid', tr('N’ont jamais payé'), tr('Aucun achat réussi')),
  (
    'inactive_7d',
    tr('Inactifs depuis 7 jours'),
    tr('Inscrits depuis plus de 7 jours')
  ),
];

/// Écrans accessibles depuis une notification ciblée : (chemin, libellé).
final campaignRoutes = [
  ('/accueil', tr('Accueil')),
  ('/coupons', tr('Coupons')),
  ('/matchs', tr('Matchs')),
  ('/assistant', tr('Assistant IA')),
  ('/abonnement', tr('Abonnement et crédits')),
  ('/carnet', tr('Carnet de paris')),
  ('/performances', tr('Performances')),
  ('/communaute', tr('Communauté')),
  ('/laboratoire', tr('Laboratoire')),
];

final campaignAudienceProvider =
    FutureProvider.autoDispose.family<int, String>((ref, segment) async {
  final res = await ref
      .watch(supabaseClientProvider)
      .rpc('admin_campaign_audience', params: {'p_segment': segment});
  return (res as num).toInt();
});

final campaignsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('push_campaigns')
      .select('id, segment, title, body, route, audience, created_at')
      .order('created_at', ascending: false)
      .limit(30);
  return rows;
});

/// Mots refusés par le serveur (mêmes règles que les visuels du studio).
final _forbidden = RegExp(
    r"(^|[^\p{L}\p{N}])(sûr(e|s|es)?|sûrement|garanti(e|es|s|r|t)?|assuré(e|s|es)?|certitudes?|imparables?|infaillibles?|sans risque|gains?|guaranteed?|guarantees|sure (bets?|wins?|thing)|risk[- ]free|winnings|unbeatable|can'?t lose|certaint(y|ies))([^\p{L}\p{N}]|$)|(^|[^\p{L}\p{N}])100 ?%",
    caseSensitive: false,
    unicode: true);

bool hasForbiddenWords(String text) => _forbidden.hasMatch(text);

/// Console → Notifications ciblées.
class CampaignsAdminScreen extends ConsumerStatefulWidget {
  const CampaignsAdminScreen({super.key});

  @override
  ConsumerState<CampaignsAdminScreen> createState() =>
      _CampaignsAdminScreenState();
}

class _CampaignsAdminScreenState extends ConsumerState<CampaignsAdminScreen> {
  String _segment = 'all';
  String _route = '/accueil';
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _titleEn = TextEditingController();
  final _bodyEn = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _titleEn.dispose();
    _bodyEn.dispose();
    super.dispose();
  }

  String? get _problem {
    final t = _title.text.trim(), b = _body.text.trim();
    if (t.length < 3 || t.length > 80) return tr('Titre : 3 à 80 caractères.');
    if (b.length < 3 || b.length > 300) {
      return tr('Message : 3 à 300 caractères.');
    }
    final te = _titleEn.text.trim(), be = _bodyEn.text.trim();
    if (te.isNotEmpty || be.isNotEmpty) {
      if (te.length < 3 || te.length > 80 || be.length < 3 || be.length > 300) {
        return tr(
            'Version anglaise : titre (3 à 80 caractères) et message (3 à 300), ou rien.');
      }
    }
    if (hasForbiddenWords('$t $b $te $be')) {
      return tr(
          'Mot interdit (sûr, garanti, assuré, gain, sans risque, 100 %…).');
    }
    return null;
  }

  Future<void> _send(int audience) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Envoyer la notification ?')),
        content: Text(trf(
            '{0} utilisateur{1} la recevront (sauf ceux qui ont coupé « Annonces et offres »). Trois envois par 24 heures au plus.',
            [audience, audience > 1 ? 's' : ''])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: Text(tr('Annuler'))),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(tr('Envoyer'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _sending = true);
    try {
      final n = await ref
          .read(supabaseClientProvider)
          .rpc('admin_send_campaign', params: {
        'p_segment': _segment,
        'p_title': _title.text.trim(),
        'p_body': _body.text.trim(),
        'p_route': _route,
        'p_title_en':
            _titleEn.text.trim().isEmpty ? null : _titleEn.text.trim(),
        'p_body_en': _bodyEn.text.trim().isEmpty ? null : _bodyEn.text.trim(),
      });
      ref.invalidate(campaignsProvider);
      if (mounted) {
        _title.clear();
        _body.clear();
        _titleEn.clear();
        _bodyEn.clear();
        showMessage(
            context, trf('Notification envoyée à {0} utilisateur(s).', [n]));
      }
    } on PostgrestException catch (e) {
      if (mounted) showMessage(context, tr(e.message), error: true);
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if (!perms.contains('campaigns.send')) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Notifications ciblées'))),
        body: InfoMessage(
            icon: Icons.lock_outline,
            title: tr('Écran réservé au super administrateur')),
      );
    }
    final theme = Theme.of(context);
    final audience = ref.watch(campaignAudienceProvider(_segment));
    final history = ref.watch(campaignsProvider);
    final problem = _problem;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Notifications ciblées'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          SectionTitle(tr('Destinataires')),
          Card(
            child: RadioGroup<String>(
              groupValue: _segment,
              onChanged: (v) => setState(() => _segment = v ?? 'all'),
              child: Column(
                children: [
                  for (final (code, label, desc) in campaignSegments)
                    RadioListTile<String>(
                      value: code,
                      title: Text(label),
                      subtitle: Text(desc),
                      dense: true,
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
                audience.when(
                    loading: () => tr('Calcul de l’audience…'),
                    error: (e, _) => userMessageFor(e),
                    data: (n) => trf('Audience : {0} utilisateur{1}',
                        [n, n > 1 ? 's' : ''])),
                style: theme.textTheme.titleSmall),
          ),
          SectionTitle(tr('Message')),
          TextField(
            controller: _title,
            maxLength: 80,
            decoration: InputDecoration(
                labelText: tr('Titre'), border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _body,
            maxLength: 300,
            maxLines: 3,
            decoration: InputDecoration(
                labelText: tr('Message'), border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          SectionTitle(tr('Version anglaise (facultative)')),
          Text(
              tr('Envoyée aux utilisateurs dont l’application est en anglais ; sans elle, ils reçoivent le français.'),
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: _titleEn,
            maxLength: 80,
            decoration: InputDecoration(
                labelText: tr('Titre en anglais'),
                border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bodyEn,
            maxLength: 300,
            maxLines: 3,
            decoration: InputDecoration(
                labelText: tr('Message en anglais'),
                border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          DropdownButtonFormField<String>(
            initialValue: _route,
            decoration: InputDecoration(
                labelText: tr('Écran ouvert au toucher'),
                border: OutlineInputBorder()),
            items: [
              for (final (path, label) in campaignRoutes)
                DropdownMenuItem(value: path, child: Text(label)),
            ],
            onChanged: (v) => setState(() => _route = v ?? '/accueil'),
          ),
          const SizedBox(height: 12),
          if (_title.text.trim().isNotEmpty || _body.text.trim().isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: Text(_title.text.trim()),
                subtitle: Text(_body.text.trim()),
              ),
            ),
          if (problem != null &&
              (_title.text.isNotEmpty || _body.text.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(problem,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          FilledButton.icon(
            onPressed: _sending ||
                    problem != null ||
                    audience.valueOrNull == null ||
                    audience.valueOrNull == 0
                ? null
                : () => _send(audience.valueOrNull!),
            icon: const Icon(Icons.send_outlined),
            label: Text(tr('Envoyer')),
          ),
          const SizedBox(height: 6),
          Text(
              tr('Reçue dans la boîte de l’app et sur le téléphone (heures calmes respectées), sauf pour les utilisateurs qui ont coupé « Annonces et offres ». Chaque envoi est inscrit au journal d’audit.'),
              style: theme.textTheme.bodySmall),
          SectionTitle(tr('Derniers envois')),
          ...history.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(userMessageFor(e))],
            data: (list) => list.isEmpty
                ? [Text(tr('Aucun envoi pour le moment.'))]
                : [
                    for (final c in list)
                      Card(
                        child: ListTile(
                          title: Text('${c['title']}'),
                          subtitle:
                              Text(trf('{0}\n{1} · {2} destinataires · {3}', [
                            c['body'],
                            campaignSegments
                                .firstWhere((s) => s.$1 == c['segment'],
                                    orElse: () => (
                                          c['segment'] as String,
                                          c['segment'] as String,
                                          ''
                                        ))
                                .$2,
                            c['audience'],
                            _when(DateTime.parse(c['created_at'] as String)
                                .toLocal())
                          ])),
                          isThreeLine: true,
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  static String _when(DateTime d) =>
      trf('{0} à {1}', [shortDate(d), timeLabel(d)]);
}
