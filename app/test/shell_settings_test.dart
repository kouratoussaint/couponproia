import 'package:coupon_pro_ia/core/theme/text_scale_controller.dart';
import 'package:coupon_pro_ia/features/shell/home_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'Retour : onglets précédents, puis Accueil, puis confirmation pour quitter',
      () {
    final h = TabBackHistory()
      ..visited(0, 1) // Accueil → Matchs
      ..visited(1, 3) // Matchs → Assistant
      ..visited(3, 1); // Assistant → Matchs (déjà visité)
    expect(h.back(1), 3);
    expect(h.back(3), 0);
    expect(h.back(0), isNull, reason: 'sur l’Accueil : demander confirmation');

    final fresh = TabBackHistory();
    expect(fresh.back(2), 0, reason: 'sans historique, retour à l’Accueil');
  });

  test('Quitter : deux appuis en moins de 2 secondes', () {
    final h = TabBackHistory();
    final t = DateTime(2026, 10, 31, 8);
    expect(h.confirmExit(t), isFalse);
    expect(h.confirmExit(t.add(const Duration(seconds: 1))), isTrue);
    expect(h.confirmExit(t.add(const Duration(seconds: 5))), isFalse);
    expect(h.confirmExit(t.add(const Duration(seconds: 9))), isFalse,
        reason: 'trop tard : nouvel avertissement');
  });

  test('taille du texte : choix × téléphone, bornée', () {
    expect(effectiveTextScale(1.0, TextSize.normal), 1.0);
    expect(effectiveTextScale(1.0, TextSize.large), 1.15);
    expect(effectiveTextScale(1.3, TextSize.extraLarge), 1.6);
    expect(effectiveTextScale(0.8, TextSize.small), 0.8);
    expect(TextSize.fromName('inconnu'), TextSize.normal);
  });
}
