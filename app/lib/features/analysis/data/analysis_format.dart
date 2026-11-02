import 'analysis_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// « 53 % » à partir de 0,532.
String pct(double p) => percentLabel((p * 100).round());

/// Écart modèle − marché en points : « +4 pts », « −2 pts ».
String edgePoints(double edge) {
  final pts = (edge * 100).round();
  if (pts == 0) return tr('0 pt');
  return trf('{0}{1} pts', [pts > 0 ? '+' : '−', pts.abs()]);
}

String decimal(double x, [int digits = 2]) =>
    x.toStringAsFixed(digits).replaceAll('.', decimalSeparator);

/// Libellé lisible d'une issue (« 1X2.HOME », « OU.OVER.2.5 »…) avec le nom des équipes.
String outcomeKeyLabel(String key, String home, String away) {
  final parts = key.split('.');
  final market = parts.first;
  final outcome = parts.length > 1 ? parts[1] : '';
  final line = parts.length > 2
      ? parts.sublist(2).join('.').replaceAll('.', decimalSeparator)
      : '';
  switch (market) {
    case '1X2':
      return switch (outcome) {
        'HOME' => trf('Victoire {0}', [home]),
        'DRAW' => tr('Match nul'),
        'AWAY' => trf('Victoire {0}', [away]),
        _ => key,
      };
    case 'DC':
      return switch (outcome) {
        '1X' => trf('{0} ou nul', [home]),
        '12' => trf('{0} ou {1}', [home, away]),
        'X2' => trf('Nul ou {0}', [away]),
        _ => key,
      };
    case 'OU':
      return outcome == 'OVER'
          ? trf('Plus de {0} buts', [line])
          : trf('Moins de {0} buts', [line]);
    case 'BTTS':
      return outcome == 'YES'
          ? tr('Les deux équipes marquent')
          : tr('Au moins une équipe ne marque pas');
    case 'DNB':
      return switch (outcome) {
        'HOME' => trf('{0} (remboursé si nul)', [home]),
        'AWAY' => trf('{0} (remboursé si nul)', [away]),
        _ => key,
      };
    case 'TTH' || 'TTA':
      final team = market == 'TTH' ? home : away;
      final s = line == '0,5' ? '' : 's';
      return outcome == 'OVER'
          ? trf('{0} : plus de {1} but{2}', [team, line, s])
          : trf('{0} : moins de {1} but{2}', [team, line, s]);
  }
  return key;
}

String reliabilityLabel(Reliability r) => switch (r) {
      Reliability.faible => tr('Fiabilité faible'),
      Reliability.moyenne => tr('Fiabilité moyenne'),
      Reliability.bonne => tr('Fiabilité bonne'),
    };

String reliabilityExplanation(AnalysisFiche f) => trf(
    'Basée sur {0} match(s) à domicile de l’équipe qui reçoit et {1} à l’extérieur de l’équipe visiteuse cette saison.',
    [f.homeTeamHomeMatches, f.awayTeamAwayMatches]);

/// Pourquoi le texte de l'IA est absent.
String statsOnlyReason(String? reason) => switch (reason) {
      'no_provider' => tr(
          'L’analyse rédigée par l’IA n’est pas encore activée. Voici la fiche statistique.'),
      'validation_failed' => tr(
          'Le texte proposé par l’IA n’a pas passé nos contrôles (chiffres vérifiés, aucune promesse de gain). Voici la fiche statistique seule.'),
      'provider_error' => tr(
          'Le service d’IA est momentanément indisponible. Voici la fiche statistique seule.'),
      _ => tr('Voici la fiche statistique calculée par le moteur.'),
    };

/// Issue réellement survenue, pour les marchés 1X2 (match terminé).
String? actualOneXTwoKey(int? homeGoals, int? awayGoals) {
  if (homeGoals == null || awayGoals == null) return null;
  if (homeGoals > awayGoals) return '1X2.HOME';
  if (homeGoals == awayGoals) return '1X2.DRAW';
  return '1X2.AWAY';
}

/// Lettre de forme (V/N/D) → résultat lisible.
String formLetterLabel(String letter) => switch (letter) {
      'V' => tr('Victoire'),
      'N' => tr('Nul'),
      'D' => tr('Défaite'),
      _ => letter,
    };

/// Informations manquantes de la fiche et de l'IA, sans doublon.
List<String> mergedMissing(AnalysisFiche fiche, AiAnalysis? ai) {
  final seen = <String>{};
  final out = <String>[];
  for (final s in [...fiche.missing, ...?ai?.missing]) {
    final k = s.trim().toLowerCase();
    if (k.isEmpty || !seen.add(k)) continue;
    out.add(s.trim());
  }
  return out;
}

/// Probabilité dite en langage courant : 0,75 → « environ 3 fois sur 4 »,
/// 0,17 → « environ 1 fois sur 6 ». Toujours une approximation (« environ »).
String frequencyLabel(double p) {
  if (p.isNaN || p <= 0) return tr('presque jamais selon le modèle');
  if (p < 0.05) return tr('moins d’1 fois sur 20');
  if (p >= 0.975) return tr('plus de 19 fois sur 20');
  if (p < 0.5) {
    final d = (1 / p).round();
    if (d >= 2 && ((1 / d) - p).abs() / p <= 0.12) {
      return trf('environ 1 fois sur {0}', [d]);
    }
    for (final d in const [3, 4, 5, 10, 20]) {
      final n = (p * d).round();
      if (n >= 1 && (n / d - p).abs() <= 0.03) {
        return trf('environ {0} fois sur {1}', [n, d]);
      }
    }
    return trf('environ {0} fois sur 10', [(p * 10).round()]);
  }
  for (final d in const [2, 3, 4, 5]) {
    final n = (p * d).round();
    if ((n / d - p).abs() <= 0.035) {
      return trf('environ {0} fois sur {1}', [n, d]);
    }
  }
  if (p >= 0.85) {
    for (final d in const [10, 20]) {
      final n = (p * d).round();
      if ((n / d - p).abs() <= 0.02) {
        return trf('environ {0} fois sur {1}', [n, d]);
      }
    }
  }
  // Sinon, la fraction simple la plus proche (dénominateur 2 à 5, ou 10).
  var best = (1, 2);
  for (final d in const [2, 3, 4, 5, 10]) {
    final n = (p * d).round();
    if ((n / d - p).abs() < (best.$1 / best.$2 - p).abs() - 1e-9) best = (n, d);
  }
  return trf('environ {0} fois sur {1}', [best.$1, best.$2]);
}

/// Cote équivalente à l'estimation du modèle (1 ÷ probabilité).
double? fairOdd(double? p) => p == null || p <= 0 ? null : 1 / p;
