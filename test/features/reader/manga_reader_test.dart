import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/models/episode.dart';
import 'package:watch_app/core/models/home_section.dart';
import 'package:watch_app/core/models/media_detail.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/page_content.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/core/playback/playback_prefs.dart';
import 'package:watch_app/core/privacy/incognito_mode.dart';
import 'package:watch_app/core/provider/base_provider.dart';
import 'package:watch_app/core/provider/cloudstream_provider.dart';
import 'package:watch_app/core/provider/provider_manager.dart';
import 'package:watch_app/core/provider/reading_provider.dart';
import 'package:watch_app/core/reading/read_history.dart';
import 'package:watch_app/core/reading/read_store.dart';
import 'package:watch_app/core/reading/reader_prefs.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/core/state/active_source_cubit.dart';
import 'package:watch_app/core/supabase/supabase_service.dart';
import 'package:watch_app/features/reader/manga_reader_screen.dart';

// ── Pure-logic tests ────────────────────────────────────────────────────────

void _pureLogicTests() {
  group('zoneFor', () {
    test('ltr: left third is previous, right third is next', () {
      expect(zoneFor(10, 300, 'ltr'), ReaderTapZone.previous);
      expect(zoneFor(290, 300, 'ltr'), ReaderTapZone.next);
    });

    test('rtl: swaps previous/next', () {
      expect(zoneFor(10, 300, 'rtl'), ReaderTapZone.next);
      expect(zoneFor(290, 300, 'rtl'), ReaderTapZone.previous);
    });

    test('center third is chrome in both directions', () {
      expect(zoneFor(150, 300, 'ltr'), ReaderTapZone.chrome);
      expect(zoneFor(150, 300, 'rtl'), ReaderTapZone.chrome);
    });

    test('vertical: every dx is chrome — no left/right paging', () {
      expect(zoneFor(10, 300, 'vertical'), ReaderTapZone.chrome);
      expect(zoneFor(150, 300, 'vertical'), ReaderTapZone.chrome);
      expect(zoneFor(290, 300, 'vertical'), ReaderTapZone.chrome);
    });
  });

  group('preloadWindow', () {
    test('returns the next 3 indices', () {
      expect(preloadWindow(0, 10), [1, 2, 3]);
      expect(preloadWindow(5, 10), [6, 7, 8]);
    });

    test('clamps to the end of the chapter', () {
      expect(preloadWindow(8, 10), [9]);
      expect(preloadWindow(9, 10), <int>[]);
    });

    test('empty chapter yields nothing', () {
      expect(preloadWindow(0, 0), <int>[]);
    });
  });

  group('clampPageIndex', () {
    test('in-range index passes through', () {
      expect(clampPageIndex(3, 10), 3);
    });

    test('negative clamps to 0', () {
      expect(clampPageIndex(-1, 10), 0);
    });

    test('out-of-range clamps to the last page', () {
      expect(clampPageIndex(99, 10), 9);
    });

    test('an empty/unknown chapter clamps to 0', () {
      expect(clampPageIndex(5, 0), 0);
    });
  });

  group('estimateIndexFromScroll', () {
    test('top of scroll is page 0, bottom is the last page', () {
      expect(estimateIndexFromScroll(0, 1000, 5), 0);
      expect(estimateIndexFromScroll(1000, 1000, 5), 4);
    });

    test('midway scroll lands near the middle page', () {
      expect(estimateIndexFromScroll(500, 1000, 5), 2);
    });

    test(
      'a chapter that fits on screen (no scroll extent) is the last page',
      () {
        expect(estimateIndexFromScroll(0, 0, 5), 4);
      },
    );

    test('empty chapter is page 0', () {
      expect(estimateIndexFromScroll(0, 1000, 0), 0);
    });
  });
}

// ── Widget-level fakes ───────────────────────────────────────────────────────

/// A fake reading-capable source that hands back canned pages per chapter
/// URL — mirrors `_FakeReadingProvider` in novel_reader_test.dart, with
/// `getPages` implemented instead of `getText`.
class _FakeReadingProvider implements BaseProvider, ReadingProvider {
  _FakeReadingProvider(this.sourceId, this.pagesByUrl);

  @override
  final String sourceId;
  final Map<String, List<PageImage>> pagesByUrl;

  @override
  String get displayName => sourceId;

  @override
  Future<ProviderInfo> getInfo() => throw UnimplementedError();

  @override
  Future<List<HomeSection>?> getHome({String category = 'sub'}) =>
      throw UnimplementedError();

  @override
  Future<List<MediaItem>> popular({
    String category = 'sub',
    int dateRange = 7,
    int page = 1,
  }) => throw UnimplementedError();

  @override
  Future<List<MediaItem>> search(
    String query,
    int page, {
    String category = '',
  }) => throw UnimplementedError();

  @override
  Future<MediaDetail> getDetail(String url, {String category = 'sub'}) =>
      throw UnimplementedError();

  @override
  Future<List<Episode>> getEpisodes(String url, {String category = 'sub'}) =>
      throw UnimplementedError();

  @override
  Future<List<VideoSource>> getVideoSources(
    String episodeUrl, {
    bool fast = false,
  }) => throw UnimplementedError();

  @override
  Future<List<PageImage>> getPages(String chapterUrl) async =>
      pagesByUrl[chapterUrl] ?? const [];

  @override
  Future<ChapterText> getText(String chapterUrl) => throw UnimplementedError();
}

/// A reading source whose `getPages` throws on the first call and succeeds
/// on every call after — for the error/retry path.
class _FlakyReadingProvider implements BaseProvider, ReadingProvider {
  _FlakyReadingProvider(this.sourceId, this.pages);

  @override
  final String sourceId;
  final List<PageImage> pages;
  int calls = 0;

  @override
  String get displayName => sourceId;

  @override
  Future<ProviderInfo> getInfo() => throw UnimplementedError();

  @override
  Future<List<HomeSection>?> getHome({String category = 'sub'}) =>
      throw UnimplementedError();

  @override
  Future<List<MediaItem>> popular({
    String category = 'sub',
    int dateRange = 7,
    int page = 1,
  }) => throw UnimplementedError();

  @override
  Future<List<MediaItem>> search(
    String query,
    int page, {
    String category = '',
  }) => throw UnimplementedError();

  @override
  Future<MediaDetail> getDetail(String url, {String category = 'sub'}) =>
      throw UnimplementedError();

  @override
  Future<List<Episode>> getEpisodes(String url, {String category = 'sub'}) =>
      throw UnimplementedError();

  @override
  Future<List<VideoSource>> getVideoSources(
    String episodeUrl, {
    bool fast = false,
  }) => throw UnimplementedError();

  @override
  Future<List<PageImage>> getPages(String chapterUrl) async {
    calls++;
    if (calls == 1) throw Exception('network blip');
    return pages;
  }

  @override
  Future<ChapterText> getText(String chapterUrl) => throw UnimplementedError();
}

/// Records every `flush` value passed to [ReadHistory.save] (synchronously,
/// before delegating to the real implementation) so the carry-forward
/// requirement — flush on chapter change + on dispose — is provable without
/// reaching into private reader state. Same shape as novel_reader_test.dart's
/// spy.
class _SpyReadHistory extends ReadHistory {
  _SpyReadHistory(super.service, super.currentUserId);

  final List<bool> flushCalls = [];

  @override
  Future<void> save(ReadEntry e, {bool flush = false}) {
    flushCalls.add(flush);
    return super.save(e, flush: flush);
  }
}

Episode chapter(String id, String url) => Episode(id: id, title: id, url: url);

List<PageImage> pages(int count, {String prefix = 'https://example.com/p'}) =>
    List.generate(count, (i) => PageImage(url: '$prefix$i.jpg'));

/// Pumps a bounded, small number of frames instead of `pumpAndSettle()`.
///
/// Not `pumpAndSettle()` because every page's loading placeholder used to be
/// an indeterminate `CircularProgressIndicator`, which — against an
/// unreachable fake URL in this network-less sandbox — animates forever and
/// never lets `pumpAndSettle()` see "no more frames scheduled". The
/// placeholders are now static (`ColoredBox`, matching
/// poster_card.dart/continue_card.dart's convention), so this is moot, but
/// bounded pumping is kept regardless — it's simpler to reason about than
/// "settle, but only sometimes."
///
/// Pumps past `kDoubleTapTimeout` (~300ms): every page's GestureDetector
/// registers both `onTapUp` (tap zones) and `onDoubleTap` (zoom), so Flutter
/// delays resolving a single tap until it's sure a second tap isn't coming.
/// A shorter pump budget would assert before that single tap ever fires.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _pureLogicTests();

  group('MangaReaderScreen', () {
    late Directory dir;
    late _SpyReadHistory spyHistory;
    late AniyomiManager ani;

    setUp(() async {
      // CachedNetworkImage (flutter_cache_manager) hits path_provider to find
      // a disk-cache directory; without a mock handler that throws
      // MissingPluginException on the first real image load. Same fix as
      // reading_detail_routing_test.dart (Task 11's own test for this
      // routing).
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => '/tmp',
          );

      // The global image cache persists across tests in this file — clear it
      // so one test's precache calls can't leave stale entries that make a
      // later test's cache assertions pass for the wrong reason.
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      dir = await Directory.systemTemp.createTemp('manga_reader_test');
      Hive.init(dir.path);
      IncognitoMode.notifier.value = false;

      await ReadStore.init();
      await ReadHistory.init();
      await ReaderPrefs.init();

      sl.registerSingleton<ReadStore>(ReadStore());
      spyHistory = _SpyReadHistory(SupabaseService(), () => null);
      sl.registerSingleton<ReadHistory>(spyHistory);
      sl.registerSingleton<ReaderPrefs>(ReaderPrefs());

      ani = AniyomiManager();
      ani.register(
        _FakeReadingProvider('ani:m', {'u1': pages(3), 'u2': pages(2)}),
      );
      sl.registerSingleton<SourceRepository>(
        SourceRepository(
          manager: ProviderManager(dio: Dio()),
          csManager: CloudStreamManager(),
          aniManager: ani,
          activeSource: ActiveSourceCubit(),
          prefs: PlaybackPrefs(),
        ),
      );
    });

    tearDown(() async {
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await sl.reset();
      await Hive.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Widget harness({int startIndex = 0}) => MaterialApp(
      home: MangaReaderScreen(
        sourceId: 'ani:m',
        showId: 'm1',
        showTitle: 'Some Manga',
        cover: null,
        chapters: [chapter('c1', 'u1'), chapter('c2', 'u2')],
        startIndex: startIndex,
      ),
    );

    Future<void> disposeHarness(WidgetTester tester) async {
      // Real Hive I/O happens fire-and-forget on dispose (flushed
      // ReadHistory write) — run under runAsync so it actually resolves
      // instead of dangling into tearDown's Hive.close(), same as
      // novel_reader_test.dart.
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
    }

    // flutter_cache_manager's cache-info repo (sqflite-backed on macOS/iOS/
    // Android) throws `StateError: databaseFactory not initialized` the
    // first time *any* CachedNetworkImage in this whole test process ever
    // resolves — `flutter test` never registers a sqflite plugin, and there's
    // no first-party way to fake `databaseFactory` without a new dependency.
    // The failure is one-time only: flutter_cache_manager doesn't retry its
    // metadata-store lookup after the first failure, so every image after
    // this one silently falls straight through to a network fetch instead.
    // Deliberately eating that one-time failure here, in its own test, keeps
    // every other test in this file clean — see the task report for the
    // full investigation (this was verified empirically, not assumed).
    testWidgets(
      "warm-up: absorb flutter_cache_manager's one-time cache-store init "
      'failure before any real test runs',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CachedNetworkImage(
              imageUrl: 'https://example.com/warmup.jpg',
            ),
          ),
        );
        await settle(tester);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('ltr direction renders a non-reversed PageView', (
      tester,
    ) async {
      await tester.runAsync(() => sl<ReaderPrefs>().setDirection('ltr'));
      await tester.pumpWidget(harness());
      await settle(tester);

      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      final pv = tester.widget<PageView>(find.byType(PageView));
      expect(pv.reverse, isFalse);

      await disposeHarness(tester);
    });

    testWidgets('rtl direction renders a reversed PageView', (tester) async {
      await tester.runAsync(() => sl<ReaderPrefs>().setDirection('rtl'));
      await tester.pumpWidget(harness());
      await settle(tester);

      expect(find.byType(PageView), findsOneWidget);
      final pv = tester.widget<PageView>(find.byType(PageView));
      expect(pv.reverse, isTrue);

      await disposeHarness(tester);
    });

    testWidgets('vertical direction renders a ListView, not a PageView', (
      tester,
    ) async {
      await tester.runAsync(() => sl<ReaderPrefs>().setDirection('vertical'));
      await tester.pumpWidget(harness());
      await settle(tester);

      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(PageView), findsNothing);

      await disposeHarness(tester);
    });

    testWidgets('jumping to a page saves it as the ReadStore position', (
      tester,
    ) async {
      await tester.runAsync(() => sl<ReaderPrefs>().setDirection('ltr'));
      await tester.pumpWidget(harness());
      await settle(tester);

      final pv = tester.widget<PageView>(find.byType(PageView));
      await tester.runAsync(() async {
        pv.controller!.jumpToPage(1); // the chapter's 2nd page (index 1)
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settle(tester);

      final saved = sl<ReadStore>().get('ani:m', 'm1', 'c1');
      expect(saved, isNotNull);
      expect(saved!.pos, 1);
      expect(saved.total, 3);

      // Pin the other half of the carry-forward contract: a routine page
      // turn (no chapter change, no dispose) must never flush. A regression
      // that flips _saveProgress's default to flush: true would still leave
      // every other assertion in this file green while pushing to Supabase
      // on every page turn.
      expect(spyHistory.flushCalls, everyElement(isFalse));

      await disposeHarness(tester);
    });

    testWidgets('flushes ReadHistory on chapter change and on dispose', (
      tester,
    ) async {
      await tester.runAsync(() => sl<ReaderPrefs>().setDirection('ltr'));
      await tester.pumpWidget(harness());
      await settle(tester);

      // Chrome (bottom bar) starts hidden — reveal it so the skip_next icon
      // exists to tap.
      await tester.tapAt(const Offset(400, 300));
      await settle(tester);

      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.skip_next_rounded));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settle(tester);

      expect(spyHistory.flushCalls, contains(true));
      final flushesAfterChapterChange = spyHistory.flushCalls
          .where((f) => f)
          .length;
      expect(flushesAfterChapterChange, greaterThanOrEqualTo(1));

      await disposeHarness(tester);

      final flushesAfterDispose = spyHistory.flushCalls.where((f) => f).length;
      expect(flushesAfterDispose, greaterThan(flushesAfterChapterChange));
    });

    testWidgets(
      'a pages() failure shows the error state (not a crash, not a stuck '
      'spinner), and Retry re-fetches successfully',
      (tester) async {
        ani.register(_FlakyReadingProvider('ani:m', pages(3)));

        await tester.pumpWidget(harness());
        await settle(tester);

        expect(find.text('Retry'), findsOneWidget);
        expect(find.byType(PageView), findsNothing);

        await tester.tap(find.text('Retry'));
        await settle(tester);

        expect(find.text('Retry'), findsNothing);
        expect(find.byType(PageView), findsOneWidget);

        await disposeHarness(tester);
      },
    );

    testWidgets('reopening a chapter restores its saved page', (tester) async {
      await tester.runAsync(() => sl<ReaderPrefs>().setDirection('ltr'));
      // Pre-seed a saved position: page index 2 of a 3-page chapter.
      await tester.runAsync(
        () => sl<ReadStore>().save('ani:m', 'm1', 'c1', pos: 2, total: 3),
      );

      await tester.pumpWidget(harness());
      await settle(tester);

      final pv = tester.widget<PageView>(find.byType(PageView));
      expect(pv.controller!.page, closeTo(2, 0.01));

      await disposeHarness(tester);
    });

    testWidgets('page/chapter header shows "ch n · pg i/N"', (tester) async {
      await tester.runAsync(() => sl<ReaderPrefs>().setDirection('ltr'));
      await tester.pumpWidget(harness());
      await settle(tester);

      // Chrome starts hidden — tap the chrome (center) zone to reveal it.
      await tester.tapAt(const Offset(400, 300)); // center third
      await settle(tester);

      expect(find.textContaining('ch 1 · pg 1/3'), findsOneWidget);

      await disposeHarness(tester);
    });

    testWidgets(
      "a page's CachedNetworkImage receives its real imageUrl and headers "
      '(the exact detail that breaks CF-walled sources if dropped)',
      (tester) async {
        await tester.runAsync(() => sl<ReaderPrefs>().setDirection('ltr'));
        ani.register(
          _FakeReadingProvider('ani:m', {
            'u1': [
              PageImage(
                url: 'https://example.com/cf-page.jpg',
                headers: const {'cf-clearance': 'abc123'},
              ),
            ],
          }),
        );

        await tester.pumpWidget(harness());
        await settle(tester);

        final img = tester.widget<CachedNetworkImage>(
          find.byType(CachedNetworkImage),
        );
        expect(img.imageUrl, 'https://example.com/cf-page.jpg');
        expect(img.httpHeaders, const {'cf-clearance': 'abc123'});

        await disposeHarness(tester);
      },
    );

    testWidgets(
      'landing on a page precaches exactly the next 3 pages, not more',
      (tester) async {
        await tester.runAsync(() => sl<ReaderPrefs>().setDirection('ltr'));
        final sixPages = pages(6);
        ani.register(_FakeReadingProvider('ani:m', {'u1': sixPages}));

        await tester.pumpWidget(harness());
        await settle(tester);

        final cache = PaintingBinding.instance.imageCache;
        Future<bool> tracked(int i) async {
          final key = await CachedNetworkImageProvider(
            sixPages[i].url,
          ).obtainKey(ImageConfiguration.empty);
          return cache.statusForKey(key).tracked;
        }

        // preloadWindow(0, 6) == [1, 2, 3] — those, and only those, should be
        // registered in Flutter's global image cache.
        expect(await tracked(1), isTrue, reason: 'page 1 should be preloaded');
        expect(await tracked(2), isTrue, reason: 'page 2 should be preloaded');
        expect(await tracked(3), isTrue, reason: 'page 3 should be preloaded');
        expect(
          await tracked(4),
          isFalse,
          reason: 'page 4 is outside the 3-page preload window',
        );

        await disposeHarness(tester);
      },
    );
  });
}
