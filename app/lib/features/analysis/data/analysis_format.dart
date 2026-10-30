import 'analysis_models.dart';

/// « 53 % » à partir de 0,532.
String pct(double p) => '${(p * 100).round()} %';

/// Écart modèle − marché en points : « +4 pts », « −2 pts ».
String edgePoints(double edge) {
  final pts = (edge * 100).round();
  if (pts == 0) return '0 pt';
  return '${pts > 0 ? '+' : '−'}${pts.abs()} pts';
}

String decimal(double x, [int digits = 2]) =>
    x.toStringAsFixed(digits).replaceAll('.', ',');

/// Libellé lisible d'une issue (« 1X2.HOME », « OU.OVER.2.5 »…) avec le nom des équipes.
String outcomeKeyLabel(String key, String home, String away) {
  final parts = key.split('.');
  final market = parts.first;
  final outcome = parts.length > 1 ? parts[1] : '';
  final line =
      parts.length > 2 ? parts.sublist(2).join('.').replaceAll('.', ',') : '';
  switch (market) {
    case '1X2':
      return switch (outcome) {
        'HOME' => 'Victoire $home',
        'DRAW' => 'Match nul',
        'AWAY' => 'Victoire $away',
        _ => key,
      };
    case 'DC':
      return switch (outcome) {
        '1X' => '$home ou nul',
        '12' => '$home ou $away',
        'X2' => 'Nul ou $away',
        _ => key,
      };
    case 'OU':
      return outcome == 'OVER' ? 'Plus de $line buts' : 'Moins de $line buts';
    case 'BTTS':
      return outcome == 'YES'
          ? 'Les deux équipes marquent'
          : 'Au moins une équipe ne marque pas';
  }
  return key;
}

String reliabilityLabel(Reliability r) => switch (r) {
      Reliability.faible => 'Fiabilité faible',
      Reliability.moyenne => 'Fiabilité moyenne',
      Reliability.bonne => 'Fiabilité bonne',
    };

String reliabilityExplanation(AnalysisFiche f) =>
    'Basée sur ${f.homeTeamHomeMatches} match(s) à domicile de l’équipe qui reçoit et '
    '${f.awayTeamAwayMatches} à l’extérieur de l’équipe visiteuse cette saison.';

/// Pourquoi le texte de l'IA est absent.
String statsOnlyReason(String? reason) => switch (reason) {
      'no_provider' =>
        'L’analyse rédigée par l’IA n’est pas encore activée. Voici la fiche statistique.',
      'validation_failed' =>
        'Le texte proposé par l’IA n’a pas passé nos contrôles (chiffres vérifiés, aucune promesse de gain). '
            'Voici la fiche statistique seule.',
      'provider_error' =>
        'Le service d’IA est momentanément indisponible. Voici la fiche statistique seule.',
      _ => 'Voici la fiche statistique calculée par le moteur.',
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
      'V' => 'Victoire',
      'N' => 'Nul',
      'D' => 'Défaite',
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
  if (p.isNaN || p <= 0) return 'presque jamais selon le modèle';
  if (p < 0.05) return 'moins d’1 fois sur 20';
  if (p >= 0.975) return 'plus de 19 fois sur 20';
  if (p < 0.5) {
    final d = (1 / p).round();
    if (d >= 2 && ((1 / d) - p).abs() / p <= 0.12) {
      return 'environ 1 fois sur $d';
    }
    for (final d in const [3, 4, 5, 10, 20]) {
      final n = (p * d).round();
      if (n >= 1 && (n / d - p).abs() <= 0.03) {
        return 'environ $n fois sur $d';
      }
    }
    return 'environ ${(p * 10).round()} fois sur 10';
  }
  for (final d in const [2, 3, 4, 5]) {
    final n = (p * d).round();
    if ((n / d - p).abs() <= 0.035) return 'environ $n fois sur $d';
  }
  if (p >= 0.85) {
    for (final d in const [10, 20]) {
      final n = (p * d).round();
      if ((n / d - p).abs() <= 0.02) return 'environ $n fois sur $d';
    }
  }
  // Sinon, la fraction simple la plus proche (dénominateur 2 à 5, ou 10).
  var best = (1, 2);
  for (final d in const [2, 3, 4, 5, 10]) {
    final n = (p * d).round();
    if ((n / d - p).abs() < (best.$1 / best.$2 - p).abs() - 1e-9) best = (n, d);
  }
  return 'environ ${best.$1} fois sur ${best.$2}';
}

/// Cote équivalente à l'estimation du modèle (1 ÷ probabilité).
double? fairOdd(double? p) => p == null || p <= 0 ? null : 1 / p;
