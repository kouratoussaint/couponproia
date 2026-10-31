import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import 'assistant_models.dart';

const _userCouponColumns =
    'id, status, title, total_odd, combined_probability, implied_probability, risk_level, '
    'engine_version, conversation_id, created_at, analysis, result, settled_odd, published_at, user_coupon_selections(position, selection_key, odd, result, '
    'odd_best, bookmakers, odds_captured_at, model_probability, implied_probability, edge, reliability, justification, '
    'match:matches(id, kickoff_at, status, home_goals, away_goals, home:teams!matches_home_team_fk(name, logo_url), '
    'away:teams!matches_away_team_fk(name, logo_url), competition:competitions(name)))';

class AssistantException implements Exception {
  const AssistantException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AssistantReply {
  const AssistantReply(
      {required this.conversationId, required this.messages, this.credits});

  final String conversationId;
  final List<AssistantMessage> messages;
  final Credits? credits;
}

class AssistantRepository {
  AssistantRepository(this._client);

  final SupabaseClient _client;

  Future<AssistantReply> send(String message,
      {String? conversationId,
      String? couponId,
      Map<String, dynamic>? quick}) async {
    try {
      final res = await _client.functions.invoke('assistant', body: {
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
        if (couponId != null) 'coupon_id': couponId,
        if (quick != null) 'quick': quick,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      return AssistantReply(
        conversationId: data['conversation_id'] as String,
        messages: [
          for (final m in data['messages'] as List)
            AssistantMessage.fromJson(Map<String, dynamic>.from(m as Map))
        ],
        credits: data['credits'] is Map
            ? Credits.fromJson(
                Map<String, dynamic>.from(data['credits'] as Map))
            : null,
      );
    } on FunctionException catch (e) {
      final body = e.details is Map ? e.details as Map : const {};
      throw AssistantException(switch (body['error']) {
        'daily_limit' =>
          'Limite de ${body['limit']} messages par jour atteinte. Revenez demain.',
        'feature_disabled' => 'L’assistant est momentanément désactivé.',
        'unauthorized' => 'Session expirée : reconnectez-vous.',
        _ => 'L’assistant n’a pas pu répondre. Réessayez dans un instant.',
      });
    }
  }

  Future<Credits> myCredits() async => Credits.fromJson(
      Map<String, dynamic>.from(await _client.rpc('my_credits') as Map));

  Future<List<Conversation>> conversations() async {
    final rows = await _client
        .from('assistant_conversations')
        .select('id, title, updated_at')
        .order('updated_at', ascending: false)
        .limit(50);
    return rows.map(Conversation.fromJson).toList();
  }

  Future<List<AssistantMessage>> messages(String conversationId) async {
    final rows = await _client
        .from('assistant_messages')
        .select(
            'id, role, content, intent, payload, credits_charged, created_at')
        .eq('conversation_id', conversationId)
        .order('created_at')
        .limit(200);
    return rows.map(AssistantMessage.fromJson).toList();
  }

  Future<void> deleteConversation(String id) =>
      _client.from('assistant_conversations').delete().eq('id', id);

  Future<UserCoupon?> userCoupon(String id) async {
    final row = await _client
        .from('user_coupons')
        .select(_userCouponColumns)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : UserCoupon.fromJson(row);
  }

  Future<List<UserCoupon>> savedCoupons() async {
    final rows = await _client
        .from('user_coupons')
        .select(_userCouponColumns)
        // Les coupons publiés des Tipsters sont lisibles par tous : ne garder que les siens.
        .eq('user_id', _client.auth.currentUser?.id ?? '')
        .eq('status', 'saved')
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(UserCoupon.fromJson).toList();
  }

  Future<void> setStatus(String couponId, String status) => _client
      .from('user_coupons')
      .update({'status': status}).eq('id', couponId);

  Future<void> deleteCoupon(String couponId) =>
      _client.from('user_coupons').delete().eq('id', couponId);
}

final assistantRepositoryProvider = Provider<AssistantRepository>(
    (ref) => AssistantRepository(ref.watch(supabaseClientProvider)));

final myCreditsProvider = FutureProvider.autoDispose<Credits>(
    (ref) => ref.watch(assistantRepositoryProvider).myCredits());

final conversationsProvider = FutureProvider.autoDispose<List<Conversation>>(
    (ref) => ref.watch(assistantRepositoryProvider).conversations());

final userCouponProvider = FutureProvider.autoDispose
    .family<UserCoupon?, String>(
        (ref, id) => ref.watch(assistantRepositoryProvider).userCoupon(id));

final savedCouponsProvider = FutureProvider.autoDispose<List<UserCoupon>>(
    (ref) => ref.watch(assistantRepositoryProvider).savedCoupons());
