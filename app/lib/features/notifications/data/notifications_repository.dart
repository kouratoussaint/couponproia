import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.route,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: (j['id'] as num).toInt(),
        kind: j['kind'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        route: (j['route'] as String?)?.isEmpty ?? true
            ? null
            : j['route'] as String,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        readAt: j['read_at'] == null
            ? null
            : DateTime.parse(j['read_at'] as String).toLocal(),
      );

  final int id;
  final String kind;
  final String title;
  final String body;
  final String? route;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;
}

/// Réglages des notifications (colonnes de user_preferences).
class NotificationPrefs {
  const NotificationPrefs({
    this.enabled = true,
    this.coupons = true,
    this.results = true,
    this.tipsters = true,
    this.matches = true,
    this.morning = false,
    this.credits = true,
    this.analyses = true,
    this.betReminders = true,
    this.live = true,
    this.news = true,
    this.couponCategories = const {},
    this.quietStart = 23,
    this.quietEnd = 7,
    this.weeklyEmail = false,
  });

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) =>
      NotificationPrefs(
        enabled: j['notifications_enabled'] != false,
        coupons: j['notify_coupons'] != false,
        results: j['notify_results'] != false,
        tipsters: j['notify_tipsters'] != false,
        matches: j['notify_matches'] != false,
        morning: j['notify_morning'] == true,
        credits: j['notify_credits'] != false,
        analyses: j['notify_analyses'] != false,
        betReminders: j['notify_bet_reminders'] != false,
        live: j['notify_live'] != false,
        news: j['notify_news'] != false,
        couponCategories: {
          for (final c in (j['coupon_categories'] as List? ?? const [])) '$c'
        },
        quietStart: (j['quiet_start'] as num?)?.toInt() ?? 23,
        quietEnd: (j['quiet_end'] as num?)?.toInt() ?? 7,
        weeklyEmail: j['weekly_email'] == true,
      );

  final bool enabled;
  final bool coupons;
  final bool results;
  final bool tipsters;
  final bool matches;
  final bool morning;
  final bool credits;
  final bool analyses;
  final bool betReminders;
  final bool live;
  final bool news;

  /// Types de coupons notifiés ; vide = tous.
  final Set<String> couponCategories;
  final int quietStart;
  final int quietEnd;

  /// Rapport hebdomadaire par e-mail (désactivé par défaut).
  final bool weeklyEmail;

  static const columns =
      'notifications_enabled, notify_coupons, notify_results, notify_tipsters, '
      'notify_matches, notify_morning, notify_credits, notify_analyses, notify_bet_reminders, '
      'notify_live, notify_news, coupon_categories, quiet_start, quiet_end, weekly_email';

  bool get hasQuietHours => quietStart != quietEnd;
}

/// Types de notification réglables : (colonne, titre, description).
final notificationKinds = [
  (
    'notify_coupons',
    tr('Nouveaux coupons'),
    tr('Quand un coupon de la plateforme que vous pouvez voir est publié')
  ),
  (
    'notify_results',
    tr('Résultats de mes coupons'),
    tr('Gagné, perdu ou annulé, dès le règlement')
  ),
  (
    'notify_tipsters',
    tr('Tipsters suivis'),
    tr('Quand un Tipster que vous suivez publie')
  ),
  (
    'notify_matches',
    tr('Rappels de match'),
    tr('30 minutes avant un match d’une équipe que vous suivez')
  ),
  (
    'notify_morning',
    tr('Rendez-vous du matin'),
    tr('Vers 7 h 30 : matchs du jour et analyse offerte')
  ),
  (
    'notify_analyses',
    tr('Analyses de mes équipes'),
    tr('Quand le match d’une équipe que vous suivez vient d’être analysé')
  ),
  (
    'notify_bet_reminders',
    tr('Rappel avant mes paris'),
    tr('15 minutes avant le premier match d’un pari noté dans votre carnet')
  ),
  (
    'notify_live',
    tr('Scores en direct de mes paris'),
    tr('À chaque but sur un match de votre carnet ou d’un coupon dont vous suivez la cote')
  ),
  (
    'notify_credits',
    tr('Crédits IA et forfait'),
    tr('Crédits presque épuisés, forfait qui se termine (3 jours avant, la veille)')
  ),
  (
    'notify_news',
    tr('Annonces et offres'),
    tr('Nouveautés de l’application et offres de l’équipe, rarement')
  ),
];

bool prefValue(NotificationPrefs p, String column) => switch (column) {
      'notify_coupons' => p.coupons,
      'notify_results' => p.results,
      'notify_tipsters' => p.tipsters,
      'notify_matches' => p.matches,
      'notify_morning' => p.morning,
      'notify_analyses' => p.analyses,
      'notify_bet_reminders' => p.betReminders,
      'notify_live' => p.live,
      'notify_news' => p.news,
      _ => p.credits,
    };

class NotificationsRepository {
  NotificationsRepository(this._client);

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw AuthException(tr('Session expirée'));
    return id;
  }

  Future<List<AppNotification>> inbox() async {
    final rows = await _client
        .from('notifications')
        .select('id, kind, title, body, route, created_at, read_at')
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(AppNotification.fromJson).toList();
  }

  Future<int> unreadCount() async {
    final rows = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', _uid)
        .isFilter('read_at', null)
        .limit(100);
    return rows.length;
  }

  Future<void> markRead([List<int>? ids]) async {
    await _client.rpc('mark_notifications_read', params: {'p_ids': ids});
  }

  Future<void> delete(int id) =>
      _client.from('notifications').delete().eq('id', id);

  Future<NotificationPrefs> prefs() async {
    final row = await _client
        .from('user_preferences')
        .select(NotificationPrefs.columns)
        .eq('user_id', _uid)
        .maybeSingle();
    return row == null
        ? const NotificationPrefs()
        : NotificationPrefs.fromJson(row);
  }

  Future<void> updatePrefs(Map<String, Object> values) async {
    await _client.from('user_preferences').update(values).eq('user_id', _uid);
  }

  Future<void> registerDevice(String token,
      {String platform = 'android', String? version}) async {
    await _client.rpc('register_device', params: {
      'p_token': token,
      'p_platform': platform,
      'p_version': version
    });
  }

  Future<void> unregisterDevice(String token) async {
    await _client.rpc('unregister_device', params: {'p_token': token});
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
    (ref) => NotificationsRepository(ref.watch(supabaseClientProvider)));

final inboxProvider = FutureProvider.autoDispose<List<AppNotification>>(
    (ref) => ref.watch(notificationsRepositoryProvider).inbox());

final unreadCountProvider = FutureProvider<int>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(notificationsRepositoryProvider).unreadCount();
});

final notificationPrefsProvider = FutureProvider.autoDispose<NotificationPrefs>(
    (ref) => ref.watch(notificationsRepositoryProvider).prefs());
