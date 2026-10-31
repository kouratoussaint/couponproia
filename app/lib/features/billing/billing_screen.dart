import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/error_messages.dart';
import '../../core/widgets/form_widgets.dart';
import '../assistant/data/assistant_repository.dart';
import '../matches/data/sports_format.dart';
import '../matches/presentation/sports_widgets.dart';
import '../system/system_providers.dart';
import 'billing_repository.dart';

String fcfa(int amount) {
  final s = amount.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b FCFA';
}

const _statusLabels = {
  'pending': 'En attente',
  'succeeded': 'Confirmé',
  'failed': 'Échoué',
  'cancelled': 'Abandonné',
  'refunded': 'Remboursé'
};

/// Abonnement et crédits : forfaits (mensuel ou annuel), packs de crédits, paiement Mobile Money
/// dans la page de l'opérateur, puis vérification par le serveur avant tout droit accordé.
class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen>
    with WidgetsBindingObserver {
  bool _annual = false;
  int _packs = 1;
  bool _busy = false;
  String? _pendingPaymentId;
  final _promoCtrl = TextEditingController();
  PromoQuote? _promo;
  bool _checkingPromo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _promoCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour dans l'app après la page de paiement : vérification automatique.
    if (state == AppLifecycleState.resumed &&
        _pendingPaymentId != null &&
        !_busy) {
      _verify();
    }
  }

  void _refreshAll() {
    ref.invalidate(entitlementsProvider);
    ref.invalidate(paymentsProvider);
    ref.invalidate(myCreditsProvider);
  }

  Future<void> _pay(
      Future<({String paymentId, String paymentUrl})> Function()
          checkout) async {
    setState(() => _busy = true);
    try {
      final r = await checkout();
      _pendingPaymentId = r.paymentId;
      final ok = await launchUrl(Uri.parse(r.paymentUrl),
          mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showMessage(context, 'Impossible d’ouvrir la page de paiement.',
            error: true);
      }
    } catch (e) {
      if (mounted) {
        showMessage(
            context, e is BillingException ? e.message : userMessageFor(e),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _checkingPromo = true);
    try {
      final q = await ref.read(billingRepositoryProvider).checkPromo(code);
      if (!mounted) return;
      setState(() => _promo = q);
      showMessage(context, 'Code ${q.code} appliqué : −${q.percentOff} %.');
    } catch (e) {
      if (mounted) {
        showMessage(
            context, e is BillingException ? e.message : userMessageFor(e),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _checkingPromo = false);
    }
  }

  Future<void> _verify() async {
    final id = _pendingPaymentId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      var status = 'pending';
      for (var attempt = 0; attempt < 6 && status == 'pending'; attempt++) {
        if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 5));
        status = await ref.read(billingRepositoryProvider).status(id);
      }
      _refreshAll();
      if (!mounted) return;
      switch (status) {
        case 'succeeded':
          _pendingPaymentId = null;
          showMessage(context, 'Paiement confirmé : votre achat est actif.');
        case 'failed':
        case 'cancelled':
          _pendingPaymentId = null;
          showMessage(context,
              'Paiement non abouti : aucun montant n’a été pris en compte.',
              error: true);
        default:
          showMessage(context,
              'Paiement pas encore confirmé par l’opérateur. Il sera vérifié automatiquement ; revenez dans quelques minutes.');
      }
    } catch (e) {
      if (mounted) {
        showMessage(
            context, e is BillingException ? e.message : userMessageFor(e),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(publicSettingsProvider).valueOrNull ??
        const <String, dynamic>{};
    final ent = ref.watch(entitlementsProvider);
    final payments = ref.watch(paymentsProvider);
    final plans = [
      for (final p in (settings['pricing.plans'] as List? ?? const []))
        PlanOffer.fromJson(Map<String, dynamic>.from(p as Map)),
    ];
    final discount =
        (settings['pricing.annual_discount_percent'] as num?)?.toInt() ?? 0;
    final pack = settings['pricing.credit_pack'] is Map
        ? Map<String, dynamic>.from(settings['pricing.credit_pack'] as Map)
        : null;
    final maxPacks =
        (settings['pricing.credit_pack_max_quantity'] as num?)?.toInt() ?? 5;
    final current = ent.valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Abonnement et crédits')),
      body: RefreshIndicator(
        onRefresh: () async => _refreshAll(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            if (_busy) const LinearProgressIndicator(),
            ent.when(
              loading: () => const SizedBox(height: 4),
              error: (e, _) => Text(userMessageFor(e)),
              data: (e) => Card(
                child: ListTile(
                  leading: Icon(Icons.workspace_premium,
                      color: theme.colorScheme.primary),
                  title: Text('Forfait ${e.plan.replaceAll('_', ' ')}'),
                  subtitle: Text(
                    [
                      if (e.periodEnd != null)
                        'Actif jusqu’au ${shortDate(e.periodEnd!)}/${e.periodEnd!.year}',
                      'Crédits IA : ${e.credits.label}',
                    ].join(' · '),
                  ),
                ),
              ),
            ),
            if (_pendingPaymentId != null)
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.hourglass_top),
                  title: const Text('Paiement en cours de confirmation'),
                  subtitle: const Text(
                      'Après avoir validé sur votre téléphone, revenez ici.'),
                  trailing: TextButton(
                      onPressed: _busy ? null : _verify,
                      child: const Text('Vérifier')),
                ),
              ),
            _PromoCard(
              controller: _promoCtrl,
              promo: _promo,
              busy: _checkingPromo || _busy,
              onApply: _applyPromo,
              onClear: () => setState(() {
                _promo = null;
                _promoCtrl.clear();
              }),
            ),
            const SectionTitle('Forfaits'),
            SegmentedButton<bool>(
              segments: [
                const ButtonSegment(value: false, label: Text('Mensuel')),
                ButtonSegment(
                    value: true,
                    label: Text(
                        discount > 0 ? 'Annuel (−$discount %)' : 'Annuel')),
              ],
              selected: {_annual},
              onSelectionChanged: (s) => setState(() => _annual = s.first),
            ),
            const SizedBox(height: 8),
            for (final p in plans)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(p.name,
                                  style: theme.textTheme.titleMedium)),
                          _Price(
                            label: p.monthlyXof == 0
                                ? 'Gratuit'
                                : '${fcfa(p.priceFor(annual: _annual, discountPercent: discount))} / ${_annual ? 'an' : 'mois'}',
                            promoLabel: p.monthlyXof > 0 &&
                                    _promo != null &&
                                    _promo!.appliesToPlan(p.code)
                                ? '${fcfa(_promo!.discounted(p.priceFor(annual: _annual, discountPercent: discount)))} / ${_annual ? 'an' : 'mois'}'
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('• ${p.aiCredits} crédits IA par mois (assistant)'),
                      Text(p.allCoupons
                          ? '• Tous les coupons de la plateforme avant le coup d’envoi'
                          : '• Le coupon du jour avant le coup d’envoi'),
                      if (p.analysesPerDay != null)
                        Text(
                            '• ${p.analysesPerDay} analyses IA de match par jour'),
                      if (p.monthlyXof > 0) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: _busy
                                ? null
                                : () => _pay(() => ref
                                    .read(billingRepositoryProvider)
                                    .checkoutPlan(p.code,
                                        annual: _annual,
                                        promoCode: _promo != null &&
                                                _promo!.appliesToPlan(p.code)
                                            ? _promo!.code
                                            : null)),
                            child: Text(current?.plan == p.code
                                ? 'Prolonger'
                                : 'Choisir'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (pack != null) ...[
              const SectionTitle('Crédits IA supplémentaires'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      IconButton(
                          onPressed: _packs > 1
                              ? () => setState(() => _packs--)
                              : null,
                          icon: const Icon(Icons.remove)),
                      Text('$_packs', style: theme.textTheme.titleMedium),
                      IconButton(
                          onPressed: _packs < maxPacks
                              ? () => setState(() => _packs++)
                              : null,
                          icon: const Icon(Icons.add)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${(pack['credits'] as num).toInt() * _packs} crédits · ${fcfa(_promo != null && _promo!.appliesToCredits ? _promo!.discounted((pack['price_xof'] as num).toInt() * _packs) : (pack['price_xof'] as num).toInt() * _packs)}',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _pay(() => ref
                                .read(billingRepositoryProvider)
                                .checkoutCredits(_packs,
                                    promoCode: _promo != null &&
                                            _promo!.appliesToCredits
                                        ? _promo!.code
                                        : null)),
                        child: const Text('Acheter'),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                  'Les crédits achetés n’expirent pas à la fin du mois ; ceux du forfait se renouvellent chaque mois.',
                  style: theme.textTheme.bodySmall),
            ],
            const SectionTitle('Historique des paiements'),
            payments.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(userMessageFor(e)),
              data: (list) => list.isEmpty
                  ? Text('Aucun paiement.', style: theme.textTheme.bodyMedium)
                  : Card(
                      child: Column(
                        children: [
                          for (final p in list)
                            ListTile(
                              dense: true,
                              title: Text(p.kind == 'subscription'
                                  ? 'Forfait ${p.planCode?.replaceAll('_', ' ')} · ${p.period == 'annual' ? '12 mois' : '1 mois'}'
                                  : '${p.credits} crédits IA'),
                              subtitle: Text(
                                  '${shortDate(p.createdAt)}/${p.createdAt.year} · ${fcfa(p.amountXof)}${p.promoCode != null ? ' · code ${p.promoCode}' : ''}'),
                              trailing:
                                  Text(_statusLabels[p.status] ?? p.status),
                            ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              'Paiement Orange Money ou Moov Money via CinetPay. Votre abonnement ou vos crédits ne sont activés qu’après '
              'confirmation de l’opérateur, vérifiée par notre serveur. Coupon Pro IA vend un service d’analyse : aucun '
              'pari n’est pris et aucun gain n’est garanti.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Price extends StatelessWidget {
  const _Price({required this.label, this.promoLabel});

  final String label;
  final String? promoLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final main =
        theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary);
    if (promoLabel == null) return Text(label, style: main);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant)),
        Text(promoLabel!, style: main),
      ],
    );
  }
}

/// Saisie d'un code promo : vérifié par le serveur, puis réappliqué par lui au paiement.
class _PromoCard extends StatelessWidget {
  const _PromoCard({
    required this.controller,
    required this.promo,
    required this.busy,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController controller;
  final PromoQuote? promo;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = promo;
    if (q != null) {
      final scope = switch (q.appliesTo) {
        'subscription' => q.planCodes.isEmpty
            ? 'sur les forfaits'
            : 'sur ${q.planCodes.map((c) => c.replaceAll('_', ' ')).join(', ')}',
        'credits' => 'sur les crédits IA',
        _ => 'sur tous les achats',
      };
      return Card(
        color: theme.colorScheme.primaryContainer,
        child: ListTile(
          leading: Icon(Icons.local_offer_outlined,
              color: theme.colorScheme.onPrimaryContainer),
          title: Text('Code ${q.code} : −${q.percentOff} % $scope'),
          subtitle: Text([
            if (q.description.isNotEmpty) q.description,
            if (q.endsAt != null)
              'Valable jusqu’au ${shortDate(q.endsAt!)}/${q.endsAt!.year}',
            'Une seule utilisation par compte.',
          ].join(' · ')),
          trailing: IconButton(
              tooltip: 'Retirer le code',
              onPressed: onClear,
              icon: const Icon(Icons.close)),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Code promo',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.local_offer_outlined),
                ),
                onSubmitted: (_) => onApply(),
              ),
            ),
            TextButton(
                onPressed: busy ? null : onApply,
                child: const Text('Appliquer')),
          ],
        ),
      ),
    );
  }
}
