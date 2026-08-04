import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
import 'package:watch_app/features/reader/novel_reader_screen.dart';

/// A fake reading-capable source that hands back canned text per chapter
/// URL — mirrors `_FakeReadingProvider` in reading_leaf_routing_test.dart,
/// with per-URL text added so a widget test can tell chapters apart.
class _FakeReadingProvider implements BaseProvider, ReadingProvider {
  _FakeReadingProvider(this.sourceId, this.textByUrl);

  @override
  final String sourceId;
  final Map<String, String> textByUrl;

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
  Future<List<PageImage>> getPages(String chapterUrl) =>
      throw UnimplementedError();

  @override
  Future<ChapterText> getText(String chapterUrl) async =>
      ChapterText(html: '<p>${textByUrl[chapterUrl] ?? 'missing'}</p>');
}

/// Records every `flush` value passed to [ReadHistory.save] (synchronously,
/// before delegating to the real implementation) so the carry-forward
/// requirement — flush on chapter change + on dispose — is provable without
/// reaching into private reader state.
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

void main() {
  // AniyomiManager/ProviderManager construction needs the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('novelSpans', () {
    test('paragraphs, bold/italic, tags stripped', () {
      // NOTE: the brief's literal fixture used '<p>Next</p>' as the second
      // paragraph and then asserted `isNot(contains('x'))` for the stripped
      // script tag — but "Next" itself contains an 'x', which makes that
      // assertion fail unconditionally regardless of whether script
      // stripping works. Swapped to "Then" (same shape, no incidental 'x')
      // so the assertion tests what it says it tests.
      final spans = novelSpans(
        '<p>Hello <b>bold</b> and <i>it</i></p><p>Then</p>'
        '<script>x</script>',
        const TextStyle(),
      );
      final text = spans.map((s) => s.toPlainText()).join();
      expect(text, contains('Hello bold and it'));
      expect(text, contains('\n')); // paragraph break
      expect(text, isNot(contains('x'))); // script stripped
      expect(spans.any((s) => s.style?.fontWeight == FontWeight.bold), isTrue);
    });
  });

  group('NovelReaderScreen', () {
    late Directory dir;
    late _SpyReadHistory spyHistory;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('novel_reader_test');
      Hive.init(dir.path);
      IncognitoMode.notifier.value = false;

      await ReadStore.init();
      await ReadHistory.init();
      await ReaderPrefs.init();

      sl.registerSingleton<ReadStore>(ReadStore());
      spyHistory = _SpyReadHistory(SupabaseService(), () => null);
      sl.registerSingleton<ReadHistory>(spyHistory);
      sl.registerSingleton<ReaderPrefs>(ReaderPrefs());

      final ani = AniyomiManager();
      ani.register(
        _FakeReadingProvider('ani:n', {
          'u1': 'chapter one text',
          'u2': 'chapter two text',
        }),
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
      await sl.reset();
      await Hive.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Widget harness() => MaterialApp(
      home: NovelReaderScreen(
        sourceId: 'ani:n',
        showId: 'b1',
        showTitle: 'Book',
        cover: null,
        chapters: [chapter('c1', 'u1'), chapter('c2', 'u2')],
        startIndex: 0,
      ),
    );

    testWidgets('renders chapter text and advances to next chapter', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.textContaining('chapter one text'), findsOneWidget);

      // chrome → next
      await tester.tap(find.byType(SingleChildScrollView));
      await tester.pumpAndSettle();

      // Advancing writes a flushed ReadHistory entry, which is real Hive
      // I/O — run it under runAsync so the fire-and-forget write actually
      // resolves instead of dangling into tearDown's Hive.close().
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.skip_next_rounded));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(find.textContaining('chapter two text'), findsOneWidget);

      // Explicitly dispose the reader (under runAsync, same reason as
      // above) instead of relying on the framework's between-test teardown
      // — dispose() also fire-and-forgets a flushed ReadHistory write, and
      // letting that dangle outside runAsync hangs tearDown's Hive.close().
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
    });

    testWidgets('flushes ReadHistory on chapter change and on dispose', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SingleChildScrollView));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.skip_next_rounded));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(spyHistory.flushCalls, contains(true));
      final flushesAfterChapterChange = spyHistory.flushCalls
          .where((f) => f)
          .length;
      expect(flushesAfterChapterChange, greaterThanOrEqualTo(1));

      // Tear the whole tree down — this disposes NovelReaderScreen's State.
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      final flushesAfterDispose = spyHistory.flushCalls.where((f) => f).length;
      expect(flushesAfterDispose, greaterThan(flushesAfterChapterChange));
    });
  });
}
