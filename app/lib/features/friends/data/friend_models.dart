import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/profile/data/profile.dart';

/// A row of `get_friends`.
@immutable
class Friend {
  const Friend({required this.user, required this.friendsSince, this.bio});

  factory Friend.fromJson(Map<String, dynamic> j) => Friend(
    user: UserSummary.fromJson(j),
    bio: j.strOrNull('bio'),
    friendsSince: j.dateOr('friends_since', DateTime.now()),
  );

  final UserSummary user;
  final String? bio;
  final DateTime friendsSince;

  Map<String, dynamic> toJson() => {
    ...user.toJson(),
    'bio': bio,
    'friends_since': friendsSince.toUtc().toIso8601String(),
  };
}

/// A pending friend request (`get_friend_requests`). For incoming requests
/// [user] is the sender, for outgoing ones the receiver.
@immutable
class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.user,
    required this.createdAt,
    required this.incoming,
    this.mutualFriends = 0,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> j, {required bool incoming}) => FriendRequest(
    id: j.integer('request_id'),
    user: UserSummary.fromJson(j),
    mutualFriends: j.integer('mutual_friends'),
    createdAt: j.dateOr('created_at', DateTime.now()),
    incoming: incoming,
  );

  final int id;
  final UserSummary user;
  final int mutualFriends;
  final DateTime createdAt;
  final bool incoming;

  Map<String, dynamic> toJson() => {
    'request_id': id,
    'user_id': user.id,
    'username': user.username,
    'full_name': user.fullName,
    'avatar_url': user.avatarUrl,
    'mutual_friends': mutualFriends,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

/// Why a person is suggested (`get_friend_suggestions.reason`).
enum SuggestionReason {
  mutual('mutual'),
  district('district'),
  sameExam('same_exam'),
  newcomer('new');

  SuggestionReason(this.wire);

  final String wire;

  static SuggestionReason parse(Object? value) =>
      values.firstWhere((r) => r.wire == value?.toString(), orElse: () => SuggestionReason.newcomer);
}

/// A "people you may know" row.
@immutable
class FriendSuggestion {
  const FriendSuggestion({required this.user, required this.reason, this.district, this.mutualFriends = 0});

  factory FriendSuggestion.fromJson(Map<String, dynamic> j) => FriendSuggestion(
    user: UserSummary.fromJson(j),
    district: j.strOrNull('district'),
    mutualFriends: j.integer('mutual_friends'),
    reason: SuggestionReason.parse(j['reason']),
  );

  final UserSummary user;
  final String? district;
  final int mutualFriends;
  final SuggestionReason reason;
}

/// A `search_users` hit.
@immutable
class UserSearchResult {
  const UserSearchResult({required this.user, this.district});

  factory UserSearchResult.fromJson(Map<String, dynamic> j) =>
      UserSearchResult(user: UserSummary.fromJson(j), district: j.strOrNull('district'));

  final UserSummary user;
  final String? district;
}
