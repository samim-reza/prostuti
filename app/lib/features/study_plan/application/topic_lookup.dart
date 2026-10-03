import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';

/// Subject/topic names for routine items, resolved from the cached catalog.
@immutable
class TopicLookup {
  const TopicLookup({this.subjects = const {}, this.topics = const {}});

  factory TopicLookup.from(List<Subject> list) {
    final subjects = <int, Subject>{};
    final topics = <int, ({Subject subject, Topic topic})>{};
    for (final s in list) {
      subjects[s.id] = s;
      for (final t in s.topics) {
        topics[t.id] = (subject: s, topic: t);
      }
    }
    return TopicLookup(subjects: subjects, topics: topics);
  }

  static const empty = TopicLookup();

  final Map<int, Subject> subjects;
  final Map<int, ({Subject subject, Topic topic})> topics;

  Subject? subjectFor({int? subjectId, int? topicId}) =>
      (subjectId == null ? null : subjects[subjectId]) ?? (topicId == null ? null : topics[topicId]?.subject);

  Topic? topic(int? topicId) => topicId == null ? null : topics[topicId]?.topic;
}

/// O(1) lookups, rebuilt only when the subject list changes.
final topicLookupProvider = Provider<TopicLookup>((ref) {
  final list = ref.watch(subjectsProvider.select((s) => s.value));
  return list == null ? TopicLookup.empty : TopicLookup.from(list);
});
