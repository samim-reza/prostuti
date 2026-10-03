import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/feed/data/report.dart';

extension ReactionTypeUi on ReactionType {
  String label(AppLocalizations l) => switch (this) {
    ReactionType.like => l.feedReactionLike,
    ReactionType.love => l.feedReactionLove,
    ReactionType.haha => l.feedReactionHaha,
    ReactionType.wow => l.feedReactionWow,
    ReactionType.sad => l.feedReactionSad,
    ReactionType.angry => l.feedReactionAngry,
  };

  /// Accent used for the action-bar label once I reacted.
  Color color(ColorScheme scheme) => switch (this) {
    ReactionType.like => scheme.primary,
    ReactionType.love => AppColors.accent,
    ReactionType.angry => AppColors.danger,
    _ => AppColors.warning,
  };
}

extension PostVisibilityUi on PostVisibility {
  IconData get icon => switch (this) {
    PostVisibility.public => Icons.public_rounded,
    PostVisibility.friends => Icons.group_rounded,
    PostVisibility.onlyMe => Icons.lock_rounded,
  };

  String label(AppLocalizations l) => switch (this) {
    PostVisibility.public => l.feedVisibilityPublic,
    PostVisibility.friends => l.feedVisibilityFriends,
    PostVisibility.onlyMe => l.feedVisibilityOnlyMe,
  };

  String hint(AppLocalizations l) => switch (this) {
    PostVisibility.public => l.feedVisibilityPublicHint,
    PostVisibility.friends => l.feedVisibilityFriendsHint,
    PostVisibility.onlyMe => l.feedVisibilityOnlyMeHint,
  };
}

extension ReportReasonUi on ReportReason {
  String label(AppLocalizations l) => switch (this) {
    ReportReason.spam => l.feedReportReasonSpam,
    ReportReason.abuse => l.feedReportReasonAbuse,
    ReportReason.nudity => l.feedReportReasonNudity,
    ReportReason.violence => l.feedReportReasonViolence,
    ReportReason.misinformation => l.feedReportReasonMisinformation,
    ReportReason.other => l.feedReportReasonOther,
  };

  IconData get icon => switch (this) {
    ReportReason.spam => Icons.campaign_outlined,
    ReportReason.abuse => Icons.sentiment_very_dissatisfied_outlined,
    ReportReason.nudity => Icons.no_adult_content_outlined,
    ReportReason.violence => Icons.warning_amber_rounded,
    ReportReason.misinformation => Icons.fact_check_outlined,
    ReportReason.other => Icons.more_horiz_rounded,
  };
}
