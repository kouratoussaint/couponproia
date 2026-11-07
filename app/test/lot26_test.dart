// LOT 26 : mise à jour téléchargée et installée par l'application.
import 'package:coupon_pro_ia/features/system/app_updater.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:coupon_pro_ia/features/system/update_prompt.dart';
import 'package:coupon_pro_ia/features/system/update_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeUpdater implements NativeUpdater {
  Map<String, dynamic> current = {'state': 'none'};
  bool unmetered = true;
  bool allowed = true;
  String installResult = 'installing';
  final downloads = <Map<String, Object?>>[];
  int cancels = 0;
  int settingsOpened = 0;

  @override
  Future<Map<String, dynamic>> status() async => current;
  @override
  Future<void> startDownload(Map<String, Object?> args) async {
    downloads.add(args);
    current = {
      'state': 'downloading',
      'version': args['version'],
      'received': 0,
      'total': 32820320
    };
  }

  @override
  Future<void> cancel() async {
    cancels++;
    current = {'state': 'none'};
  }

  @override
  Future<bool> canInstall() async => allowed;
  @override
  Future<void> openInstallSettings() async => settingsOpened++;
  @override
  Future<bool> isUnmetered() async => unmetered;
  @override
  Future<String> install() async => installResult;
}

AppVersionInfo _v(
        {int build = 2142,
        int min = 2123,
        String? sha =
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'}) =>
    AppVersionInfo(
      versionName: '0.34.0',
      buildNumber: build,
      minSupportedBuild: min,
      downloadUrl: 'https://exemple.test/app.apk',
      releaseNotes: 'Notes',
      sha256: sha,
      sizeBytes: sha == null ? null : 32820320,
    );

ProviderContainer _container(FakeUpdater native, AppVersionInfo? latest,
        {String installed = '2141'}) =>
    ProviderContainer(overrides: [
      nativeUpdaterProvider.overrideWithValue(native),
      latestAndroidVersionProvider.overrideWith((ref) async => latest),
      installedPackageProvider.overrideWith((ref) async => PackageInfo(
          appName: 'a',
          packageName: 'p',
          version: '0.33.0',
          buildNumber: installed)),
    ]);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('à jour : rien à faire, version préparée ancienne oubliée', () async {
    final native = FakeUpdater()
      ..current = {'state': 'ready', 'version': '0.33.0'};
    final c = _container(native, _v(build: 2141));
    final s = await c.read(updateControllerProvider.notifier).check();
    expect(s.phase, UpdatePhase.idle);
    expect(native.cancels, 1);
    c.dispose();
  });

  test(
      'Wi-Fi (réglage par défaut) : téléchargement automatique en Wi-Fi seulement',
      () async {
    final native = FakeUpdater();
    final c = _container(native, _v());
    final s = await c.read(updateControllerProvider.notifier).check();
    expect(s.phase, UpdatePhase.downloading);
    expect(native.downloads.single['wifiOnly'], isTrue);
    expect(native.downloads.single['sha256'], hasLength(64));
    expect(native.downloads.single['readyTitle'], 'Mise à jour 0.34.0 prête');
    c.dispose();
  });

  test('données mobiles : rien sans accord, la proposition s’affiche',
      () async {
    final native = FakeUpdater()..unmetered = false;
    final c = _container(native, _v());
    final s = await c.read(updateControllerProvider.notifier).check();
    expect(s.phase, UpdatePhase.offer);
    expect(native.downloads, isEmpty);
    // L'utilisateur accepte : téléchargement sur tous les réseaux.
    await c.read(updateControllerProvider.notifier).download(s.latest!);
    expect(native.downloads.single['wifiOnly'], isFalse);
    c.dispose();
  });

  test('réglage « Jamais » et « Wi-Fi + mobile »', () async {
    SharedPreferences.setMockInitialValues({autoDownloadPrefKey: 'never'});
    var native = FakeUpdater();
    var c = _container(native, _v());
    await Future<void>.delayed(Duration.zero);
    expect((await c.read(updateControllerProvider.notifier).check()).phase,
        UpdatePhase.offer);
    c.dispose();

    SharedPreferences.setMockInitialValues({autoDownloadPrefKey: 'always'});
    native = FakeUpdater()..unmetered = false;
    c = _container(native, _v());
    await Future<void>.delayed(Duration.zero);
    expect((await c.read(updateControllerProvider.notifier).check()).phase,
        UpdatePhase.downloading);
    expect(native.downloads.single['wifiOnly'], isFalse);
    c.dispose();
  });

  test('fichier déjà prêt : bandeau ; échec non relancé tout seul', () async {
    var native = FakeUpdater()
      ..current = {'state': 'ready', 'version': '0.34.0'};
    var c = _container(native, _v());
    expect((await c.read(updateControllerProvider.notifier).check()).phase,
        UpdatePhase.ready);
    c.dispose();

    native = FakeUpdater()..current = {'state': 'corrupt', 'version': '0.34.0'};
    c = _container(native, _v());
    final s = await c.read(updateControllerProvider.notifier).check();
    expect(s.phase, UpdatePhase.offer);
    expect(s.error, 'corrupt');
    expect(native.downloads, isEmpty);
    c.dispose();
  });

  test('sans empreinte publiée : ancien parcours par le navigateur', () async {
    final native = FakeUpdater();
    final c = _container(native, _v(sha: null));
    expect((await c.read(updateControllerProvider.notifier).check()).phase,
        UpdatePhase.browser);
    c.dispose();
  });

  test(
      'version obligatoire : pas de téléchargement automatique, écran bloquant',
      () async {
    final native = FakeUpdater();
    final c = _container(native, _v(min: 2142), installed: '2141');
    final s = await c.read(updateControllerProvider.notifier).check();
    expect(s.required, isTrue);
    expect(native.downloads, isEmpty);
    c.dispose();
  });

  test('progression puis fichier vérifié ; installation et autorisation',
      () async {
    final native = FakeUpdater();
    final c = _container(native, _v());
    final ctrl = c.read(updateControllerProvider.notifier);
    await ctrl.check();
    native.current = {
      'state': 'downloading',
      'version': '0.34.0',
      'received': 16000000,
      'total': 32820320
    };
    await ctrl.refresh();
    expect(c.read(updateControllerProvider).received, 16000000);
    native.current = {'state': 'ready', 'version': '0.34.0'};
    await ctrl.refresh();
    expect(c.read(updateControllerProvider).phase, UpdatePhase.ready);

    native.allowed = false;
    expect(await ctrl.needsPermission(), isTrue);
    await ctrl.openPermissionSettings();
    expect(native.settingsOpened, 1);
    native.allowed = true;
    expect(await ctrl.resumeAfterPermission(), isTrue);
    expect(c.read(updateControllerProvider).phase, UpdatePhase.installing);

    native.installResult = 'corrupt';
    await ctrl.install();
    expect(c.read(updateControllerProvider).phase, UpdatePhase.failed);
    c.dispose();
  });

  testWidgets('bandeau « prête » sur l’accueil et réglages du profil',
      (tester) async {
    final native = FakeUpdater()
      ..current = {'state': 'ready', 'version': '0.34.0'};
    final c = _container(native, _v());
    await c.read(updateControllerProvider.notifier).check();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
          home: Scaffold(
              body: Column(
                  children: [UpdateReadyBannerSlot(), UpdateSettingsSlot()]))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mise à jour 0.34.0 prête'), findsOneWidget);
    expect(find.textContaining('version 0.34.0 prête'), findsOneWidget);
    expect(find.text('Wi-Fi'), findsOneWidget);
    await tester.tap(find.text('Plus tard'));
    await tester.pump();
    expect(find.text('Mise à jour 0.34.0 prête'), findsNothing);
    c.dispose();
  });

  testWidgets('mise à jour obligatoire : installer quand le fichier est prêt',
      (tester) async {
    final native = FakeUpdater()
      ..current = {'state': 'ready', 'version': '0.34.0'};
    final c = _container(native, _v(min: 2142));
    await c.read(updateControllerProvider.notifier).check();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: RequiredUpdatePage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mise à jour obligatoire'), findsOneWidget);
    expect(find.text('Installer'), findsOneWidget);
    c.dispose();
  });

  test('textes des notifications Android', () {
    final t = downloadTexts('0.34.0');
    expect(t['title'], 'Téléchargement de la mise à jour 0.34.0');
    expect(t['doneBody'], contains('0.34.0'));
    expect(autoDownloadOf(null), AutoDownload.wifi);
  });
}
