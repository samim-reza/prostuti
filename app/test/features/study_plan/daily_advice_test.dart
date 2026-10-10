// Fakes rethrow whatever error object the test injects.
// ignore_for_file: only_throw_errors
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/features/study_plan/application/daily_advice_providers.dart';
import 'package:prostuti/features/study_plan/data/daily_advice_models.dart';
import 'package:prostuti/features/study_plan/data/daily_advice_repository.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/ai_advice_card.dart';

class _FakeApi implements DailyAdviceApi {
  Map<String, dynamic>? row;
  Map<String, dynamic> Function(bool refresh) onGenerate = (_) => _json();
  Object? generateError;
  Completer<void>? gate;
  final calls = <String>[];

  @override
  String get userId => 'u1';

  @override
  Future<Map<String, dynamic>?> stored(String locale) async {
    calls.add('stored:$locale');
    return row;
  }

  @override
  Future<Map<String, dynamic>> generate(String locale, {required bool refresh}) async {
    calls.add('generate:$locale:$refresh');
    await gate?.future;
    if (generateError != null) throw generateError!;
    return onGenerate(refresh);
  }
}

Map<String, dynamic> _json({String? date, List<Map<String, dynamic>>? tips, String? cached, bool hasData = true}) => {
  'advice_date': date ?? BdTime.todayIso(),
  'locale': 'bn',
  'tips':
      tips ??
      [
        {
          'title': 'দুর্বল টপিক: পাটিগণিত',
          'body': 'আজ পাটিগণিতের ২০টি প্রশ্ন অনুশীলন করুন।',
          'action_route': '/practice?topic=801',
        },
        {'title': 'আজকের নোট', 'body': 'আজকের সাম্প্রতিক নোট পড়ুন।', 'action_route': '/notes'},
        {'title': 'পড়ার ধারা', 'body': 'আজও অন্তত একটি কাজ শেষ করুন।'},
      ],
  'stats': {'has_data': hasData},
  'created_at': '2026-10-11T02:15:00Z',
  'cached': ?cached,
};

void main() {
  group('models', () {
    test('route allowlist', () {
      for (final r in ['/notes', '/daily-exam', '/wrong-answers', '/exams', '/plan', '/practice?topic=801']) {
        expect(isAdviceRouteAllowed(r), isTrue, reason: r);
      }
      for (final r in ['/admin', 'https://evil.example', '/practice?topic=1&track=x', '/settings', '']) {
        expect(isAdviceRouteAllowed(r), isFalse, reason: r);
      }
    });

    test('fromJson drops routes outside the allowlist and empty tips', () {
      final a = DailyAdvice.fromJson(
        _json(
          tips: [
            {'title': 'A', 'body': 'a', 'action_route': '/admin'},
            {'title': 'B', 'body': 'b', 'action_route': '/practice?topic=12'},
            {'title': ' ', 'body': ''},
          ],
        ),
      );
      expect(a.tips, hasLength(2));
      expect(a.tips.first.actionRoute, isNull);
      expect(a.tips.last.actionRoute, '/practice?topic=12');
      expect(a.isToday, isTrue);
      expect(a.generatedAt, DateTime.utc(2026, 10, 11, 2, 15));
    });

    test('round-trips through the cache encoding', () {
      final a = DailyAdvice.fromJson(_json());
      final b = DailyAdvice.fromJson(a.toJson());
      expect(b.tips, a.tips);
      expect(b.date, a.date);
      expect(b.generatedAt, a.generatedAt);
    });

    test('flags: unchanged, no data, empty', () {
      expect(DailyAdvice.fromJson(_json(cached: 'unchanged')).unchanged, isTrue);
      final none = DailyAdvice.fromJson(_json(tips: const [], hasData: false));
      expect(none.hasData, isFalse);
      expect(none.isEmpty, isTrue);
      expect(DailyAdvice.empty('en').isEmpty, isTrue);
    });
  });

  group('repository', () {
    late _FakeApi api;
    late CacheStore store;
    late DailyAdviceRepository repo;

    setUp(() async {
      api = _FakeApi();
      store = await CacheStore.inMemory();
      repo = DailyAdviceRepository.withApi(api, CachedFetcher(store));
    });

    test('stored row: one RPC, no function call, then served from cache', () async {
      api.row = _json();
      final a = await repo.advice('bn');
      expect(a.tips, hasLength(3));
      await repo.advice('bn');
      expect(api.calls, ['stored:bn']);
      expect(repo.peek('bn')!.fresh, isTrue);
    });

    test('no row yet: the function runs once and the result is cached', () async {
      final a = await repo.advice('bn');
      expect(a.tips, hasLength(3));
      await repo.advice('bn');
      expect(api.calls, ['stored:bn', 'generate:bn:false']);
    });

    test('rate limited auto-generation hides the card instead of failing', () async {
      api.generateError = const RateLimitFailure(action: 'rate_limited', retryAfterSeconds: 3600);
      final a = await repo.advice('bn');
      expect(a.isEmpty, isTrue);
    });

    test('other failures propagate when nothing is cached', () async {
      api.generateError = const ServerFailure('server_error');
      await expectLater(repo.advice('bn'), throwsA(isA<ServerFailure>()));
    });

    test("an earlier day's copy is not peeked and is re-fetched", () async {
      await store.write('advice:u1:bn', _json(date: '2026-01-01'), const Duration(days: 1));
      expect(repo.peek('bn'), isNull);
      api.row = _json();
      final a = await repo.advice('bn');
      expect(a.isToday, isTrue);
      expect(api.calls, ['stored:bn']);
    });

    test('regenerate asks for a refresh and updates the cache', () async {
      api.row = _json();
      await repo.advice('bn');
      api.onGenerate = (refresh) => _json(
        tips: const [
          {'title': 'নতুন', 'body': 'নতুন পরামর্শ', 'action_route': '/wrong-answers'},
        ],
      );
      final a = await repo.regenerate('bn');
      expect(a.tips.single.title, 'নতুন');
      expect(api.calls.last, 'generate:bn:true');
      expect(repo.peek('bn')!.value.tips.single.actionRoute, '/wrong-answers');
    });
  });

  group('provider', () {
    late _FakeApi api;
    late ProviderContainer container;

    setUp(() async {
      api = _FakeApi();
      final store = await CacheStore.inMemory();
      container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('u1'),
          cacheStoreProvider.overrideWithValue(store),
          dailyAdviceRepositoryProvider.overrideWithValue(DailyAdviceRepository.withApi(api, CachedFetcher(store))),
        ],
      );
      addTearDown(container.dispose);
    });

    test('loads today in the UI language (Bangla by default)', () async {
      final a = await container.read(dailyAdviceProvider.future);
      expect(a.tips, hasLength(3));
      expect(api.calls.first, 'stored:bn');
    });

    test('regenerate shows the spinner state and keeps advice on failure', () async {
      await container.read(dailyAdviceProvider.future);
      api
        ..gate = Completer<void>()
        ..generateError = const RateLimitFailure(action: 'rate_limited');
      final future = container.read(dailyAdviceProvider.notifier).regenerate();
      expect(container.read(dailyAdviceRefreshingProvider), isTrue);
      api.gate!.complete();
      await expectLater(future, throwsA(isA<RateLimitFailure>()));
      expect(container.read(dailyAdviceRefreshingProvider), isFalse);
      expect(container.read(dailyAdviceProvider).value!.tips, hasLength(3));
    });

    test('refreshDailyAdvice re-evaluates quietly and never throws', () async {
      api.onGenerate = (refresh) => _json(cached: refresh ? 'unchanged' : null);
      await refreshDailyAdvice(container.read);
      expect(api.calls, ['stored:bn', 'generate:bn:false', 'generate:bn:true']);
      expect(container.read(dailyAdviceProvider).value!.unchanged, isTrue);

      api.generateError = const NetworkFailure();
      await refreshDailyAdvice(container.read); // swallowed
      expect(container.read(dailyAdviceProvider).value!.tips, hasLength(3));
    });
  });

  group('AiAdviceCard', () {
    Future<_FakeApi> pump(
      WidgetTester tester, {
      Map<String, dynamic>? row,
      Map<String, dynamic> Function(bool refresh)? generate,
    }) async {
      final api = _FakeApi()..row = row;
      if (generate != null) api.onGenerate = generate;
      final store = await CacheStore.inMemory();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('u1'),
            cacheStoreProvider.overrideWithValue(store),
            dailyAdviceRepositoryProvider.overrideWithValue(DailyAdviceRepository.withApi(api, CachedFetcher(store))),
          ],
          retry: (_, _) => null,
          child: const MaterialApp(
            locale: Locale('bn'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: SingleChildScrollView(child: AiAdviceCard())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('shows the title, numbered tips and a refresh button', (tester) async {
      await pump(tester, row: _json());
      expect(find.text('প্রস্তুতি এআই-এর পরামর্শ'), findsOneWidget);
      expect(find.text('দুর্বল টপিক: পাটিগণিত'), findsOneWidget);
      expect(find.text('আজকের নোট'), findsOneWidget);
      expect(find.text('১'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2)); // tips with a screen
      expect(find.textContaining('হালনাগাদ'), findsOneWidget);
    });

    testWidgets('refresh with nothing new says so', (tester) async {
      final api = await pump(tester, row: _json());
      api.onGenerate = (_) => _json(cached: 'unchanged');
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();
      expect(api.calls.last, 'generate:bn:true');
      expect(find.text('নতুন কোনো পরিবর্তন নেই — পরামর্শ ইতিমধ্যে হালনাগাদ আছে'), findsOneWidget);
    });

    testWidgets('renders nothing for a learner without data', (tester) async {
      final api = await pump(tester, generate: (_) => _json(tips: const [], hasData: false));
      expect(api.calls, ['stored:bn', 'generate:bn:false']);
      expect(find.text('প্রস্তুতি এআই-এর পরামর্শ'), findsNothing);
      expect(find.byType(Card), findsNothing);
    });
  });
}
