import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/profile/data/profile.dart';

enum ConversationKind {
  direct,
  group;

  static ConversationKind parse(String? v) => v == 'group' ? group : direct;
}

/// One row of `get_conversations` (the chat inbox).
@immutable
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.kind,
    this.title,
    this.avatarUrl,
    this.otherUser,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.lastMessageSender,
    this.unreadCount = 0,
    this.muted = false,
    this.memberCount = 2,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> j) {
    final otherId = j.strOrNull('other_user_id');
    return ConversationSummary(
      id: j.str('id'),
      kind: ConversationKind.parse(j.strOrNull('kind')),
      title: j.strOrNull('title'),
      avatarUrl: j.strOrNull('avatar_url'),
      otherUser: otherId == null ? null : UserSummary.fromJson(j, prefix: 'other_'),
      lastMessageAt: j.date('last_message_at'),
      lastMessagePreview: j.strOrNull('last_message_preview'),
      lastMessageSender: j.strOrNull('last_message_sender'),
      unreadCount: j.integer('unread_count'),
      muted: j.boolean('muted'),
      memberCount: j.integer('member_count', 2),
    );
  }

  final String id;
  final ConversationKind kind;
  final String? title;
  final String? avatarUrl;

  /// The other participant of a direct conversation.
  final UserSummary? otherUser;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final String? lastMessageSender;
  final int unreadCount;
  final bool muted;
  final int memberCount;

  bool get isGroup => kind == ConversationKind.group;

  /// Group title or the other user's name; null when neither is known.
  String? get displayName {
    if (isGroup) return (title?.trim().isNotEmpty ?? false) ? title!.trim() : null;
    return otherUser?.displayName;
  }

  String? get displayAvatar => isGroup ? avatarUrl : otherUser?.avatarUrl;

  ConversationSummary copyWith({
    String? title,
    String? avatarUrl,
    DateTime? lastMessageAt,
    String? lastMessagePreview,
    String? lastMessageSender,
    int? unreadCount,
    bool? muted,
  }) => ConversationSummary(
    id: id,
    kind: kind,
    title: title ?? this.title,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    otherUser: otherUser,
    lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
    lastMessageSender: lastMessageSender ?? this.lastMessageSender,
    unreadCount: unreadCount ?? this.unreadCount,
    muted: muted ?? this.muted,
    memberCount: memberCount,
  );

  /// Same shape as the RPC row so cached pages decode with [ConversationSummary.fromJson].
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'avatar_url': avatarUrl,
    'other_user_id': otherUser?.id,
    'other_username': otherUser?.username,
    'other_full_name': otherUser?.fullName,
    'other_avatar_url': otherUser?.avatarUrl,
    'last_message_at': lastMessageAt?.toUtc().toIso8601String(),
    'last_message_preview': lastMessagePreview,
    'last_message_sender': lastMessageSender,
    'unread_count': unreadCount,
    'muted': muted,
    'member_count': memberCount,
  };
}

/// A member of a conversation (header, read receipts, mentions of names).
@immutable
class ChatMember {
  const ChatMember({required this.user, this.role = 'member', this.lastReadAt, this.muted = false});

  factory ChatMember.fromJson(Map<String, dynamic> j) {
    final profile = j.objOrNull('profiles');
    return ChatMember(
      user: profile == null ? UserSummary(id: j.str('user_id'), username: '') : UserSummary.fromJson(profile),
      role: j.str('role', 'member'),
      lastReadAt: j.date('last_read_at'),
      muted: j.boolean('muted'),
    );
  }

  final UserSummary user;
  final String role;
  final DateTime? lastReadAt;
  final bool muted;

  String get userId => user.id;

  ChatMember copyWith({DateTime? lastReadAt, bool? muted}) =>
      ChatMember(user: user, role: role, lastReadAt: lastReadAt ?? this.lastReadAt, muted: muted ?? this.muted);

  Map<String, dynamic> toJson() => {
    'user_id': user.id,
    'role': role,
    'last_read_at': lastReadAt?.toUtc().toIso8601String(),
    'muted': muted,
    'profiles': user.toJson(),
  };
}

/// Conversation header data: kind, title and members (with read state).
@immutable
class ConversationDetail {
  const ConversationDetail({
    required this.id,
    required this.kind,
    this.title,
    this.avatarUrl,
    this.createdBy,
    this.members = const [],
  });

  factory ConversationDetail.fromJson(Map<String, dynamic> j) => ConversationDetail(
    id: j.str('id'),
    kind: ConversationKind.parse(j.strOrNull('kind')),
    title: j.strOrNull('title'),
    avatarUrl: j.strOrNull('avatar_url'),
    createdBy: j.strOrNull('created_by'),
    members: j.list('conversation_members', ChatMember.fromJson),
  );

  /// Explicit select with embedded members and their public profile fields.
  static const columns =
      'id, kind, title, avatar_url, created_by, '
      'conversation_members(user_id, role, last_read_at, muted, profiles(id, username, full_name, avatar_url))';

  final String id;
  final ConversationKind kind;
  final String? title;
  final String? avatarUrl;
  final String? createdBy;
  final List<ChatMember> members;

  bool get isGroup => kind == ConversationKind.group;

  List<ChatMember> others(String? myId) => [
    for (final m in members)
      if (m.userId != myId) m,
  ];

  ChatMember? member(String userId) {
    for (final m in members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  /// The other participant of a direct conversation.
  UserSummary? otherUser(String? myId) {
    if (isGroup) return null;
    final o = others(myId);
    return o.isEmpty ? null : o.first.user;
  }

  String? displayName(String? myId) {
    if (isGroup) return (title?.trim().isNotEmpty ?? false) ? title!.trim() : null;
    return otherUser(myId)?.displayName;
  }

  ConversationDetail copyWith({List<ChatMember>? members}) => ConversationDetail(
    id: id,
    kind: kind,
    title: title,
    avatarUrl: avatarUrl,
    createdBy: createdBy,
    members: members ?? this.members,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'avatar_url': avatarUrl,
    'created_by': createdBy,
    'conversation_members': [for (final m in members) m.toJson()],
  };
}

enum MessageKind {
  text,
  image,
  system;

  static MessageKind parse(String? v) => switch (v) {
    'image' => image,
    'system' => system,
    _ => text,
  };
}

/// Local delivery state of a message. Everything from the server is [sent].
enum MessageStatus { sent, sending, failed }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.createdAt,
    this.kind = MessageKind.text,
    this.body,
    this.mediaPath,
    this.replyToId,
    this.editedAt,
    this.deletedAt,
    this.status = MessageStatus.sent,
    this.localBytes,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j.str('id'),
    conversationId: j.str('conversation_id'),
    senderId: j.str('sender_id'),
    kind: MessageKind.parse(j.strOrNull('kind')),
    body: j.strOrNull('body'),
    mediaPath: j.strOrNull('media_path'),
    replyToId: j.strOrNull('reply_to_id'),
    createdAt: j.dateOr('created_at', DateTime.now().toUtc()),
    editedAt: j.date('edited_at'),
    deletedAt: j.date('deleted_at'),
  );

  /// Restores a queued (offline) send after an app restart.
  factory ChatMessage.fromQueuePayload(Map<String, dynamic> p) =>
      ChatMessage.fromJson({...p, 'created_at': p['created_at_local']}).copyWith(status: MessageStatus.sending);

  /// Explicit, granted columns of `messages`.
  static const columns =
      'id, conversation_id, sender_id, kind, body, media_path, reply_to_id, created_at, edited_at, deleted_at';

  final String id;
  final String conversationId;
  final String senderId;
  final MessageKind kind;
  final String? body;
  final String? mediaPath;
  final String? replyToId;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final MessageStatus status;

  /// Bytes of an image picked on this device: rendered instantly while the
  /// upload runs, and kept afterwards so the bubble never flashes.
  final Uint8List? localBytes;

  bool get isDeleted => deletedAt != null;
  bool get isPending => status != MessageStatus.sent;
  bool get isSystem => kind == MessageKind.system;
  bool get isImage => kind == MessageKind.image;

  /// Columns the client may insert (column-level grant on `messages`).
  Map<String, dynamic> toInsert() => {
    'id': id,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'kind': kind.name,
    'body': body,
    'media_path': mediaPath,
    'reply_to_id': replyToId,
  };

  /// Insert columns + the local timestamp (to order restored bubbles).
  Map<String, dynamic> toQueuePayload() => {...toInsert(), 'created_at_local': createdAt.toUtc().toIso8601String()};

  /// Same shape as a `messages` row (disk cache of the latest page).
  Map<String, dynamic> toJson() => {
    ...toInsert(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'edited_at': editedAt?.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };

  ChatMessage copyWith({
    DateTime? createdAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    MessageStatus? status,
    Uint8List? localBytes,
  }) => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    kind: kind,
    body: body,
    mediaPath: mediaPath,
    replyToId: replyToId,
    createdAt: createdAt ?? this.createdAt,
    editedAt: editedAt,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    status: status ?? this.status,
    localBytes: localBytes ?? this.localBytes,
  );

  @override
  String toString() => 'ChatMessage($id, $kind, $status)';
}
