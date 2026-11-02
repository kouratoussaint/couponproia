import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Alerte d'exploitation (ouverte ou close).
class OpsAlert {
  const OpsAlert(
      {required this.id,
      required this.severity,
      required this.title,
      required this.body,
      required this.openedAt,
      this.route,
      this.resolvedAt,
      this.emailedAt});

  factory OpsAlert.fromJson(Map<String, dynamic> j) => OpsAlert(
        id: (j['id'] as num).toInt(),
        severity: j['severity'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        route: j['route'] as String?,
        openedAt: DateTime.parse(j['opened_at'] as String).toLocal(),
        resolvedAt: j['resolved_at'] == null
            ? null
            : DateTime.parse(j['resolved_at'] as String).toLocal(),
        emailedAt: j['emailed_at'] == null
            ? null
            : DateTime.parse(j['emailed_at'] as String).toLocal(),
      );

  final int id;
  final String severity;
  final String title;
  final String body;
  final String? route;
  final DateTime openedAt;
  final DateTime? resolvedAt;
  final DateTime? emailedAt;

  bool get critical => severity == 'critical';
}

/// Plantage ou lenteur regroupé par empreinte.
class ClientError {
  const ClientError(
      {required this.id,
      required this.kind,
      required this.message,
      required this.occurrences,
      required this.users,
      required this.lastSeen,
      required this.firstSeen,
      this.stack,
      this.context,
      this.version,
      this.os,
      this.resolvedAt});

  factory ClientError.fromJson(Map<String, dynamic> j) => ClientError(
        id: (j['id'] as num).toInt(),
        kind: j['kind'] as String,
        message: j['message'] as String,
        stack: j['stack'] as String?,
        context: j['context'] as String?,
        version: j['app_version'] as String?,
        os: j['os'] as String?,
        occurrences: (j['occurrences'] as num).toInt(),
        users: (j['user_ids'] as List? ?? const []).length,
        firstSeen: DateTime.parse(j['first_seen'] as String).toLocal(),
        lastSeen: DateTime.parse(j['last_seen'] as String).toLocal(),
        resolvedAt: j['resolved_at'] == null
            ? null
            : DateTime.parse(j['resolved_at'] as String).toLocal(),
      );

  final int id;
  final String kind;
  final String message;
  final String? stack;
  final String? context;
  final String? version;
  final String? os;
  final int occurrences;
  final int users;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final DateTime? resolvedAt;
}

final opsAlertsProvider =
    FutureProvider.autoDispose<List<OpsAlert>>((ref) async {
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('ops_alerts')
      .select()
      .order('opened_at', ascending: false)
      .limit(60);
  return rows.map(OpsAlert.fromJson).toList();
});

final clientErrorsProvider =
    FutureProvider.autoDispose<List<ClientError>>((ref) async {
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('client_errors')
      .select(
          'id, kind, message, stack, context, app_version, os, occurrences, user_ids, first_seen, last_seen, resolved_at')
      .order('last_seen', ascending: false)
      .limit(100);
  return rows.map(ClientError.fromJson).toList();
});

/// Alertes ouvertes (compteur de la console).
final openOpsAlertsProvider = FutureProvider.autoDispose<int>((ref) async {
  final list = await ref.watch(opsAlertsProvider.future);
  return list.where((a) => a.resolvedAt == null).length;
});

String _when(DateTime d) => trf('{0} à {1}', [shortDate(d), timeLabel(d)]);

/// Console → Santé de l'application : alertes d'exploitation, plantages et lenteurs.
class HealthAdminScreen extends ConsumerStatefulWidget {
  const HealthAdminScreen({super.key});

  @override
  ConsumerState<HealthAdminScreen> createState() => _HealthAdminScreenState();
}

class _HealthAdminScreenState extends ConsumerState<HealthAdminScreen> {
  bool _scanning = false;
  bool _sendingReport = false;
  bool _showResolvedErrors = false;

  /// Aperçu du rapport hebdomadaire, envoyé à votre seule adresse.
  Future<void> _previewWeekly() async {
    setState(() => _sendingReport = true);
    try {
      final res = await ref
          .read(supabaseClientProvider)
          .functions
          .invoke('weekly-report', body: const {'preview': true});
      final d = Map<String, dynamic>.from(res.data as Map);
      if (mounted) {
        showMessage(
            context,
            (d['sent'] as num? ?? 0) > 0
                ? tr('Aperçu du rapport hebdomadaire envoyé à votre adresse.')
                : trf('Envoi impossible : {0}',
                    [d['error'] ?? tr('adresse non confirmée')]),
            error: (d['sent'] as num? ?? 0) == 0);
      }
    } on FunctionException catch (e) {
      if (mounted) {
        showMessage(
            context,
            e.status == 503
                ? tr('E-mail non configuré (secrets SMTP).')
                : trf('Envoi impossible ({0}).', [e.status]),
            error: true);
      }
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _sendingReport = false);
    }
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final res = await ref
          .read(supabaseClientProvider)
          .functions
          .invoke('ops-monitor', body: const {});
      final d = Map<String, dynamic>.from(res.data as Map);
      ref.invalidate(opsAlertsProvider);
      if (mounted) {
        final mail = d['smtp'] == true
            ? (d['emailed'] as num? ?? 0) > 0
                ? tr(' E-mail envoyé.')
                : d['email_error'] != null
                    ? trf(' E-mail impossible : {0}', [d['email_error']])
                    : ''
            : tr(' (e-mail non configuré)');
        showMessage(
            context,
            trf('Contrôle terminé : {0} nouvelle(s), {1} close(s), {2} en cours.{3}',
                [d['opened'], d['resolved'], d['open'], mail]));
      }
    } on FunctionException catch (e) {
      if (mounted) {
        showMessage(context, trf('Contrôle impossible ({0}).', [e.status]),
            error: true);
      }
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if (!perms.contains('ops.monitor')) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Santé de l’application'))),
        body: InfoMessage(
            icon: Icons.lock_outline,
            title: tr('Écran réservé au super administrateur')),
      );
    }
    final theme = Theme.of(context);
    final alerts = ref.watch(opsAlertsProvider);
    final errors = ref.watch(clientErrorsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Santé de l’application'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(opsAlertsProvider);
          ref.invalidate(clientErrorsProvider);
          await ref.read(opsAlertsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            Text(
                tr('Contrôle automatique toutes les 15 minutes : synchronisations, quota API-Football, IA, publication des coupons, paiements, notifications, fonctions planifiées et plantages. Vous êtes prévenu par notification (et par e-mail si un SMTP est configuré) ; une alerte se ferme d’elle-même quand le problème disparaît.'),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: _scanning ? null : _scan,
                icon: _scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.health_and_safety_outlined),
                label: Text(tr('Lancer un contrôle maintenant')),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _sendingReport ? null : _previewWeekly,
                icon: const Icon(Icons.mark_email_read_outlined),
                label: Text(tr('M’envoyer un aperçu du rapport hebdomadaire')),
              ),
            ),
            ...alerts.when(
              loading: () => [const LinearProgressIndicator()],
              error: (e, _) => [Text(userMessageFor(e))],
              data: (list) {
                final open = list.where((a) => a.resolvedAt == null).toList();
                final closed =
                    list.where((a) => a.resolvedAt != null).take(15).toList();
                return [
                  SectionTitle(trf('Alertes en cours ({0})', [open.length])),
                  if (open.isEmpty)
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.check_circle,
                            color: theme.colorScheme.primary),
                        title: Text(tr('Tout fonctionne')),
                        subtitle: Text(tr('Aucune alerte ouverte.')),
                      ),
                    ),
                  for (final a in open) _AlertCard(alert: a),
                  if (closed.isNotEmpty) ...[
                    SectionTitle(tr('Alertes closes récemment')),
                    for (final a in closed) _AlertCard(alert: a),
                  ],
                ];
              },
            ),
            SectionTitle(tr('Plantages et lenteurs'),
                trailing: FilterChip(
                  label: Text(tr('Résolus')),
                  selected: _showResolvedErrors,
                  onSelected: (v) => setState(() => _showResolvedErrors = v),
                )),
            ...errors.when(
              loading: () => [const LinearProgressIndicator()],
              error: (e, _) => [Text(userMessageFor(e))],
              data: (list) {
                final shown = list
                    .where((e) => (e.resolvedAt != null) == _showResolvedErrors)
                    .toList();
                if (shown.isEmpty) {
                  return [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.bug_report_outlined),
                        title: Text(_showResolvedErrors
                            ? tr('Aucun problème résolu')
                            : tr('Aucun plantage ni lenteur à traiter')),
                      ),
                    )
                  ];
                }
                return [for (final e in shown) _ErrorTile(error: e)];
              },
            ),
            const SizedBox(height: 8),
            Text(
                tr('Les rapports arrivent des téléphones connectés dont l’utilisateur n’a pas désactivé les rapports d’erreurs (Profil). Ils ne contiennent ni coupon, ni montant, ni message personnel.'),
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final OpsAlert alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = alert;
    final open = a.resolvedAt == null;
    final color = !open
        ? scheme.outline
        : a.critical
            ? scheme.error
            : BrandColors.orange;
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withValues(alpha: open ? 0.8 : 0.3))),
      child: ListTile(
        leading: Icon(
            open
                ? (a.critical
                    ? Icons.error_outline
                    : Icons.warning_amber_rounded)
                : Icons.check_circle_outline,
            color: color),
        title: Text(a.title),
        subtitle: Text([
          a.body,
          open
              ? trf('Depuis le {0}{1}', [
                  _when(a.openedAt),
                  a.emailedAt != null ? tr(' · e-mail envoyé') : ''
                ])
              : trf('Du {0} au {1}', [_when(a.openedAt), _when(a.resolvedAt!)]),
        ].join('\n')),
        isThreeLine: true,
        trailing: open && a.route != null
            ? IconButton(
                tooltip: tr('Ouvrir'),
                icon: const Icon(Icons.chevron_right),
                onPressed: () => context.push(a.route!),
              )
            : null,
      ),
    );
  }
}

class _ErrorTile extends ConsumerWidget {
  const _ErrorTile({required this.error});

  final ClientError error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = error;
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = e.kind == 'slow'
        ? (Icons.hourglass_bottom, BrandColors.orange)
        : (Icons.bug_report_outlined, scheme.error);
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(e.message, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle:
            Text(trf('{0} fois · {1} utilisateur{2}{3} · dernier {4}{5}', [
          e.occurrences,
          e.users,
          e.users > 1 ? 's' : '',
          e.version == null ? '' : trf(' · v{0}', [e.version]),
          _when(e.lastSeen),
          e.context == null ? '' : '\n${e.context}'
        ])),
        onTap: () => _details(context, ref),
      ),
    );
  }

  Future<void> _details(BuildContext context, WidgetRef ref) async {
    final e = error;
    final resolve = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(e.kind == 'slow' ? tr('Lenteur') : tr('Plantage')),
        content: SingleChildScrollView(
          child: SelectableText([
            e.message,
            '',
            trf('Écran ou requête : {0}', [e.context ?? '—']),
            trf('Version : {0} · {1}', [e.version ?? '—', e.os ?? '—']),
            trf('Première fois : {0} · dernière : {1}',
                [_when(e.firstSeen), _when(e.lastSeen)]),
            if (e.stack != null) ...['', e.stack!],
          ].join('\n')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: Text(tr('Fermer'))),
          FilledButton(
              onPressed: () => Navigator.pop(d, e.resolvedAt == null),
              child: Text(e.resolvedAt == null
                  ? tr('Marquer comme résolu')
                  : tr('Rouvrir'))),
        ],
      ),
    );
    if (resolve == null || !context.mounted) return;
    try {
      await ref.read(supabaseClientProvider).rpc('admin_resolve_client_error',
          params: {'p_id': e.id, 'p_resolved': resolve});
      ref.invalidate(clientErrorsProvider);
    } catch (err) {
      if (context.mounted) {
        showMessage(context, userMessageFor(err), error: true);
      }
    }
  }
}
