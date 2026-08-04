// Task 11: the Detail screen routes reading-type (manga/novel) titles to the
// reader instead of the video player.
//
// Harness mirrors detail_screen_tv_test.dart's lightweight GetIt stubs (no
// Hive, no platform channels), but pumps the PHONE DetailScreen with
// AppMode(isTv: false). Unlike DetailScreenTv (which reads a DetailCubit from
// an ancestor BlocProvider), DetailScreen builds its own cubit internally, so
// we just pump DetailScreen(item:) directly and let it load.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/download/download_manager.dart';
import 'package:watch_app/core/download/download_record.dart';
import 'package:watch_app/core/models/episode.dart';
import 'package:watch_app/core/models/media_detail.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/models/watch_status.dart';
import 'package:watch_app/core/playback/list_status_store.dart';
import 'package:watch_app/core/playback/my_list.dart';
import 'package:watch_app/core/playback/playback_prefs.dart';
import 'package:watch_app/core/playback/resume_store.dart';
import 'package:watch_app/core/playback/title_prefs.dart';
import 'package:watch_app/core/provider/cloudstream_provider.dart';
import 'package:watch_app/core/provider/base_provider.dart';
import 'package:watch_app/core/provider/provider_registry.dart';
import 'package:watch_app/core/reading/reader_prefs.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/core/tracker/tracker_hub.dart';
import 'package:watch_app/core/trailer/trailer_service.dart';
import 'package:watch_app/features/detail/detail_screen.dart';
import 'package:watch_app/features/reader/novel_reader_screen.dart';

// ── Minimal stubs — no Hive, no platform channels, no network ───────────────

/// Stub [SourceRepository] that returns a pre-built [MediaDetail]. Doesn't
/// implement `chapterText` — a tap into NovelReaderScreen drives it into its
/// own already-tested error state (see novel_reader_test.dart) via the
/// inherited noSuchMethod, which is exactly what we want: we're only proving
/// the PUSH happened, not re-testing the reader's load path.
class _StubSourceRepository implements SourceRepository {
  _StubSourceRepository(this._detail);
  final MediaDetail _detail;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  Future<MediaDetail> detail(
    String url, {
    String category = 'sub',
    String? sourceId,
  }) async => _detail;

  @override
  void prefetch(String url, {String? sourceId}) {}

  @override
  String get sourceId => 'test';

  @override
  bool hasSource(String id) => false;

  @override
  String displayName(String id) => id;

  @override
  List<({String id, String name})> get loadedSources => const [];
}

class _FakeTitlePrefs extends TitlePrefsStore {
  @override
  String? category(String s, String u) => null;

  @override
  Future<void> setCategory(String s, String u, String c) async {}
}

class _FakeMyListStore implements MyListStore {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  bool contains(MediaItem m) => false;

  @override
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
}

class _FakeListStatusStore implements ListStatusStore {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  WatchStatus? statusOf(MediaItem m) => null;

  @override
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
}

class _FakeResumeStore implements ResumeStore {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  ResumeMark? get(String sourceId, String showId, String episodeId) => null;
}

class _FakeProviderRegistry implements ProviderRegistry {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  ProviderRegistryEntry? entryFor(String sourceId) => null;

  @override
  List<ProviderRegistryEntry> getAll() => const [];
}

class _FakeCloudStreamManager extends ChangeNotifier
    implements CloudStreamManager {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  BaseProvider? get(String sourceId) => null;

  @override
  String? repoNameForSourceId(String sourceId) => null;

  @override
  List<CloudStreamProvider> get enabled => const [];
}

class _FakeDownloadManager extends ChangeNotifier implements DownloadManager {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  DownloadRecord? recordFor(String sourceId, String showId, String episodeId) =>
      null;
}

/// Never resolves a trailer — keeps the hero on its static (empty-cover)
/// backdrop so the media_kit-backed `_HeroTrailer` is never built, and
/// avoids a real network call to AniList/TMDB.
class _FakeTrailerService extends TrailerService {
  _FakeTrailerService() : super(Dio());

  @override
  Future<String?> youtubeId({
    required String title,
    String? englishTitle,
    required ProviderType type,
    String? year,
  }) async => null;
}

/// Hive-backed in reality; overriding the one getter the reader's build()
/// touches unconditionally avoids needing a real box.
class _FakeReaderPrefs extends ReaderPrefs {
  @override
  String get theme => 'dark';
}

/// Hive-backed in reality; overrides just the getters _openPlayer's
/// preserved anime path reads, matching the real defaults.
class _FakePlaybackPrefs extends PlaybackPrefs {
  @override
  bool get autoAddToMyList => false;

  @override
  String get defaultCategory => 'sub';
}

// ── Test data ────────────────────────────────────────────────────────────────

const _novelItem = MediaItem(
  id: 'test-novel',
  title: 'Test Novel',
  url: 'http://test/novel',
  type: ProviderType.novel,
  sourceId: 'test',
);

const _novelDetail = MediaDetail(
  id: 'test-novel',
  title: 'Test Novel',
  url: 'http://test/novel',
  type: ProviderType.novel,
  sourceId: 'test',
  episodes: [
    Episode(id: 'c1', title: 'Chapter 1', url: '/c1', number: 1),
    Episode(id: 'c2', title: 'Chapter 2', url: '/c2', number: 2),
  ],
);

const _animeItem = MediaItem(
  id: 'test-anime',
  title: 'Test Anime',
  url: 'http://test/anime',
  type: ProviderType.anime,
  sourceId: 'test',
);

const _animeDetail = MediaDetail(
  id: 'test-anime',
  title: 'Test Anime',
  url: 'http://test/anime',
  type: ProviderType.anime,
  sourceId: 'test',
  episodes: [
    Episode(id: 'e1', title: 'Episode 1', url: '/e1', number: 1),
    Episode(id: 'e2', title: 'Episode 2', url: '/e2', number: 2),
  ],
);

/// Records pushes so the anime-regression test can prove `_openPlayer`'s
/// original path ran (reached its final `Navigator.push`) WITHOUT actually
/// building `PlayerScreen` — which wires up media_kit + a dozen more
/// singletons that have no place in a lightweight widget test. `didPush`
/// fires synchronously as part of `Navigator.push`, before any rebuild, so
/// checking it right after `tester.tap()` (with no follow-up `pump()`) never
/// triggers the destination route's build.
class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
  }
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '/tmp',
        );

    await sl.reset();
    sl.registerSingleton<AppMode>(const AppMode(isTv: false));
    sl.registerSingleton<MyListStore>(_FakeMyListStore());
    sl.registerSingleton<ListStatusStore>(_FakeListStatusStore());
    sl.registerSingleton<ResumeStore>(_FakeResumeStore());
    sl.registerSingleton<ProviderRegistry>(_FakeProviderRegistry());
    sl.registerSingleton<CloudStreamManager>(_FakeCloudStreamManager());
    sl.registerSingleton<DownloadManager>(_FakeDownloadManager());
    sl.registerSingleton<TitlePrefsStore>(_FakeTitlePrefs());
    sl.registerSingleton<PlaybackPrefs>(_FakePlaybackPrefs());
    sl.registerSingleton<TrailerService>(_FakeTrailerService());
    sl.registerSingleton<TrackerHub>(TrackerHub(const []));
    sl.registerSingleton<ReaderPrefs>(_FakeReaderPrefs());
  });

  tearDown(() async {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await sl.reset();
  });

  testWidgets(
    'novel detail shows Read (not Play), no Sub/Dub toggle, no download '
    'button, and tapping a chapter pushes NovelReaderScreen',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      sl.registerSingleton<SourceRepository>(
        _StubSourceRepository(_novelDetail),
      );

      await tester.pumpWidget(
        const MaterialApp(home: DetailScreen(item: _novelItem)),
      );
      await tester.pump(); // let the cubit's load() resolve

      expect(find.text('Read'), findsWidgets);
      expect(find.text('Play'), findsNothing);

      // No Sub/Dub toggle anywhere on the page.
      expect(find.text('Sub'), findsNothing);
      expect(find.text('Dub'), findsNothing);

      // No download affordance — main button or per-chapter icon (both use
      // this glyph when shown).
      expect(find.byIcon(Icons.file_download_outlined), findsNothing);

      // Tapping a chapter row pushes NovelReaderScreen.
      expect(find.byType(NovelReaderScreen), findsNothing);
      expect(find.textContaining('Chapter 1'), findsOneWidget);
      await tester.tap(find.textContaining('Chapter 1'));
      await tester.pumpAndSettle();
      expect(find.byType(NovelReaderScreen), findsOneWidget);
    },
  );

  testWidgets(
    'anime detail keeps Play (not Read) and still pushes the player — the '
    'hard constraint: anime/movie behaviour is unchanged',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      sl.registerSingleton<SourceRepository>(
        _StubSourceRepository(_animeDetail),
      );

      final observer = _RecordingNavigatorObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: const DetailScreen(item: _animeItem),
        ),
      );
      await tester.pump(); // let the cubit's load() resolve

      expect(find.text('Play'), findsWidgets);
      expect(find.text('Read'), findsNothing);

      final before = observer.pushCount;
      // No pump() after this tap on purpose — see _RecordingNavigatorObserver.
      await tester.tap(find.text('Play').first);
      expect(observer.pushCount, before + 1);
    },
  );
}
