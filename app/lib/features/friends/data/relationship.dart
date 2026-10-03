import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';

/// How the signed-in user relates to another user (`get_relationship`).
enum RelationshipStatus {
  self('self'),
  none('none'),
  requestSent('request_sent'),
  requestReceived('request_received'),
  friends('friends'),
  blocked('blocked');

  RelationshipStatus(this.wire);

  final String wire;

  static RelationshipStatus parse(Object? value) =>
      values.firstWhere((s) => s.wire == value?.toString(), orElse: () => RelationshipStatus.none);
}

@immutable
class Relationship {
  const Relationship(this.status, {this.requestId});

  factory Relationship.fromJson(Map<String, dynamic> j) =>
      Relationship(RelationshipStatus.parse(j['status']), requestId: j.intOrNull('request_id'));

  static const none = Relationship(RelationshipStatus.none);
  static const self = Relationship(RelationshipStatus.self);
  static const friends = Relationship(RelationshipStatus.friends);
  static const blocked = Relationship(RelationshipStatus.blocked);

  final RelationshipStatus status;

  /// Pending request id (for `request_sent` / `request_received`).
  final int? requestId;

  bool get isFriend => status == RelationshipStatus.friends;
  bool get isBlocked => status == RelationshipStatus.blocked;
  bool get isPending => status == RelationshipStatus.requestSent || status == RelationshipStatus.requestReceived;

  Map<String, dynamic> toJson() => {'status': status.wire, 'request_id': ?requestId};

  @override
  bool operator ==(Object other) => other is Relationship && other.status == status && other.requestId == requestId;

  @override
  int get hashCode => Object.hash(status, requestId);

  @override
  String toString() => 'Relationship(${status.wire}${requestId == null ? '' : ', #$requestId'})';
}

/// Resolves relationships for many users from raw rows of `friendships`,
/// pending `friend_requests` and my `blocks` — two to three cheap queries for
/// a whole result page instead of one `get_relationship` RPC per row.
/// Precedence mirrors `get_relationship`: self → blocked → friends → pending.
Map<String, Relationship> resolveRelationships({
  required String me,
  required Iterable<String> userIds,
  required List<Map<String, dynamic>> friendships,
  required List<Map<String, dynamic>> pendingRequests,
  required List<Map<String, dynamic>> blocks,
}) {
  final friends = <String>{
    for (final f in friendships)
      if (f.str('user_a') == me) f.str('user_b') else f.str('user_a'),
  };
  final blocked = <String>{for (final b in blocks) b.str('blocked_id')};
  final pending = <String, Relationship>{};
  for (final r in pendingRequests) {
    final sender = r.str('sender_id');
    final id = r.intOrNull('id');
    if (sender == me) {
      pending[r.str('receiver_id')] = Relationship(RelationshipStatus.requestSent, requestId: id);
    } else {
      pending[sender] = Relationship(RelationshipStatus.requestReceived, requestId: id);
    }
  }
  return {
    for (final id in userIds)
      id: id == me
          ? Relationship.self
          : blocked.contains(id)
          ? Relationship.blocked
          : friends.contains(id)
          ? Relationship.friends
          : pending[id] ?? Relationship.none,
  };
}
