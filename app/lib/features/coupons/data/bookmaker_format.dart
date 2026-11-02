import '../../matches/data/sports_format.dart';
import 'coupon_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Code de pari tel qu'on le saisit chez un bookmaker (1xBet et la plupart des sites) :
/// 1 / X / 2, 1X / X2 / 12, « Plus de 2,5 buts », « Les deux marquent : Oui ».
String bookmakerPick(String key) {
  final parts = key.split('.');
  final market = parts.first;
  final outcome = parts.length > 1 ? parts[1] : '';
  final line = parts.length > 2
      ? parts.sublist(2).join('.').replaceAll('.', decimalSeparator)
      : '';
  switch (market) {
    case '1X2':
      return switch (outcome) {
        'HOME' => '1',
        'DRAW' => 'X',
        'AWAY' => '2',
        _ => key,
      };
    case 'DC':
      return switch (outcome) {
        '1X' || '12' || 'X2' => outcome,
        _ => key,
      };
    case 'OU':
      return outcome == 'OVER'
          ? trf('Plus de {0} buts (Total Plus {1})', [line, line])
          : trf('Moins de {0} buts (Total Moins {1})', [line, line]);
    case 'BTTS':
      return outcome == 'YES'
          ? tr('Les deux marquent : Oui')
          : tr('Les deux marquent : Non');
    case 'DNB':
      return outcome == 'HOME'
          ? tr('Remboursé si nul : 1 (DNB 1)')
          : tr('Remboursé si nul : 2 (DNB 2)');
    case 'TTH' || 'TTA':
      final side = market == 'TTH' ? 'domicile' : tr('extérieur');
      return outcome == 'OVER'
          ? trf('Buts équipe {0} : plus de {1} (Total Plus {2})',
              [side, line, line])
          : trf('Buts équipe {0} : moins de {1} (Total Moins {2})',
              [side, line, line]);
  }
  return key;
}

String _odd(double v) => v.toStringAsFixed(2).replaceAll('.', decimalSeparator);

/// Texte d'un coupon prêt à reporter sur un site de paris : une ligne par match
/// (date, affiche, code du pari, cote). Jamais pour un coupon réservé : son contenu est masqué.
String bookmakerText(
    String title, double totalOdd, List<CouponSelection> selections) {
  final sorted = [...selections]
    ..sort((a, b) => a.match.kickoffAt.compareTo(b.match.kickoffAt));
  return [
    trf('Coupon Pro IA · {0}', [title]),
    for (final (i, s) in sorted.indexed)
      trf('{0}. {1} {2} · {3} – {4} · {5} · cote {6}', [
        i + 1,
        shortDate(s.match.kickoffAt),
        timeLabel(s.match.kickoffAt),
        s.match.home,
        s.match.away,
        bookmakerPick(s.key),
        _odd(s.odd)
      ]),
    trf('Cote totale indicative : {0} (les cotes du bookmaker peuvent différer)',
        [_odd(totalOdd)]),
    tr('Estimations, aucune certitude. 18+ · Pariez de façon responsable.'),
  ].join('\n');
}

/// Lien « Ouvrir mon bookmaker » réglé par l'équipe (réglage public `bookmaker.link`).
class BookmakerLink {
  const BookmakerLink(this.name, this.url);

  final String name;
  final Uri url;

  static BookmakerLink? fromSetting(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final url = Uri.tryParse(value['url']?.toString() ?? '');
    if (name is! String || name.trim().isEmpty) return null;
    if (url == null || url.scheme != 'https' || url.host.isEmpty) return null;
    return BookmakerLink(name.trim(), url);
  }
}
