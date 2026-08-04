// Task 12 Parts A + B:
//  - Home's Continue Watching row swaps to Continue Reading in a reading
//    mode (manga/novel), fed by ReadHistory; anime mode renders exactly
//    today's WatchHistory-backed row (ContinueWatchingRow/ContinueSection,
//    home_screen.dart + continue_section.dart).
//  - My List's grid filters by ContentMode.matchesProvider(item.type); the
//    anime-mode filter UI (segmented control, type-filter sheet) is
//    untouched — matchesProvider is a no-op there (anime OR movie).
//
// ContinueWatchingRow/ContinueReadingRow (the actual card content — title,
// subtitle, tap wiring) are pumped directly against a resolved list, and
// ContinueSection's login/box gating is exercised without ever opening a
// real Hive box. Both deliberately avoid mounting a live
// ValueListenableBuilder over a real Hive box inside a widget test — that
// combination reproducibly hangs `flutter test` in this environment even in
// a two-line, feature-unrelated repro (bare ValueListenableBuilder over a
// freshly-opened Hive box, no ContentRow/ContinueCard/BlocBuilder involved).
// ContinueSection's reactive box-listenable wiring itself is unchanged for
// anime (copied verbatim from the shipped, working code) and structurally
// identical for reading, so it's verified by inspection + `flutter analyze`
// instead. See task-12-report.md for the full writeup.
//
// The real HomeScreen isn't pumped at all — its initState fires a one-time,
// un-DI'd update-check + real network call (UpdateService()) and opens
// community/announcement Hive boxes, none of which this feature touches.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/mode/content_mode.dart';
import 'package:watch_app/core/mode/content_mode_cubit.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/models/watch_status.dart';
import 'package:watch_app/core/playback/list_status_store.dart';
import 'package:watch_app/core/playback/my_list.dart';
import 'package:watch_app/core/playback/watch_history.dart';
import 'package:watch_app/core/reading/read_history.dart';
import 'package:watch_app/core/tracker/tracker_hub.dart';
import 'package:watch_app/features/home/continue_section.dart';
import 'package:watch_app/features/home/my_list_screen.dart';

// ── Shared fakes ─────────────────────────────────────────────────────────────

/// Bare [ContentModeCubit] stand-in: real [Cubit] behaviour (emit/state/
/// stream) via `extends`, everything ContentModeCubit-specific (setMode,
/// etc.) unreachable via `noSuchMethod` — nothing under test calls those.
class _FakeContentModeCubit extends Cubit<ContentMode>
    implements ContentModeCubit {
  _FakeContentModeCubit(super.initial);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeMyListStore implements MyListStore {
  _FakeMyListStore(this._items) : revision = ValueNotifier<int>(0);
  final List<MediaItem> _items;

  @override
  final ValueNotifier<int> revision;

  @override
  List<MediaItem> all() => List<MediaItem>.from(_items);

  @override
  bool contains(MediaItem m) => _items.any((i) => i.id == m.id);

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeListStatusStore implements ListStatusStore {
  @override
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  @override
  WatchStatus? statusOf(MediaItem m) => null;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  // ── Part A: Continue Watching / Continue Reading row content ─────────────
  // Pumped directly (no Hive) — this is what actually renders the card.

  group('ContinueWatchingRow / ContinueReadingRow content', () {
    // ContentRow wraps every card in RevealItem, which reads sl<AppMode>()
    // unconditionally (list-animation gating) — needed even though nothing
    // in these tests is TV-specific.
    setUp(() async {
      await sl.reset();
      sl.registerSingleton<AppMode>(const AppMode(isTv: false));
    });

    tearDown(() async {
      await sl.reset();
    });

    testWidgets(
      'ContinueWatchingRow renders the title, an Episode subtitle, and '
      'resumes on tap — the anime row, unchanged (regression)',
      (tester) async {
        HistoryEntry? resumed;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  ContinueWatchingRow(
                    history: [
                      HistoryEntry(
                        sourceId: 'src',
                        showId: 'show1',
                        showTitle: 'Anime Show',
                        showUrl: '/show1',
                        category: 'sub',
                        episodeId: 'e1',
                        episodeNumber: 3,
                        episodeUrl: '/e1',
                        position: const Duration(minutes: 2),
                        duration: const Duration(minutes: 24),
                        updatedAt: 1,
                      ),
                    ],
                    onSeeAll: () {},
                    onResume: (e) => resumed = e,
                    onLongPress: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Continue Watching'), findsOneWidget);
        expect(find.text('Episode 3'), findsOneWidget);

        await tester.tap(find.text('Anime Show'));
        expect(resumed?.showId, 'show1');
      },
    );

    testWidgets(
      'ContinueWatchingRow renders nothing for an empty history (regression '
      '— matches the original "hide when empty" behaviour)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  ContinueWatchingRow(
                    history: const [],
                    onSeeAll: () {},
                    onResume: (_) {},
                    onLongPress: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Continue Watching'), findsNothing);
      },
    );

    testWidgets(
      'ContinueReadingRow renders the title, a Chapter subtitle, and '
      'resumes on tap',
      (tester) async {
        ReadEntry? resumed;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  ContinueReadingRow(
                    history: [
                      ReadEntry(
                        sourceId: 'src',
                        showId: 'show2',
                        title: 'Novel Title',
                        chapterId: 'c5',
                        chapterNumber: 5,
                        chapterUrl: '/c5',
                        pos: 3,
                        total: 20,
                        updatedMs: 1,
                      ),
                    ],
                    onResumeReading: (e) => resumed = e,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Continue Reading'), findsOneWidget);
        expect(find.text('Chapter 5'), findsOneWidget);
        expect(find.text('Continue Watching'), findsNothing);

        await tester.tap(find.text('Novel Title'));
        expect(resumed?.showId, 'show2');
      },
    );
  });

  // ── Part A: ContinueSection gating (login / box-open guard) ──────────────
  // No Hive box is ever opened here, so Hive.isBoxOpen() is always false —
  // exercising exactly the "signed-out / test-env" guard branch the
  // original code's comment described, for both modes.

  group('ContinueSection gating', () {
    setUp(() async {
      await sl.reset();
      sl.registerSingleton<AppMode>(const AppMode(isTv: false));
    });

    tearDown(() async {
      await sl.reset();
    });

    Future<void> pumpGated(
      WidgetTester tester, {
      required bool loggedIn,
      required ContentMode mode,
    }) async {
      if (sl.isRegistered<ContentModeCubit>()) {
        sl.unregister<ContentModeCubit>();
      }
      sl.registerSingleton<ContentModeCubit>(_FakeContentModeCubit(mode));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                ContinueSection(
                  loggedIn: loggedIn,
                  onResume: (_) {},
                  onLongPress: (_) {},
                  onSeeAll: () {},
                  onResumeReading: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('signed out renders nothing in anime mode', (tester) async {
      await pumpGated(tester, loggedIn: false, mode: ContentMode.anime);
      expect(find.text('Continue Watching'), findsNothing);
      expect(find.text('Continue Reading'), findsNothing);
    });

    testWidgets('signed out renders nothing in a reading mode',
        (tester) async {
      await pumpGated(tester, loggedIn: false, mode: ContentMode.novel);
      expect(find.text('Continue Watching'), findsNothing);
      expect(find.text('Continue Reading'), findsNothing);
    });

    testWidgets(
      'signed in but the box was never opened (production opens it at '
      'boot) still renders nothing — never throws',
      (tester) async {
        await pumpGated(tester, loggedIn: true, mode: ContentMode.anime);
        expect(find.text('Continue Watching'), findsNothing);
        await pumpGated(tester, loggedIn: true, mode: ContentMode.manga);
        expect(find.text('Continue Reading'), findsNothing);
      },
    );
  });

  // ── Part B: My List mode filter ───────────────────────────────────────────

  group('MyListScreen mode filter', () {
    const animeItem = MediaItem(
      id: 'a1',
      title: 'Anime Show',
      url: '/a1',
      type: ProviderType.anime,
      sourceId: 's',
    );
    const movieItem = MediaItem(
      id: 'm1',
      title: 'Movie Show',
      url: '/m1',
      type: ProviderType.movie,
      sourceId: 's',
    );
    const mangaItem = MediaItem(
      id: 'g1',
      title: 'Manga Title',
      url: '/g1',
      type: ProviderType.manga,
      sourceId: 's',
    );
    const novelItem = MediaItem(
      id: 'n1',
      title: 'Novel Title',
      url: '/n1',
      type: ProviderType.novel,
      sourceId: 's',
    );

    setUp(() async {
      await sl.reset();
      sl.registerSingleton<AppMode>(const AppMode(isTv: false));
      sl.registerSingleton<TrackerHub>(TrackerHub(const []));
      sl.registerSingleton<MyListStore>(
        _FakeMyListStore([animeItem, movieItem, mangaItem, novelItem]),
      );
      sl.registerSingleton<ListStatusStore>(_FakeListStatusStore());
    });

    tearDown(() async {
      await sl.reset();
    });

    testWidgets(
      'anime mode shows anime + movie items and hides manga/novel — the '
      "hard constraint: anime mode's own library view is unchanged",
      (tester) async {
        sl.registerSingleton<ContentModeCubit>(
          _FakeContentModeCubit(ContentMode.anime),
        );

        await tester.pumpWidget(const MaterialApp(home: MyListScreen()));
        await tester.pumpAndSettle();

        expect(find.text('Anime Show'), findsOneWidget);
        expect(find.text('Movie Show'), findsOneWidget);
        expect(find.text('Manga Title'), findsNothing);
        expect(find.text('Novel Title'), findsNothing);
      },
    );

    testWidgets(
      'manga mode shows only the manga item, hiding anime/movie/novel',
      (tester) async {
        sl.registerSingleton<ContentModeCubit>(
          _FakeContentModeCubit(ContentMode.manga),
        );

        await tester.pumpWidget(const MaterialApp(home: MyListScreen()));
        await tester.pumpAndSettle();

        expect(find.text('Manga Title'), findsOneWidget);
        expect(find.text('Anime Show'), findsNothing);
        expect(find.text('Movie Show'), findsNothing);
        expect(find.text('Novel Title'), findsNothing);
      },
    );

    testWidgets(
      'novel mode shows only the novel item, hiding anime/movie/manga',
      (tester) async {
        sl.registerSingleton<ContentModeCubit>(
          _FakeContentModeCubit(ContentMode.novel),
        );

        await tester.pumpWidget(const MaterialApp(home: MyListScreen()));
        await tester.pumpAndSettle();

        expect(find.text('Novel Title'), findsOneWidget);
        expect(find.text('Anime Show'), findsNothing);
        expect(find.text('Movie Show'), findsNothing);
        expect(find.text('Manga Title'), findsNothing);
      },
    );
  });
}
