import 'package:coupon_pro_ia/features/assistant/data/assistant_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'message de l’assistant : coupons, avertissements, opportunités, diagnostic',
      () {
    final m = AssistantMessage.fromJson({
      'id': 'm1',
      'role': 'assistant',
      'content': 'Voici un coupon.',
      'intent': 'creer_coupon',
      'credits_charged': 1,
      'created_at': '2026-10-30T18:00:00Z',
      'payload': {
        'coupon_ids': ['c1'],
        'warnings': ['Critères assouplis.'],
        'opportunities': [
          {
            'match_id': 4,
            'match': 'A – B',
            'competition': 'Ligue 1',
            'kickoff_at': '2026-10-31T19:00:00Z',
            'selection': 'Victoire A',
            'key': '1X2.HOME',
            'odd': 1.9,
            'model_probability': 0.56,
            'implied_probability': 0.5,
            'edge': 0.06,
            'reliability': 'bonne',
          },
        ],
        'diagnosis': {
          'fragiles': [
            {
              'position': 2,
              'selection': 'Nul ou B (A – B)',
              'raison': 'probabilité du modèle 41 %'
            },
          ],
          'alertes': ['A – B : la cote est passée de 1,80 à 2,10.'],
          'qualite': ['Compositions non prises en compte.'],
        },
      },
    });
    expect(m.isUser, isFalse);
    expect(m.couponIds, ['c1']);
    expect(m.creditsCharged, 1);
    expect(m.opportunities.single.edge, 0.06);
    expect(m.diagnosis!.fragiles.single, contains('41 %'));
  });

  test('crédits : libellé selon le compte', () {
    expect(
        Credits.fromJson({
          'plan': 'FREE',
          'total': 2,
          'plan_credits': 2,
          'extra_credits': 0
        }).label,
        '2 crédits');
    expect(Credits.fromJson({'total': 1}).label, '1 crédit');
    expect(Credits.fromJson({'total': 0, 'unlimited': true}).label,
        'Illimité (équipe)');
  });
}
