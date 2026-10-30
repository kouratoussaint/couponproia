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
