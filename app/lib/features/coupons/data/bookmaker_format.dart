import '../../matches/data/sports_format.dart';
import 'coupon_models.dart';

/// Code de pari tel qu'on le saisit chez un bookmaker (1xBet et la plupart des sites) :
/// 1 / X / 2, 1X / X2 / 12, « Plus de 2,5 buts », « Les deux marquent : Oui ».
String bookmakerPick(String key) {
  final parts = key.split('.');
  final market = parts.first;
  final outcome = parts.length > 1 ? parts[1] : '';
  final line =
      parts.length > 2 ? parts.sublist(2).join('.').replaceAll('.', ',') : '';
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
          ? 'Plus de $line buts (Total Plus $line)'
          : 'Moins de $line buts (Total Moins $line)';
    case 'BTTS':
      return outcome == 'YES'
          ? 'Les deux marquent : Oui'
          : 'Les deux marquent : Non';
    case 'DNB':
      return outcome == 'HOME'
          ? 'Remboursé si nul : 1 (DNB 1)'
          : 'Remboursé si nul : 2 (DNB 2)';
    case 'TTH' || 'TTA':
      final side = market == 'TTH' ? 'domicile' : 'extérieur';
      return outcome == 'OVER'
          ? 'Buts équipe $side : plus de $line (Total Plus $line)'
          : 'Buts équipe $side : moins de $line (Total Moins $line)';
  }
  return key;
}

String _odd(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

/// Texte d'un coupon prêt à reporter sur un site de paris : une ligne par match
/// (date, affiche, code du pari, cote). Jamais pour un coupon réservé : son contenu est masqué.
String bookmakerText(
    String title, double totalOdd, List<CouponSelection> selections) {
  final sorted = [...selections]
    ..sort((a, b) => a.match.kickoffAt.compareTo(b.match.kickoffAt));
  return [
    'Coupon Pro IA · $title',
    for (final (i, s) in sorted.indexed)
      '${i + 1}. ${shortDate(s.match.kickoffAt)} ${timeLabel(s.match.kickoffAt)} · '
          '${s.match.home} – ${s.match.away} · ${bookmakerPick(s.key)} · cote ${_odd(s.odd)}',
    'Cote totale indicative : ${_odd(totalOdd)} (les cotes du bookmaker peuvent différer)',
    'Estimations, aucune certitude. 18+ · Pariez de façon responsable.',
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
