import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/application/exam_clock.dart';

@immutable
class SubjectShare {
  const SubjectShare(this.subject, this.count);
  final Subject subject;
  final int count;
}

/// Mirrors `start_exam('model_test')`: questions are apportioned to the
/// track's subjects by marks with the largest-remainder method, so a test
/// always has exactly `size` questions. Without a track this is the BCS
/// pattern (200 marks, 36 s per question → 200 questions in 120 minutes).
abstract final class ModelTestPlan {
  static const sizes = [25, 50, 100, 200];
  static const fullMarks = 200;

  /// [subjects] must be in catalog `sort` order: it breaks remainder ties,
  /// exactly like the server.
  static List<SubjectShare> distribution(List<Subject> subjects, int size, {ExamTrack? track}) {
    int marksOf(Subject s) => track == null ? s.bcsMarks : (track.distribution[s.code] ?? 0);
    final full = track?.fullMarks ?? fullMarks;
    final graded = [
      for (final s in subjects)
        if (marksOf(s) > 0) s,
    ];
    // Integer arithmetic: share = (marks × size) / full = count + remainder/full.
    final counts = [for (final s in graded) marksOf(s) * size ~/ full];
    final remainders = [for (final s in graded) marksOf(s) * size % full];
    final byRemainder = List.generate(graded.length, (i) => i)
      ..sort((a, b) {
        final c = remainders[b].compareTo(remainders[a]);
        return c != 0 ? c : a.compareTo(b);
      });
    final left = size - counts.fold<int>(0, (sum, c) => sum + c);
    for (final i in byRemainder.take(math.max(0, left))) {
      counts[i]++;
    }
    return [
      for (final (i, s) in graded.indexed)
        if (counts[i] > 0) SubjectShare(s, counts[i]),
    ];
  }

  static int totalQuestions(List<SubjectShare> shares) => shares.fold(0, (sum, s) => sum + s.count);

  /// Exam duration at the track's pace; falls back to `size` questions while
  /// subjects are loading.
  static Duration duration(int size, {List<SubjectShare>? shares, ExamTrack? track}) {
    final count = (shares == null || shares.isEmpty) ? size : totalQuestions(shares);
    if (track != null) return Duration(seconds: count * track.secondsPerQuestion);
    return ExamTiming.forQuestions(count, withMinimum: false);
  }
}
