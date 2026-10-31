import 'package:coupon_pro_ia/features/community/data/community_models.dart';
import 'package:coupon_pro_ia/features/community/data/community_repository.dart';
import 'package:coupon_pro_ia/features/community/presentation/community_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _postJson({String? result, String kind = 'coupon'}) => {
      'id': 7,
      'kind': kind,
      'body': 'Ma sélection du jour',
      'status': 'visible',
      'created_at': '2026-10-31T08:00:00Z',
      'author': {
        'user_id': 'u1',
        'handle': 'kouassi_tips',
        'display_name': 'Kouassi Pronos',
        'avatar_path': null
      },
      'reactions': 3,
      'my_reaction': true,
      'comments': 2,
      'is_mine': false,
      'coupon': kind != 'coupon'
          ? null
          : {
              'id': 'c1',
              'title': 'Coupon du week-end',
              'total_odd': 2.34,
              'combined_probability': 0.41,
              'result': result,
              'settled_odd': result == 'won' ? 2.34 : null,
              'published_at': '2026-10-31T08:00:00Z',
              'selections': [
                for (final (i, h, a) in [
                  (1, 'Arsenal', 'Chelsea'),
                  (2, 'Lille', 'Lens')
                ])
                  {
                    'position': i,
                    'selection_key': '1X2.HOME',
                    'odd': 1.53,
                    'result': result == null ? null : 'won',
                    'match': {
                      'id': i,
                      'kickoff_at': '2026-10-31T15:00:00Z',
                      'status': 'scheduled',
                      'home': {'name': h, 'logo_url': null},
                      'away': {'name': a, 'logo_url': null},
                      'competition': {'name': 'Ligue'},
                    },
                  },
              ],
            },
      'comment_list': [
        {
          'id': 1,
          'body': 'Bien vu',
          'created_at': '2026-10-31T09:00:00Z',
          'status': 'visible',
          'is_mine': true,
          'author_id': 'u2',
          'author': 'Bob',
          'author_is_tipster': false,
        }
      ],
    };

Map<String, dynamic> _numbers(int won, int lost, {int pending = 0}) => {
      'published': won + lost + pending,
      'won': won,
      'lost': lost,
      'void': 0,
      'pending': pending,
      'win_rate': won + lost == 0 ? null : won / (won + lost),
      'average_odd': 1.9,
      'theoretical_return': -0.05,
      'last_results': [
        for (var i = 0; i < won; i++) 'won',
        for (var i = 0; i < lost; i++) 'lost'
      ].take(10).toList(),
    };

TipsterStats _stats(int won, int lost) => TipsterStats.fromJson({
      'all_time': _numbers(won, lost, pending: 1),
      'last_30_days': _numbers(won, lost),
      'min_settled_for_rate': 10,
      'stake_note': 'Mise théorique de 1 unité par coupon (aucun pari réel)',
      'scope':
          'Coupons publiés avant le premier coup d’envoi, réglés automatiquement par Coupon Pro IA',
      'followers': 12,
      'computed_at': '2026-10-31T10:00:00Z',
    });

class _FakeRepo implements CommunityRepository {
  @override
  String? avatarUrl(String? path) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(Widget child, {double scale = 1}) => ProviderScope(
      overrides: [communityRepositoryProvider.overrideWithValue(_FakeRepo())],
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
        builder: (c, w) => MediaQuery(
            data:
                MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: w!),
      ),
    );

void main() {
  test('publication lue depuis le serveur', () {
    final p = Post.fromJson(_postJson(result: 'won'));
    expect(p.isCoupon, isTrue);
    expect(p.coupon!.selections.length, 2);
    expect(p.coupon!.selections.first.pickLabel, 'Victoire Arsenal');
    expect(p.commentList.single.author, 'Bob');
    final unliked = p.withReaction(false);
    expect(unliked.reactions, 2);
    expect(unliked.withReaction(false).reactions, 2,
        reason: 'pas de double décompte');
  });

  test('identifiant Tipster et dates relatives', () {
    expect(validateHandle('Kouassi_Tips'), isNull);
    expect(validateHandle('ab'), isNotNull);
    expect(validateHandle('kouassi pronos'), isNotNull);
    final now = DateTime(2026, 10, 31, 12);
    expect(relativeTime(now.subtract(const Duration(minutes: 5)), now),
        'il y a 5 min');
    expect(relativeTime(now.subtract(const Duration(hours: 3)), now),
        'il y a 3 h');
    expect(relativeTime(DateTime(2026, 10, 1), now), '01/10/2026');
  });

  test('taux de réussite affiché seulement au-delà du seuil', () {
    final few = _stats(3, 2);
    expect(few.rateShown(few.allTime), isFalse);
    final many = _stats(7, 5);
    expect(many.rateShown(many.allTime), isTrue);
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets('carte de publication (texte ×$scale)', (tester) async {
      await tester.pumpWidget(_wrap(
          PostCard(post: Post.fromJson(_postJson(result: 'lost'))),
          scale: scale));
      await tester.pump();
      expect(find.text('Kouassi Pronos'), findsOneWidget);
      expect(find.text('Perdu'), findsOneWidget,
          reason: 'les pertes restent visibles');
      expect(find.text('Arsenal – Chelsea'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('statistiques vérifiées (texte ×$scale)', (tester) async {
      await tester.pumpWidget(
          _wrap(TipsterStatsCard(stats: _stats(3, 2)), scale: scale));
      await tester.pump();
      expect(find.text('Statistiques vérifiées'), findsOneWidget);
      expect(
          find.textContaining('à partir de 10 coupons réglés'), findsWidgets);
      expect(find.textContaining('ne garantissent pas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'coupon en cours : badge « En cours », jamais un résultat inventé',
      (tester) async {
    await tester.pumpWidget(_wrap(PostCard(post: Post.fromJson(_postJson()))));
    await tester.pump();
    expect(find.text('En cours'), findsOneWidget);
    expect(find.text('Gagné'), findsNothing);
  });
}

/// Données d'exemple réutilisées par les aperçus locaux.
Map<String, dynamic> postJsonForPreview(String? result,
        {String kind = 'coupon'}) =>
    _postJson(result: result, kind: kind);
TipsterStats statsForPreview() => _stats(9, 4);
