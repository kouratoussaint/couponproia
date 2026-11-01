import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';

/// Segments d'utilisateurs : (code, libellé, description).
const campaignSegments = [
  ('all', 'Tous les utilisateurs', 'Comptes actifs (non suspendus)'),
  ('free', 'Sans forfait payant', 'Forfait FREE aujourd’hui'),
  ('paying', 'Forfait payant en cours', 'STARTER, PRO TIPSTER, BUSINESS'),
  ('expiring', 'Forfait qui se termine', 'Dans les 7 jours, sans prolongation'),
  ('expired', 'Forfait terminé récemment', 'Depuis moins de 30 jours'),
  ('never_paid', 'N’ont jamais payé', 'Aucun achat réussi'),
  ('inactive_7d', 'Inactifs depuis 7 jours', 'Inscrits depuis plus de 7 jours'),
];

/// Écrans accessibles depuis une notification ciblée : (chemin, libellé).
const campaignRoutes = [
  ('/accueil', 'Accueil'),
  ('/coupons', 'Coupons'),
  ('/matchs', 'Matchs'),
  ('/assistant', 'Assistant IA'),
  ('/abonnement', 'Abonnement et crédits'),
  ('/carnet', 'Carnet de paris'),
  ('/performances', 'Performances'),
  ('/communaute', 'Communauté'),
  ('/laboratoire', 'Laboratoire'),
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
    r'(^|[^\p{L}\p{N}])(sûr(e|s|es)?|sûrement|garanti(e|es|s|r|t)?|assuré(e|s|es)?|certitudes?|imparables?|infaillibles?|sans risque|gains?)([^\p{L}\p{N}]|$)|(^|[^\p{L}\p{N}])100 ?%',
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
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  String? get _problem {
    final t = _title.text.trim(), b = _body.text.trim();
    if (t.length < 3 || t.length > 80) return 'Titre : 3 à 80 caractères.';
    if (b.length < 3 || b.length > 300) return 'Message : 3 à 300 caractères.';
    if (hasForbiddenWords('$t $b')) {
      return 'Mot interdit (sûr, garanti, assuré, gain, sans risque, 100 %…).';
    }
    return null;
  }

  Future<void> _send(int audience) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Envoyer la notification ?'),
        content: Text(
            '$audience utilisateur${audience > 1 ? 's' : ''} la recevront (sauf ceux qui ont coupé « Annonces et offres »). '
            'Trois envois par 24 heures au plus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Envoyer')),
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
      });
      ref.invalidate(campaignsProvider);
      if (mounted) {
        _title.clear();
        _body.clear();
        showMessage(context, 'Notification envoyée à $n utilisateur(s).');
      }
    } on PostgrestException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
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
        appBar: AppBar(title: const Text('Notifications ciblées')),
        body: const InfoMessage(
            icon: Icons.lock_outline,
            title: 'Écran réservé au super administrateur'),
      );
    }
    final theme = Theme.of(context);
    final audience = ref.watch(campaignAudienceProvider(_segment));
    final history = ref.watch(campaignsProvider);
    final problem = _problem;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications ciblées')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          const SectionTitle('Destinataires'),
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
                    loading: () => 'Calcul de l’audience…',
                    error: (e, _) => userMessageFor(e),
                    data: (n) =>
                        'Audience : $n utilisateur${n > 1 ? 's' : ''}'),
                style: theme.textTheme.titleSmall),
          ),
          const SectionTitle('Message'),
          TextField(
            controller: _title,
            maxLength: 80,
            decoration: const InputDecoration(
                labelText: 'Titre', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _body,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Message', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          DropdownButtonFormField<String>(
            initialValue: _route,
            decoration: const InputDecoration(
                labelText: 'Écran ouvert au toucher',
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
            label: const Text('Envoyer'),
          ),
          const SizedBox(height: 6),
          Text(
              'Reçue dans la boîte de l’app et sur le téléphone (heures calmes respectées), sauf pour les utilisateurs '
              'qui ont coupé « Annonces et offres ». Chaque envoi est inscrit au journal d’audit.',
              style: theme.textTheme.bodySmall),
          const SectionTitle('Derniers envois'),
          ...history.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(userMessageFor(e))],
            data: (list) => list.isEmpty
                ? [const Text('Aucun envoi pour le moment.')]
                : [
                    for (final c in list)
                      Card(
                        child: ListTile(
                          title: Text('${c['title']}'),
                          subtitle: Text(
                              '${c['body']}\n${campaignSegments.firstWhere((s) => s.$1 == c['segment'], orElse: () => (
                                    c['segment'] as String,
                                    c['segment'] as String,
                                    ''
                                  )).$2} · ${c['audience']} destinataires · ${_when(DateTime.parse(c['created_at'] as String).toLocal())}'),
                          isThreeLine: true,
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  static String _when(DateTime d) => '${shortDate(d)} à ${timeLabel(d)}';
}
