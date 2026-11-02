// Cohérence d'une sélection avec le pronostic de l'IA (mêmes règles que le serveur) : une
// sélection est cohérente si elle passe chaque fois que le pronostic se réalise ; les marchés
// que l'IA n'a pas tranchés restent libres.

const _result = {
  '1X2.HOME': {'H'},
  '1X2.DRAW': {'D'},
  '1X2.AWAY': {'A'},
  'DC.1X': {'H', 'D'},
  'DC.X2': {'D', 'A'},
  'DC.12': {'H', 'A'},
  // Remboursé si nul : le nul annule la sélection sans la faire perdre.
  'DNB.HOME': {'H', 'D'},
  'DNB.AWAY': {'D', 'A'},
};

String? _family(String key) {
  if (_result.containsKey(key)) return 'result';
  if (RegExp(r'^OU\.(OVER|UNDER)\.\d+(\.\d+)?$').hasMatch(key)) return 'goals';
  if (key == 'BTTS.YES' || key == 'BTTS.NO') return 'btts';
  return null;
}

bool compatibleWithPick(String selection, String pick) {
  final f = _family(selection);
  if (f == null || f != _family(pick)) return true;
  if (f == 'result') return _result[selection]!.containsAll(_result[pick]!);
  if (f == 'btts') return selection == pick;
  final s = selection.split('.'), p = pick.split('.');
  if (s[1] != p[1]) return false;
  final sl = double.parse(s.sublist(2).join('.')),
      pl = double.parse(p.sublist(2).join('.'));
  return s[1] == 'OVER' ? sl <= pl : sl >= pl;
}

/// Pronostics de l'IA contredits par la sélection (vide = cohérente ou pas de pronostic).
List<String> aiContradictions(String selection, List<String> aiPicks) => [
      for (final p in aiPicks)
        if (!compatibleWithPick(selection, p)) p
    ];
