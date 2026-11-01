// Simulateur de mise : calculs purs (aucun pari n'est placé, aucune donnée n'est inventée).
// Les cotes viennent des coupons, des analyses ou des relevés ; la probabilité est celle du
// modèle quand elle existe, jamais une valeur fabriquée.

/// Une sélection simulée.
class SimLeg {
  const SimLeg({
    required this.matchId,
    required this.key,
    required this.matchLabel,
    required this.pick,
    required this.odd,
    this.kickoffAt,
    this.currentOdd,
    this.probability,
  });

  final int matchId;
  final String key;
  final String matchLabel;
  final String pick;

  /// Cote publiée (coupon) ou relevée (match, analyse).
  final double odd;
  final DateTime? kickoffAt;

  /// Cote médiane actuelle, si elle a été relevée depuis.
  final double? currentOdd;

  /// Estimation du modèle (0–1), si elle existe.
  final double? probability;
}

/// Ce que l'on simule : un coupon, un match ou une analyse.
class SimInput {
  const SimInput({
    required this.title,
    required this.legs,
    required this.sourceType,
    this.sourceId,
    this.totalOdd,
    this.probability,
  });

  final String title;
  final List<SimLeg> legs;

  /// coupon, user_coupon, match, analysis, lab (pour le carnet de paris).
  final String sourceType;
  final String? sourceId;

  /// Cote totale publiée (coupon) ; sinon produit des cotes.
  final double? totalOdd;

  /// Probabilité combinée publiée ; sinon produit des estimations si toutes sont connues.
  final double? probability;

  double get odd =>
      _round2(totalOdd ?? legs.fold<double>(1, (p, l) => p * l.odd));

  /// Cote totale avec les cotes actuelles, si au moins une a bougé ; sinon null.
  double? get currentOdd {
    if (!legs.any((l) => l.currentOdd != null && l.currentOdd != l.odd)) {
      return null;
    }
    final ratio =
        legs.fold<double>(1, (p, l) => p * ((l.currentOdd ?? l.odd) / l.odd));
    return _round2(odd * ratio);
  }

  double? get estimatedProbability {
    if (probability != null) return probability;
    if (legs.isEmpty || legs.any((l) => l.probability == null)) return null;
    return legs.fold<double>(1, (p, l) => p * l.probability!);
  }

  /// Cote du coupon si la sélection [index] est annulée (elle compte alors pour 1,00).
  double oddWithoutLeg(int index) => _round2(_max1(odd / legs[index].odd));
}

double _round2(double v) => (v * 100).roundToDouble() / 100;
double _max1(double v) => v < 1 ? 1 : v;

/// Résultat d'une mise : retour si tout passe (prélèvement déduit), résultat net.
class StakeOutcome {
  const StakeOutcome(
      {required this.stake,
      required this.odd,
      required this.gross,
      required this.withholding,
      required this.payout});

  final int stake;
  final double odd;

  /// Mise × cote.
  final int gross;

  /// Prélèvement de l'opérateur sur le bénéfice (0 si aucun).
  final int withholding;

  /// Retour potentiel : ce que l'on récupère si toutes les sélections passent.
  final int payout;

  /// Résultat net si tout passe.
  int get net => payout - stake;
}

StakeOutcome simulate(int stake, double odd, {double withholdingPercent = 0}) {
  final gross = (stake * odd).round();
  final profit = gross - stake;
  final tax = profit > 0 ? (profit * withholdingPercent / 100).round() : 0;
  return StakeOutcome(
      stake: stake,
      odd: odd,
      gross: gross,
      withholding: tax,
      payout: gross - tax);
}

/// Valeur moyenne estimée d'une mise selon le modèle : p × retour − mise.
/// Une estimation, souvent négative : c'est la marge des opérateurs.
int expectedValue(int stake, double odd, double probability,
        {double withholdingPercent = 0}) =>
    (probability *
                simulate(stake, odd, withholdingPercent: withholdingPercent)
                    .payout -
            stake)
        .round();

/// Mises du tableau comparatif autour de la mise choisie.
List<int> comparisonStakes(int stake) {
  const base = [500, 1000, 2000, 5000, 10000];
  if (base.contains(stake) || stake <= 0) return base;
  final list = {...base, stake}.toList()..sort();
  return list;
}

/// Montant avec espaces de milliers : « 12 500 FCFA ».
String money(num amount, {String currency = 'FCFA'}) {
  final negative = amount < 0;
  final s = amount.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  final sign = negative ? '−' : '';
  return currency.isEmpty ? '$sign$b' : '$sign$b $currency';
}

/// Montant signé : « +2 500 FCFA », « −1 000 FCFA ».
String signedMoney(num amount, {String currency = 'FCFA'}) => amount > 0
    ? '+${money(amount, currency: currency)}'
    : money(amount, currency: currency);

/// Saisie d'une mise : chiffres uniquement (espaces tolérés), sinon null.
int? parseStake(String text) {
  final digits = text.replaceAll(RegExp(r'[\s  .]'), '');
  if (digits.isEmpty || !RegExp(r'^\d{1,9}$').hasMatch(digits)) return null;
  final v = int.parse(digits);
  return v > 0 ? v : null;
}
