import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import 'analysis_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

// Le fournisseur et le modèle d'IA ne sont pas lisibles par les utilisateurs :
// le super administrateur les obtient avec [AnalysisRepository.tech].
const _analysisColumns = 'id, match_id, engine_version, status, status_reason, '
    'stats, analysis, source_updated_at, created_at';

/// Erreur métier renvoyée par la fonction d'analyse, déjà formulée pour l'utilisateur.
class AnalysisException implements Exception {
  const AnalysisException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Message clair pour une réponse d'erreur des fonctions d'analyse.
String analysisErrorMessage(int status, Object? details) {
  final body = details is Map ? details : const {};
  switch (body['error']) {
    case 'daily_limit':
      return trf(
          'Limite atteinte : {0} nouvelles analyses par jour. Vos analyses déjà obtenues restent consultables.',
          [body['limit'] ?? 20]);
    case 'feature_disabled':
      return tr('L’analyse IA est momentanément désactivée.');
    case 'match_not_analyzable':
      return tr('Ce match est reporté ou annulé : pas d’analyse possible.');
    case 'match_not_found':
      return tr('Match introuvable.');
    case 'forbidden':
      return tr('Action réservée aux administrateurs.');
    case 'unauthorized':
      return tr('Session expirée : reconnectez-vous.');
    case 'credits_required':
      return trf(
          'Il vous faut {0} crédit IA pour cette analyse. Achetez un pack de crédits (sans abonnement) ou choisissez un forfait dans Abonnement et crédits.',
          [body['cost'] ?? 1]);
    case 'subscription_required':
      return tr(
          'Analyse réservée aux comptes avec un forfait payant ou des crédits IA. L’analyse offerte du jour reste gratuite.');
  }
  return tr('L’analyse n’a pas pu être réalisée. Réessayez dans un instant.');
}

class AnalysisRepository {
  AnalysisRepository(this._client);

  final SupabaseClient _client;

  /// Dernière analyse enregistrée pour un match (partagée entre utilisateurs).
  Future<MatchAnalysis?> latest(int matchId) async {
    final row = await _client
        .from('match_analyses')
        .select(_analysisColumns)
        .eq('match_id', matchId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : MatchAnalysis.fromJson(row);
  }

  Future<Map<String, dynamic>> _invoke(
      String fn, Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(fn, body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      throw AnalysisException(analysisErrorMessage(e.status, e.details));
    }
  }

  /// Lance (ou récupère en cache) l'analyse d'un match. `force` : administrateurs.
  Future<MatchAnalysis> analyze(int matchId, {bool force = false}) async {
    final data = await _invoke(
        'analyze-match', {'match_id': matchId, if (force) 'force': true});
    return MatchAnalysis.fromJson(data);
  }

  Future<EngineEvaluation?> latestEvaluation() async {
    final row = await _client
        .from('engine_evaluations')
        .select()
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : EngineEvaluation.fromJson(row);
  }

  /// Fournisseur, modèle, prompt et temps de réponse d'une analyse (super administrateur).
  Future<Map<String, dynamic>> tech(int analysisId) async {
    final res = await _client
        .rpc('analysis_tech', params: {'p_analysis_id': analysisId});
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  Future<EngineEvaluation> evaluateEngine() async =>
      EngineEvaluation.fromJson(await _invoke('engine-evaluate', const {}));

  /// Journal IA des 7 derniers jours (administrateurs : toutes les requêtes).
  Future<List<Map<String, dynamic>>> recentAiRequests() async {
    final since = DateTime.now().toUtc().subtract(const Duration(days: 7));
    final rows = await _client
        .from('ai_requests')
        .select(
            'provider, model, status, input_tokens, output_tokens, cost_usd, latency_ms, error, created_at')
        .gte('created_at', since.toIso8601String())
        .order('created_at', ascending: false)
        .limit(500);
    return rows;
  }
}

final analysisRepositoryProvider = Provider<AnalysisRepository>(
  (ref) => AnalysisRepository(ref.watch(supabaseClientProvider)),
);

final storedAnalysisProvider =
    FutureProvider.autoDispose.family<MatchAnalysis?, int>(
  (ref, matchId) => ref.watch(analysisRepositoryProvider).latest(matchId),
);

final analysisTechProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>(
  (ref, id) => ref.watch(analysisRepositoryProvider).tech(id),
);

final latestEvaluationProvider = FutureProvider<EngineEvaluation?>(
  (ref) => ref.watch(analysisRepositoryProvider).latestEvaluation(),
);

final recentAiRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(analysisRepositoryProvider).recentAiRequests(),
);

/// Analyse obtenue pendant la session (bouton « Analyser »), prioritaire sur celle en base.
final freshAnalysisProvider =
    StateProvider.autoDispose.family<MatchAnalysis?, int>((ref, _) => null);

/// Analyse affichée dans la fiche : la plus récente de la session, sinon la dernière enregistrée.
final currentAnalysisProvider =
    Provider.autoDispose.family<AsyncValue<MatchAnalysis?>, int>((ref, id) {
  final fresh = ref.watch(freshAnalysisProvider(id));
  if (fresh != null) return AsyncData(fresh);
  return ref.watch(storedAnalysisProvider(id));
});
