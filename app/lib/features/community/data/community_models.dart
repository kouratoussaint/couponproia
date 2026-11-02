import '../../analysis/data/analysis_format.dart';
import '../../coupons/data/coupon_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
double? _dn(Object? v) => (v as num?)?.toDouble();
DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();

/// Droits communauté de l'utilisateur connecté (fonction my_community).
class CommunityRights {
  const CommunityRights({
    required this.tipstersEnabled,
    required this.communityEnabled,
    required this.canPublish,
    required this.canModerate,
    required this.following,
    this.profile,
    this.openReports,
  });

  factory CommunityRights.fromJson(Map<String, dynamic> j) => CommunityRights(
        tipstersEnabled: j['tipsters_enabled'] == true,
        communityEnabled: j['community_enabled'] == true,
        canPublish: j['can_publish'] == true,
        canModerate: j['can_moderate'] == true,
        following: _i(j['following']),
        profile: j['profile'] == null
            ? null
            : TipsterProfile.fromJson(_map(j['profile'])),
        openReports: j['open_reports'] == null ? null : _i(j['open_reports']),
      );

  final bool tipstersEnabled;
  final bool communityEnabled;
  final bool canPublish;
  final bool canModerate;
  final int following;
  final TipsterProfile? profile;
  final int? openReports;

  bool get isTipster => profile != null && profile!.isActive;
}

class TipsterProfile {
  const TipsterProfile({
    required this.userId,
    required this.handle,
    required this.displayName,
    this.bio,
    this.avatarPath,
    this.status = 'active',
  });

  factory TipsterProfile.fromJson(Map<String, dynamic> j) => TipsterProfile(
        userId: j['user_id'] as String,
        handle: j['handle'] as String,
        displayName: j['display_name'] as String,
        bio: j['bio'] as String?,
        avatarPath: j['avatar_path'] as String?,
        status: j['status'] as String? ?? 'active',
      );

  final String userId;
  final String handle;
  final String displayName;
  final String? bio;
  final String? avatarPath;
  final String status;

  bool get isActive => status == 'active';
}

/// Chiffres calculés par la plateforme (tipster_stats_raw).
class TipsterNumbers {
  const TipsterNumbers({
    required this.published,
    required this.won,
    required this.lost,
    required this.voided,
    required this.pending,
    required this.lastResults,
    this.winRate,
    this.averageOdd,
    this.theoreticalReturn,
  });

  factory TipsterNumbers.fromJson(Map<String, dynamic> j) => TipsterNumbers(
        published: _i(j['published']),
        won: _i(j['won']),
        lost: _i(j['lost']),
        voided: _i(j['void']),
        pending: _i(j['pending']),
        winRate: _dn(j['win_rate']),
        averageOdd: _dn(j['average_odd']),
        theoreticalReturn: _dn(j['theoretical_return']),
        lastResults: [
          for (final r in (j['last_results'] as List? ?? const [])) r as String
        ],
      );

  final int published;
  final int won;
  final int lost;
  final int voided;
  final int pending;
  final double? winRate;
  final double? averageOdd;
  final double? theoreticalReturn;
  final List<String> lastResults;

  int get settled => won + lost;
}

class TipsterStats {
  const TipsterStats({
    required this.allTime,
    required this.last30Days,
    required this.minSettledForRate,
    required this.followers,
    required this.scope,
    required this.stakeNote,
    required this.computedAt,
  });

  factory TipsterStats.fromJson(Map<String, dynamic> j) => TipsterStats(
        allTime: TipsterNumbers.fromJson(_map(j['all_time'])),
        last30Days: TipsterNumbers.fromJson(_map(j['last_30_days'])),
        minSettledForRate: _i(j['min_settled_for_rate']),
        followers: _i(j['followers']),
        scope: j['scope'] as String? ?? '',
        stakeNote: j['stake_note'] as String? ?? '',
        computedAt: _date(j['computed_at']),
      );

  final TipsterNumbers allTime;
  final TipsterNumbers last30Days;
  final int minSettledForRate;
  final int followers;
  final String scope;
  final String stakeNote;
  final DateTime computedAt;

  /// Le taux de réussite n'est affiché qu'à partir d'un nombre suffisant de coupons réglés.
  bool rateShown(TipsterNumbers n) => n.settled >= minSettledForRate;
}

/// Ligne de l'annuaire des Tipsters.
class TipsterSummary {
  const TipsterSummary({
    required this.profile,
    required this.followers,
    required this.iFollow,
    required this.settled30d,
    required this.stats30d,
  });

  factory TipsterSummary.fromJson(Map<String, dynamic> j) => TipsterSummary(
        profile: TipsterProfile.fromJson(j),
        followers: _i(j['followers']),
        iFollow: j['i_follow'] == true,
        settled30d: _i(j['settled_30d']),
        stats30d: TipsterNumbers.fromJson(_map(j['stats_30d'])),
      );

  final TipsterProfile profile;
  final int followers;
  final bool iFollow;
  final int settled30d;
  final TipsterNumbers stats30d;
}

class PostSelection {
  const PostSelection({
    required this.position,
    required this.key,
    required this.odd,
    required this.match,
    this.result,
  });

  factory PostSelection.fromJson(Map<String, dynamic> j) => PostSelection(
        position: _i(j['position']),
        key: j['selection_key'] as String,
        odd: (j['odd'] as num).toDouble(),
        result: j['result'] as String?,
        match: SelectionMatch.fromJson(_map(j['match'])),
      );

  final int position;
  final String key;
  final double odd;
  final String? result;
  final SelectionMatch match;

  String get pickLabel => outcomeKeyLabel(key, match.home, match.away);
}

class PostCoupon {
  const PostCoupon({
    required this.id,
    required this.title,
    required this.totalOdd,
    required this.combinedProbability,
    required this.publishedAt,
    required this.selections,
    this.result,
    this.settledOdd,
  });

  factory PostCoupon.fromJson(Map<String, dynamic> j) => PostCoupon(
        id: j['id'] as String,
        title: j['title'] as String,
        totalOdd: (j['total_odd'] as num).toDouble(),
        combinedProbability: (j['combined_probability'] as num).toDouble(),
        result: j['result'] as String?,
        settledOdd: _dn(j['settled_odd']),
        publishedAt: _date(j['published_at']),
        selections: [
          for (final s in (j['selections'] as List? ?? const []))
            PostSelection.fromJson(_map(s)),
        ],
      );

  final String id;
  final String title;
  final double totalOdd;
  final double combinedProbability;
  final String? result;
  final double? settledOdd;
  final DateTime publishedAt;
  final List<PostSelection> selections;

  DateTime? get firstKickoff => selections.isEmpty
      ? null
      : selections
          .map((s) => s.match.kickoffAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
}

class PostComment {
  const PostComment({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.authorId,
    required this.author,
    required this.isMine,
    required this.authorIsTipster,
    this.hidden = false,
  });

  factory PostComment.fromJson(Map<String, dynamic> j) => PostComment(
        id: _i(j['id']),
        body: j['body'] as String,
        createdAt: _date(j['created_at']),
        authorId: j['author_id'] as String,
        author: j['author'] as String? ?? tr('Utilisateur'),
        isMine: j['is_mine'] == true,
        authorIsTipster: j['author_is_tipster'] == true,
        hidden: j['status'] == 'hidden',
      );

  final int id;
  final String body;
  final DateTime createdAt;
  final String authorId;
  final String author;
  final bool isMine;
  final bool authorIsTipster;
  final bool hidden;
}

class Post {
  const Post({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.author,
    required this.reactions,
    required this.myReaction,
    required this.comments,
    required this.isMine,
    this.body,
    this.coupon,
    this.hidden = false,
    this.commentList = const [],
  });

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: _i(j['id']),
        kind: j['kind'] as String,
        body: j['body'] as String?,
        createdAt: _date(j['created_at']),
        author: TipsterProfile.fromJson(_map(j['author'])),
        reactions: _i(j['reactions']),
        myReaction: j['my_reaction'] == true,
        comments: _i(j['comments']),
        isMine: j['is_mine'] == true,
        hidden: j['status'] == 'hidden',
        coupon:
            j['coupon'] == null ? null : PostCoupon.fromJson(_map(j['coupon'])),
        commentList: [
          for (final c in (j['comment_list'] as List? ?? const []))
            PostComment.fromJson(_map(c)),
        ],
      );

  final int id;
  final String kind;
  final String? body;
  final DateTime createdAt;
  final TipsterProfile author;
  final int reactions;
  final bool myReaction;
  final int comments;
  final bool isMine;
  final bool hidden;
  final PostCoupon? coupon;
  final List<PostComment> commentList;

  bool get isCoupon => kind == 'coupon';

  Post withReaction(bool on) => Post(
        id: id,
        kind: kind,
        body: body,
        createdAt: createdAt,
        author: author,
        reactions: reactions + (on == myReaction ? 0 : (on ? 1 : -1)),
        myReaction: on,
        comments: comments,
        isMine: isMine,
        hidden: hidden,
        coupon: coupon,
        commentList: commentList,
      );
}

class ModerationItem {
  const ModerationItem({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.createdAt,
    required this.reportsOnTarget,
    this.details,
    this.previewText,
    this.previewAuthor,
    this.previewAuthorId,
    this.previewStatus,
  });

  factory ModerationItem.fromJson(Map<String, dynamic> j) {
    final p = _map(j['preview']);
    return ModerationItem(
      id: _i(j['id']),
      targetType: j['target_type'] as String,
      targetId: j['target_id'] as String,
      reason: j['reason'] as String,
      details: j['details'] as String?,
      createdAt: _date(j['created_at']),
      reportsOnTarget: _i(j['reports_on_target']),
      previewText: p['text'] as String?,
      previewAuthor: p['author'] as String?,
      previewAuthorId: p['author_id'] as String?,
      previewStatus: p['status'] as String?,
    );
  }

  final int id;
  final String targetType;
  final String targetId;
  final String reason;
  final String? details;
  final DateTime createdAt;
  final int reportsOnTarget;
  final String? previewText;
  final String? previewAuthor;
  final String? previewAuthorId;
  final String? previewStatus;
}

class BlockedUser {
  const BlockedUser({required this.userId, required this.name});

  factory BlockedUser.fromJson(Map<String, dynamic> j) => BlockedUser(
      userId: j['user_id'] as String,
      name: j['name'] as String? ?? tr('Utilisateur'));

  final String userId;
  final String name;
}

final reportReasons = {
  'spam': tr('Spam ou publicité'),
  'arnaque': tr('Arnaque ou promesse de gain'),
  'insulte': tr('Insulte ou harcèlement'),
  'faux_resultats': tr('Résultats trompeurs'),
  'autre': tr('Autre'),
};

/// Identifiant : 3 à 20 caractères, minuscules, chiffres ou « _ ».
String? validateHandle(String? v) {
  final s = (v ?? '').trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(s)) {
    return tr('3 à 20 caractères : lettres sans accent, chiffres ou « _ ».');
  }
  return null;
}

/// « il y a 3 h », « il y a 2 j », sinon la date.
String relativeTime(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return tr('à l’instant');
  if (d.inMinutes < 60) return trf('il y a {0} min', [d.inMinutes]);
  if (d.inHours < 24) return trf('il y a {0} h', [d.inHours]);
  if (d.inDays < 7) return trf('il y a {0} j', [d.inDays]);
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
}
