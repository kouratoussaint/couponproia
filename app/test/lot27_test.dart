// LOT 27 : navigation et retours. Le bouton retour d'Android est simulé
// (handlePopRoute) sur une copie de la structure de l'app : coque à 5 onglets,
// écrans plein écran au-dessus, avec les vrais composants de navigation.
import 'package:coupon_pro_ia/core/router/app_routes.dart';
import 'package:coupon_pro_ia/core/router/navigation.dart';
import 'package:coupon_pro_ia/core/router/shell_back.dart';
import 'package:coupon_pro_ia/core/widgets/sub_tab_back.dart';
import 'package:coupon_pro_ia/core/widgets/unsaved_changes_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final _scaffold = GlobalKey<ScaffoldState>();
int exits = 0;

Widget _page(String title, {List<Widget> actions = const []}) => Scaffold(
    appBar: AppBar(title: Text(title)), body: Column(children: actions));

Widget _tabs(String prefix, int count, {int initial = 0, int? shellTab}) =>
    DefaultTabController(
      length: count,
      initialIndex: initial,
      child: SubTabBackScope(
        shellTab: shellTab,
        child: Scaffold(
          appBar: AppBar(
            title: Text(prefix),
            bottom: TabBar(tabs: [
              for (var i = 0; i < count; i++) Tab(text: '$prefix-tab$i')
            ]),
          ),
          body: TabBarView(children: [
            for (var i = 0; i < count; i++) Text('$prefix-contenu$i')
          ]),
        ),
      ),
    );

class _Form extends StatefulWidget {
  const _Form();
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _c = TextEditingController(text: 'Nom');
  String? _baseline;
  @override
  Widget build(BuildContext context) {
    _baseline ??= _c.text;
    return UnsavedChangesGuard(
      isDirty: () => _c.text != _baseline,
      child: Scaffold(
          appBar: AppBar(title: const Text('FORMULAIRE')),
          body: TextField(controller: _c)),
    );
  }
}

GoRouter _router() {
  GoRoute old(String path) => GoRoute(
      path: path, redirect: (c, s) => normalizeLocation(s.uri.toString()));
  return GoRouter(initialLocation: AppRoutes.home, routes: [
    old(AppRoutes.oldLab),
    old(AppRoutes.oldMyCoupons),
    old(AppRoutes.oldLegal),
    old(AppRoutes.oldCompetitions),
    GoRoute(path: AppRoutes.legal, builder: (c, s) => _page('MENTIONS')),
    GoRoute(path: AppRoutes.help, builder: (c, s) => _page('AIDE')),
    GoRoute(
        path: AppRoutes.helpArticle,
        builder: (c, s) => _page('ARTICLE ${s.pathParameters['id']}')),
    GoRoute(path: AppRoutes.matchDetail, builder: (c, s) => _tabs('MATCH', 4)),
    GoRoute(path: '/formulaire', builder: (c, s) => const _Form()),
    GoRoute(path: AppRoutes.signIn, builder: (c, s) => _page('CONNEXION')),
    GoRoute(
        path: AppRoutes.verifyEmail, builder: (c, s) => _page('VERIFICATION')),
    StatefulShellRoute.indexedStack(
      builder: (c, s, shell) => ShellBackScope(
        navigationShell: shell,
        scaffoldKey: _scaffold,
        onExit: () => exits++,
        child: Scaffold(
          key: _scaffold,
          drawer: const Drawer(child: Text('MENU')),
          body: shell,
          bottomNavigationBar: Text('ONGLET=${shell.currentIndex}'),
        ),
      ),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: AppRoutes.home, builder: (c, s) => _page('ACCUEIL'))
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: AppRoutes.matches,
              builder: (c, s) => KeyedSubtree(
                  key: ValueKey(s.uri.query),
                  child: _tabs('MATCHS', 2,
                      shellTab: 1,
                      initial: s.uri.queryParameters['onglet'] == 'competitions'
                          ? 1
                          : 0)))
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: AppRoutes.coupons, builder: (c, s) => _page('COUPONS'))
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: AppRoutes.assistant,
              builder: (c, s) => KeyedSubtree(
                    key: ValueKey(s.uri.query),
                    child: Column(children: [
                      Text('COUPON=${s.uri.queryParameters['coupon']}'),
                      Expanded(
                        child: _tabs('ASSISTANT', 3,
                            shellTab: 3,
                            initial: switch (s.uri.queryParameters['onglet']) {
                              'coupons' => 1,
                              'laboratoire' => 2,
                              _ => 0
                            }),
                      ),
                    ]),
                  ))
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: AppRoutes.profile, builder: (c, s) => _page('PROFIL'))
        ]),
      ],
    ),
  ]);
}

Future<GoRouter> _start(WidgetTester t) async {
  final r = _router();
  await t.pumpWidget(MaterialApp.router(routerConfig: r));
  await t.pumpAndSettle();
  return r;
}

Future<void> _back(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

Future<void> _open(WidgetTester t, GoRouter r, String location) async {
  openLocation(r, location);
  await t.pumpAndSettle();
}

/// Titre de l'écran au premier plan (barre de titre visible).
bool _shows(String title) =>
    find.text(title).hitTestable().evaluate().isNotEmpty;

String _tab() => find
    .textContaining('ONGLET=')
    .evaluate()
    .map((e) => (e.widget as Text).data!)
    .join();

void main() {
  setUp(() {
    exits = 0;
    TabBackHistory.pendingStack = null;
  });

  test('anciennes adresses et onglets', () {
    expect(normalizeLocation('/laboratoire?coupon=7'),
        '/assistant?onglet=laboratoire&coupon=7');
    expect(normalizeLocation('/laboratoire'), AppRoutes.assistantLab);
    expect(normalizeLocation('/mes-coupons'), AppRoutes.assistantMyCoupons);
    expect(normalizeLocation('/mes-coupons/abc'), '/mes-coupons/abc');
    expect(normalizeLocation('/profil/mentions'), '/mentions');
    expect(normalizeLocation('/competitions'), AppRoutes.matchesCompetitions);
    expect(normalizeLocation('/competitions/39'), '/competitions/39');
    expect(tabIndexOf('/coupons'), 2);
    expect(tabIndexOf('/assistant?onglet=coupons'), 3);
    expect(tabIndexOf('/coupon/abc'), isNull);
    expect(tabIndexOf('/profil/modifier'), isNull);
  });

  test('historique : écrans à rouvrir rattachés à l’onglet quitté', () {
    final h = TabBackHistory()
      ..visited(0, 2, stack: ['/aide', '/aide/x'])
      ..visited(2, 1);
    expect(h.backEntry(1)!.tab, 2);
    final e = h.backEntry(2)!;
    expect(e.tab, 0);
    expect(e.stack, ['/aide', '/aide/x']);
    expect(h.backEntry(0), isNull);
  });

  testWidgets('notification vers un onglet : bon onglet, retour à l’Accueil',
      (t) async {
    final r = await _start(t);
    await _open(t, r, AppRoutes.coupons);
    expect(_shows('COUPONS'), isTrue);
    expect(_tab(), 'ONGLET=2');
    await _back(t);
    expect(_shows('ACCUEIL'), isTrue);
    expect(_tab(), 'ONGLET=0');
  });

  testWidgets(
      'ancienne notification « Laboratoire » : sous-onglet, puis Assistant, puis Accueil',
      (t) async {
    final r = await _start(t);
    await _open(t, r, '/laboratoire?coupon=7');
    expect(_tab(), 'ONGLET=3');
    expect(find.text('COUPON=7'), findsOneWidget);
    expect(_shows('ASSISTANT-contenu2'), isTrue);
    await _back(t);
    expect(_shows('ASSISTANT-contenu0'), isTrue, reason: 'premier sous-onglet');
    expect(_tab(), 'ONGLET=3');
    await _back(t);
    expect(_tab(), 'ONGLET=0');
  });

  testWidgets(
      'Aide → article → bouton vers un onglet : le retour rouvre l’article',
      (t) async {
    final r = await _start(t);
    r.push(AppRoutes.help);
    await t.pumpAndSettle();
    r.push(AppRoutes.helpArticleFor('1'));
    await t.pumpAndSettle();
    await _open(t, r, AppRoutes.coupons);
    expect(_shows('COUPONS'), isTrue);
    await _back(t);
    expect(_shows('ARTICLE 1'), isTrue);
    await _back(t);
    expect(_shows('AIDE'), isTrue);
    await _back(t);
    expect(_shows('ACCUEIL'), isTrue);
  });

  testWidgets('articles liés : le retour revient à l’article précédent',
      (t) async {
    final r = await _start(t);
    r.push(AppRoutes.helpArticleFor('1'));
    await t.pumpAndSettle();
    await _open(t, r, AppRoutes.helpArticleFor('2'));
    expect(_shows('ARTICLE 2'), isTrue);
    await _back(t);
    expect(_shows('ARTICLE 1'), isTrue);
  });

  testWidgets('menu → Mentions légales depuis l’Accueil : retour à l’Accueil',
      (t) async {
    final r = await _start(t);
    await _open(t, r, '/profil/mentions'); // ancienne adresse
    expect(_shows('MENTIONS'), isTrue);
    await _back(t);
    expect(_shows('ACCUEIL'), isTrue);
    expect(_tab(), 'ONGLET=0');
  });

  testWidgets('détail d’un match : sous-onglet, puis écran précédent',
      (t) async {
    final r = await _start(t);
    await _open(t, r, AppRoutes.matchDetailFor(5));
    await t.tap(find.text('MATCH-tab2'));
    await t.pumpAndSettle();
    await _back(t);
    expect(_shows('MATCH-contenu0'), isTrue);
    await _back(t);
    expect(_shows('ACCUEIL'), isTrue);
  });

  testWidgets('Matchs → Compétitions : retour au Calendrier, puis Accueil',
      (t) async {
    final r = await _start(t);
    await _open(t, r, AppRoutes.matchesCompetitions);
    expect(_shows('MATCHS-contenu1'), isTrue);
    await _back(t);
    expect(_shows('MATCHS-contenu0'), isTrue);
    await _back(t);
    expect(_tab(), 'ONGLET=0');
  });

  testWidgets('formulaire : retour direct sans modification, question sinon',
      (t) async {
    final r = await _start(t);
    await _open(t, r, '/formulaire');
    await _back(t);
    expect(_shows('ACCUEIL'), isTrue, reason: 'rien de modifié');

    await _open(t, r, '/formulaire');
    await t.enterText(find.byType(TextField), 'Autre nom');
    await _back(t);
    expect(find.text('Quitter sans enregistrer ?'), findsOneWidget);
    await t.tap(find.text('Continuer la saisie'));
    await t.pumpAndSettle();
    expect(_shows('FORMULAIRE'), isTrue);
    await _back(t);
    await t.tap(find.text('Quitter'));
    await t.pumpAndSettle();
    expect(_shows('ACCUEIL'), isTrue);
  });

  testWidgets('connexion → code de vérification : retour à la connexion',
      (t) async {
    final r = await _start(t);
    r.go(AppRoutes.signIn);
    await t.pumpAndSettle();
    r.push(AppRoutes.verifyEmailFor('a@b.c'));
    await t.pumpAndSettle();
    await _back(t);
    expect(_shows('CONNEXION'), isTrue);
  });

  testWidgets(
      'menu ouvert : le retour le ferme ; Accueil : deux appuis pour quitter',
      (t) async {
    await _start(t);
    _scaffold.currentState!.openDrawer();
    await t.pumpAndSettle();
    await _back(t);
    expect(_scaffold.currentState!.isDrawerOpen, isFalse);
    await _back(t);
    expect(find.text('Appuyez encore sur Retour pour quitter'), findsOneWidget);
    expect(exits, 0);
    await _back(t);
    expect(exits, 1);
  });
}
