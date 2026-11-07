import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n/tr.dart';
import 'system_providers.dart';
import 'update_widgets.dart';

/// LOT 26 : accès au module Android de mise à jour (`AppUpdater.kt`).
abstract class NativeUpdater {
  Future<Map<String, dynamic>> status();
  Future<void> startDownload(Map<String, Object?> args);
  Future<void> cancel();
  Future<bool> canInstall();
  Future<void> openInstallSettings();
  Future<bool> isUnmetered();

  /// installing, not_ready, corrupt ou failed.
  Future<String> install();
}

class ChannelUpdater implements NativeUpdater {
  static const _channel = MethodChannel('coupon_pro_ia/updater');

  @override
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
      await _channel.invokeMethod<Map<Object?, Object?>>('status') ?? {});

  @override
  Future<void> startDownload(Map<String, Object?> args) =>
      _channel.invokeMethod('startDownload', args);

  @override
  Future<void> cancel() => _channel.invokeMethod('cancel');

  @override
  Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> openInstallSettings() =>
      _channel.invokeMethod('openInstallSettings');

  @override
  Future<bool> isUnmetered() async =>
      await _channel.invokeMethod<bool>('isUnmetered') ?? false;

  @override
  Future<String> install() async =>
      await _channel.invokeMethod<String>('install') ?? 'failed';
}

/// null hors Android (web, iOS, tests) : l'ancien dialogue avec le navigateur reste utilisé.
final nativeUpdaterProvider = Provider<NativeUpdater?>((ref) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? ChannelUpdater()
        : null);

const autoDownloadPrefKey = 'update.auto_download';

AutoDownload autoDownloadOf(String? v) => switch (v) {
      'always' => AutoDownload.always,
      'never' => AutoDownload.never,
      _ => AutoDownload.wifi,
    };

class AutoDownloadController extends StateNotifier<AutoDownload> {
  AutoDownloadController() : super(AutoDownload.wifi) {
    SharedPreferences.getInstance().then((p) {
      if (mounted) state = autoDownloadOf(p.getString(autoDownloadPrefKey));
    });
  }

  Future<void> set(AutoDownload value) async {
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setString(autoDownloadPrefKey, value.name);
  }
}

final autoDownloadProvider =
    StateNotifierProvider<AutoDownloadController, AutoDownload>(
        (ref) => AutoDownloadController());

enum UpdatePhase {
  /// À jour, ou vérification pas encore faite.
  idle,

  /// Version facultative : dialogue de proposition à afficher.
  offer,

  /// Téléchargement en cours (éventuellement en attente du Wi-Fi).
  downloading,

  /// Fichier reçu et vérifié : bandeau « Installer ».
  ready,

  /// Installation demandée à Android.
  installing,

  /// Échec (téléchargement, fichier non conforme) : nouvel essai possible.
  failed,

  /// Mise à jour impossible dans l'app (pas d'empreinte, autre plateforme) : navigateur.
  browser,
}

@immutable
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.latest,
    this.required = false,
    this.received = 0,
    this.total = 0,
    this.waitingForWifi = false,
    this.error,
  });

  final UpdatePhase phase;
  final AppVersionInfo? latest;

  /// Version installée plus prise en charge : écran bloquant.
  final bool required;

  /// Octets reçus / attendus.
  final int received;
  final int total;
  final bool waitingForWifi;
  final String? error;

  double get receivedMb => received / 1000000;
  double get totalMb => total > 0 ? total / 1000000 : (latest?.sizeMb ?? 0);

  UpdateState copyWith({
    UpdatePhase? phase,
    AppVersionInfo? latest,
    bool? required,
    int? received,
    int? total,
    bool? waitingForWifi,
    String? error,
  }) =>
      UpdateState(
        phase: phase ?? this.phase,
        latest: latest ?? this.latest,
        required: required ?? this.required,
        received: received ?? this.received,
        total: total ?? this.total,
        waitingForWifi: waitingForWifi ?? this.waitingForWifi,
        error: error,
      );
}

/// Textes des notifications Android, dans la langue de l'app.
Map<String, Object?> downloadTexts(String version) => {
      'title': trf('Téléchargement de la mise à jour {0}', [version]),
      'description': 'Coupon Pro IA',
      'readyTitle': trf('Mise à jour {0} prête', [version]),
      'readyBody': tr('Téléchargée et vérifiée. Touchez pour l’installer.'),
      'doneTitle': tr('Coupon Pro IA est à jour'),
      'doneBody': trf(
          'Version {0} installée. Touchez pour ouvrir l’application.',
          [version]),
      'channelName': tr('Mises à jour'),
    };

/// Déroulement d'une mise à jour : vérification, téléchargement automatique selon le
/// réglage (Wi-Fi par défaut), progression, vérification du fichier, installation.
class UpdateController extends StateNotifier<UpdateState> {
  UpdateController(this._ref) : super(const UpdateState());

  final Ref _ref;
  Timer? _poll;
  bool _awaitingPermission = false;

  NativeUpdater? get _native => _ref.read(nativeUpdaterProvider);

  /// Au lancement, au retour dans l'app ou à la demande ([userInitiated]).
  Future<UpdateState> check({bool userInitiated = false}) async {
    try {
      _ref.invalidate(latestAndroidVersionProvider);
      final package = await _ref.read(installedPackageProvider.future);
      final latest = await _ref.read(latestAndroidVersionProvider.future);
      final kind = updateKindFor(
          installedBuild: int.tryParse(package.buildNumber) ?? 0,
          latest: latest);
      final native = _native;
      if (kind == UpdateKind.none || latest == null) {
        // Une version préparée plus ancienne (ou déjà installée) est oubliée.
        if (native != null) {
          final s = await native.status();
          if (s['state'] != 'none' && s['state'] != null) await native.cancel();
        }
        return state = const UpdateState();
      }
      final required = kind == UpdateKind.required;
      if (native == null || !latest.installableInApp) {
        return state = UpdateState(
            phase: UpdatePhase.browser, latest: latest, required: required);
      }
      final s = await native.status();
      final sameVersion = s['version'] == latest.versionName;
      final raw = sameVersion ? s['state'] as String? : null;
      final nativeState = raw == 'none' ? null : raw;
      if (nativeState == 'installing') {
        // Installation interrompue (annulée par l'utilisateur) : le fichier reste prêt.
        state = UpdateState(
            phase: UpdatePhase.ready, latest: latest, required: required);
        return state;
      }
      if (nativeState == 'ready') {
        return state = UpdateState(
            phase: UpdatePhase.ready, latest: latest, required: required);
      }
      if (nativeState == 'downloading') {
        state = UpdateState(
            phase: UpdatePhase.downloading,
            latest: latest,
            required: required,
            received: (s['received'] as num?)?.toInt() ?? 0,
            total: (s['total'] as num?)?.toInt() ?? 0,
            waitingForWifi: s['paused'] == true);
        _startPolling();
        return state;
      }
      // Rien de préparé pour cette version (un échec n'est pas relancé tout seul).
      if (!required && !userInitiated && nativeState == null) {
        // Lu directement : au démarrage, le réglage n'est peut-être pas
        // encore chargé dans le fournisseur.
        final prefs = await SharedPreferences.getInstance();
        final mode = autoDownloadOf(prefs.getString(autoDownloadPrefKey));
        final wifi = await native.isUnmetered();
        if (mode == AutoDownload.always ||
            (mode == AutoDownload.wifi && wifi)) {
          await download(latest, wifiOnly: mode == AutoDownload.wifi);
          return state;
        }
      }
      return state = UpdateState(
          phase: required ? UpdatePhase.idle : UpdatePhase.offer,
          latest: latest,
          required: required,
          error: nativeState == 'corrupt' || nativeState == 'failed'
              ? nativeState
              : null);
    } catch (_) {
      // Jamais bloquant (hors ligne, serveur indisponible).
      return state;
    }
  }

  /// Télécharge la version (en arrière-plan, notification Android de progression).
  Future<void> download(AppVersionInfo latest, {bool wifiOnly = false}) async {
    final native = _native;
    if (native == null || !latest.installableInApp) return;
    await native.startDownload({
      'url': latest.downloadUrl,
      'version': latest.versionName,
      'sha256': latest.sha256,
      'wifiOnly': wifiOnly,
      ...downloadTexts(latest.versionName),
    });
    state = state.copyWith(
        phase: UpdatePhase.downloading,
        latest: latest,
        received: 0,
        total: latest.sizeBytes ?? 0);
    _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  /// Relit l'état du téléchargement (progression, fin, échec).
  Future<void> refresh() async {
    final native = _native;
    if (native == null || state.phase != UpdatePhase.downloading) {
      _poll?.cancel();
      return;
    }
    try {
      final s = await native.status();
      final phase = switch (s['state']) {
        'ready' => UpdatePhase.ready,
        'corrupt' || 'failed' => UpdatePhase.failed,
        _ => UpdatePhase.downloading,
      };
      if (!mounted) return;
      state = state.copyWith(
        phase: phase,
        received: (s['received'] as num?)?.toInt() ?? state.received,
        total: ((s['total'] as num?)?.toInt() ?? -1) > 0
            ? (s['total'] as num).toInt()
            : state.total,
        waitingForWifi: s['paused'] == true,
        error: phase == UpdatePhase.failed ? s['state'] as String? : null,
      );
      if (phase != UpdatePhase.downloading) _poll?.cancel();
    } catch (_) {}
  }

  /// L'utilisateur a besoin d'autoriser l'installation (première fois) ?
  Future<bool> needsPermission() async =>
      !(await _native?.canInstall() ?? true);

  Future<void> openPermissionSettings() async {
    _awaitingPermission = true;
    await _native?.openInstallSettings();
  }

  /// Retour du réglage Android : installation reprise si l'autorisation est donnée.
  Future<bool> resumeAfterPermission() async {
    if (!_awaitingPermission) return false;
    _awaitingPermission = false;
    if (await needsPermission()) return false;
    await install();
    return true;
  }

  Future<String> install() async {
    final native = _native;
    if (native == null) return 'failed';
    state = state.copyWith(phase: UpdatePhase.installing);
    final r = await native.install();
    if (!mounted) return r;
    state = state.copyWith(
        phase: r == 'installing'
            ? UpdatePhase.installing
            : r == 'corrupt'
                ? UpdatePhase.failed
                : UpdatePhase.ready,
        error: r == 'installing' ? null : r);
    return r;
  }

  /// Bandeau « Plus tard » : masqué jusqu'au prochain lancement.
  void postpone() {
    if (state.phase == UpdatePhase.ready && !state.required) {
      state = state.copyWith(phase: UpdatePhase.idle);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

final updateControllerProvider =
    StateNotifierProvider<UpdateController, UpdateState>(
        (ref) => UpdateController(ref));
