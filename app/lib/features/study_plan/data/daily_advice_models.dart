import 'package:flutter/foundation.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/core/utils/json.dart';

/// Screens a tip may open. The server only emits these (see
/// `daily-advice/advice.ts`); anything else is ignored on the client too.
const adviceStaticRoutes = {
  Routes.notes,
  Routes.dailyExam,
  Routes.wrongAnswers,
  Routes.exams,
  Routes.modelTests,
  Routes.questionBank,
  Routes.plan,
  Routes.progress,
};

final _practiceTopic = RegExp(r'^/practice\?topic=\d{1,9}$');

bool isAdviceRouteAllowed(String route) => adviceStaticRoutes.contains(route) || _practiceTopic.hasMatch(route);

/// One suggestion: a short title, one or two sentences, optionally a screen.
@immutable
class AdviceTip {
  const AdviceTip({required this.title, required this.body, this.actionRoute});

  factory AdviceTip.fromJson(Map<String, dynamic> j) {
    final route = j.strOrNull('action_route');
    return AdviceTip(
      title: j.str('title').trim(),
      body: j.str('body').trim(),
      actionRoute: route != null && isAdviceRouteAllowed(route) ? route : null,
    );
  }

  final String title;
  final String body;
  final String? actionRoute;

  Map<String, dynamic> toJson() => {'title': title, 'body': body, 'action_route': ?actionRoute};

  @override
  bool operator ==(Object other) =>
      other is AdviceTip && other.title == title && other.body == body && other.actionRoute == actionRoute;

  @override
  int get hashCode => Object.hash(title, body, actionRoute);
}

/// Today's "প্রস্তুতি এআই-এর পরামর্শ" (row of `ai_daily_advice`, or the
/// `daily-advice` function's answer). Empty when the learner has no data yet.
@immutable
class DailyAdvice {
  const DailyAdvice({
    required this.date,
    required this.locale,
    this.tips = const [],
    this.generatedAt,
    this.hasData = true,
    this.unchanged = false,
  });

  /// "Nothing to show" (no data yet, or today's allowance is used up).
  factory DailyAdvice.empty(String locale) => DailyAdvice(date: BdTime.todayIso(), locale: locale, hasData: false);

  factory DailyAdvice.fromJson(Map<String, dynamic> j, {String? fallbackLocale}) {
    final stats = j.obj('stats');
    return DailyAdvice(
      date: j.str('advice_date', BdTime.todayIso()),
      locale: j.str('locale', fallbackLocale ?? 'bn'),
      tips: j.list('tips', AdviceTip.fromJson).where((t) => t.title.isNotEmpty || t.body.isNotEmpty).toList(),
      generatedAt: j.date('created_at'),
      hasData: stats['has_data'] != false,
      unchanged: j['cached'] == 'unchanged',
    );
  }

  /// Bangladesh day the advice was written for (`yyyy-MM-dd`).
  final String date;
  final String locale;
  final List<AdviceTip> tips;
  final DateTime? generatedAt;
  final bool hasData;

  /// A refresh found nothing new in the learner's data (same advice back).
  final bool unchanged;

  bool get isEmpty => tips.isEmpty;

  bool get isToday => date == BdTime.todayIso();

  /// The advice day as a date (for "from 10 October" on an offline copy).
  DateTime? get day => DateTime.tryParse('${date}T00:00:00Z');

  Map<String, dynamic> toJson() => {
    'advice_date': date,
    'locale': locale,
    'tips': [for (final t in tips) t.toJson()],
    'created_at': generatedAt?.toIso8601String(),
    'stats': {'has_data': hasData},
  };
}
