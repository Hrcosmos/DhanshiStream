// Task E3: manga/novel sources get their own entry, separate from the three
// streaming ecosystem rows (Zangetsu / CloudStream / Aniyomi).
//
// Two things under test:
//  - ProvidersHubScreen (phone view) grows a fourth "Manga & Novel" row that
//    opens the Zangetsu JS providers screen — while the existing three rows
//    stay exactly as they are today.
//  - Settings → Sources grows a matching entry, in the same section, without
//    disturbing the order of the entries already there.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/anilist/anilist_service.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/appwrite/appwrite_service.dart';
import 'package:watch_app/core/download/download_prefs.dart';
import 'package:watch_app/core/mihon/mihon_manager.dart';
import 'package:watch_app/core/playback/playback_prefs.dart';
import 'package:watch_app/core/playback/search_prefs.dart';
import 'package:watch_app/core/provider/cloudstream_provider.dart';
import 'package:watch_app/core/provider/provider_manager.dart';
import 'package:watch_app/core/provider/provider_registry.dart';
import 'package:watch_app/core/provider/provider_repo_registry.dart';
import 'package:watch_app/core/state/active_source_cubit.dart';
import 'package:watch_app/core/supabase/supabase_service.dart';
import 'package:watch_app/core/theme/theme_controller.dart';
import 'package:watch_app/core/torrent/torrent_prefs.dart';
import 'package:watch_app/core/tracker/mal_service.dart';
import 'package:watch_app/core/tracker/simkl_service.dart';
import 'package:watch_app/features/auth/auth_cubit.dart';
import 'package:watch_app/features/auth/migration_bridge.dart';
import 'package:watch_app/features/settings/settings_screen.dart';
import 'package:watch_app/features/sources/providers_hub_screen.dart';
import 'package:watch_app/features/sources/zangetsu_sources_screen.dart';

// ---------------------------------------------------------------------------
// Shared fakes
// ---------------------------------------------------------------------------

/// Fixed installed-entries + manifest-type lookup, so reading (manga/novel)
/// vs. video (anime/movie) counts are deterministic without wiring up a real
/// cached repo manifest.
class _FakeProviderRegistry implements ProviderRegistry {
  _FakeProviderRegistry(this._entries, this._types);
  final List<ProviderRegistryEntry> _entries;
  final Map<String, String> _types;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  List<ProviderRegistryEntry> getAll() => _entries;

  @override
  ProviderRegistryEntry? entryFor(String sourceId) {
    for (final e in _entries) {
      if (e.name == sourceId) return e;
    }
    return null;
  }

  @override
  Set<String> nsfwSourceIds() => const {};

  @override
  String? typeOf(String sourceId) => _types[sourceId];

  // SourcesBloc (built when ZangetsuSourcesScreen is pushed) subscribes to
  // this on construction.
  @override
  Stream<BoxEvent> watch() => const Stream<BoxEvent>.empty();
}

class _FakeReposRegistry implements ProviderReposRegistry {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  List<ProviderRepo> getAll() => const [];

  @override
  Stream<BoxEvent> watch() => const Stream<BoxEvent>.empty();
}

void main() {
  final sl = GetIt.instance;

  // ── ProvidersHubScreen (phone) ──────────────────────────────────────────
  group('ProvidersHubScreen phone view', () {
    setUp(() {
      final entries = [
        ProviderRegistryEntry(
          name: 'anime1',
          url: 'bundled://anime1',
          displayName: 'Anime One',
        ),
        ProviderRegistryEntry(
          name: 'manga1',
          url: 'bundled://manga1',
          displayName: 'Manga One',
        ),
        ProviderRegistryEntry(
          name: 'novel1',
          url: 'bundled://novel1',
          displayName: 'Novel One',
        ),
      ];
      final types = {'anime1': 'anime', 'manga1': 'manga', 'novel1': 'novel'};

      sl
        ..registerSingleton<AppMode>(const AppMode(isTv: false))
        ..registerSingleton<ProviderRegistry>(
          _FakeProviderRegistry(entries, types),
        )
        ..registerSingleton<ProviderReposRegistry>(_FakeReposRegistry())
        ..registerSingleton<CloudStreamManager>(CloudStreamManager())
        ..registerSingleton<AniyomiManager>(AniyomiManager())
        ..registerSingleton<MihonManager>(MihonManager())
        ..registerSingleton<ActiveSourceCubit>(ActiveSourceCubit(fallback: ''));
    });

    tearDown(() async {
      await sl.reset();
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: ProvidersHubScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a dedicated Manga & Novel entry, counting only reading sources',
        (tester) async {
      await pump(tester);

      expect(find.text('Manga & Novel'), findsOneWidget);
      // Only manga1 + novel1 — the video-only anime1 is excluded.
      expect(find.text('2 sources'), findsOneWidget);
    });

    testWidgets('tapping Manga & Novel opens the Zangetsu JS providers screen',
        (tester) async {
      await pump(tester);

      await tester.tap(find.text('Manga & Novel'));
      await tester.pumpAndSettle();

      expect(find.byType(ZangetsuSourcesScreen), findsOneWidget);
    });

    testWidgets(
      'the existing Zangetsu row is unchanged — same title, desc and '
      'unfiltered total (reading sources still count toward it, as today)',
      (tester) async {
        await pump(tester);

        expect(find.text('Zangetsu'), findsOneWidget);
        expect(find.text('Built-in JS providers'), findsOneWidget);
        expect(find.text('3 sources'), findsOneWidget); // all 3, unfiltered
      },
    );

    testWidgets(
      'CloudStream and Aniyomi rows are unaffected — still Android-gated, '
      'absent on this (non-Android) test host, same as before',
      (tester) async {
        await pump(tester);

        expect(find.text('CloudStream'), findsNothing);
        expect(find.text('Aniyomi'), findsNothing);
      },
    );

    // ── Fix round 1, finding 1: ACTIVE badge must be exclusive ────────────
    testWidgets(
      'an anime active source badges only the Zangetsu row (unchanged today)',
      (tester) async {
        sl.unregister<ActiveSourceCubit>();
        sl.registerSingleton<ActiveSourceCubit>(
          ActiveSourceCubit(fallback: 'anime1'),
        );
        await pump(tester);

        expect(find.text('ACTIVE'), findsOneWidget);
        final activeY = tester.getTopLeft(find.text('ACTIVE')).dy;
        final zangetsuY = tester.getTopLeft(find.text('Zangetsu')).dy;
        final mangaY = tester.getTopLeft(find.text('Manga & Novel')).dy;
        expect((activeY - zangetsuY).abs(), lessThan((activeY - mangaY).abs()));
      },
    );

    testWidgets(
      'a manga active source badges only the Manga & Novel row, not Zangetsu',
      (tester) async {
        sl.unregister<ActiveSourceCubit>();
        sl.registerSingleton<ActiveSourceCubit>(
          ActiveSourceCubit(fallback: 'manga1'),
        );
        await pump(tester);

        expect(find.text('ACTIVE'), findsOneWidget);
        final activeY = tester.getTopLeft(find.text('ACTIVE')).dy;
        final zangetsuY = tester.getTopLeft(find.text('Zangetsu')).dy;
        final mangaY = tester.getTopLeft(find.text('Manga & Novel')).dy;
        expect((activeY - mangaY).abs(), lessThan((activeY - zangetsuY).abs()));
      },
    );

    // ── Fix round 1, finding 2: tapping through actually separates content ─
    testWidgets(
      'tapping Manga & Novel scopes the Installed tab to reading providers, '
      'with a Show all escape hatch back to everything',
      (tester) async {
        await pump(tester);

        await tester.tap(find.text('Manga & Novel'));
        await tester.pumpAndSettle();

        expect(find.text('Manga One'), findsOneWidget);
        expect(find.text('Novel One'), findsOneWidget);
        // Anime provider is hidden by default — this is the actual "different
        // from streaming mode" the user asked for, not just a different tile.
        expect(find.text('Anime One'), findsNothing);

        // The user can still always reach everything.
        final showAll = find.text('Show all');
        expect(showAll, findsOneWidget);
        await tester.tap(showAll);
        await tester.pumpAndSettle();

        expect(find.text('Anime One'), findsOneWidget);
        expect(find.text('Manga One'), findsOneWidget);
        expect(find.text('Novel One'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping Zangetsu (unscoped) still shows every provider, no scoping UI',
      (tester) async {
        await pump(tester);

        await tester.tap(find.text('Zangetsu'));
        await tester.pumpAndSettle();

        expect(find.text('Anime One'), findsOneWidget);
        expect(find.text('Manga One'), findsOneWidget);
        expect(find.text('Novel One'), findsOneWidget);
        expect(find.text('Show all'), findsNothing);
      },
    );
  });

  // ── Settings → Sources ──────────────────────────────────────────────────
  group('Settings Sources section', () {
    late ActiveSourceCubit activeCubit;
    late Directory hiveDir;

    setUp(() async {
      hiveDir = await Directory.systemTemp.createTemp();
      Hive.init(hiveDir.path);
      await Hive.openBox(DownloadPrefs.boxName);
      await Hive.openBox(TorrentPrefs.boxName);
      await Hive.openBox(ThemeController.boxName);
      await Hive.openBox(PlaybackPrefs.boxName);
      sl
        ..registerSingleton<AppMode>(const AppMode(isTv: false))
        ..registerSingleton<SearchPrefs>(_StubSearchPrefs())
        ..registerSingleton<ProviderRegistry>(_FakeProviderRegistry(
          [
            ProviderRegistryEntry(name: 'manga1', url: 'bundled://manga1'),
          ],
          {'manga1': 'manga'},
        ))
        ..registerSingleton<AniListService>(_StubAniList())
        ..registerSingleton<MalService>(_StubMal())
        ..registerSingleton<SimklService>(_StubSimkl())
        ..registerSingleton<PlaybackPrefs>(PlaybackPrefs())
        ..registerSingleton<DownloadPrefs>(DownloadPrefs())
        ..registerSingleton<TorrentPrefs>(TorrentPrefs());
      activeCubit = ActiveSourceCubit();
    });

    tearDown(() async {
      await activeCubit.close();
      await GetIt.instance.reset();
      await Hive.deleteFromDisk();
      if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
    });

    Future<void> pumpSettings(WidgetTester tester) async {
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => '/tmp/test',
      );
      await tester.binding.setSurfaceSize(const Size(1000, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final authCubit =
          AuthCubit(SupabaseService(), AppwriteService(), _fakeBridge());
      addTearDown(authCubit.close);
      GetIt.instance.registerSingleton<AuthCubit>(authCubit);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<ActiveSourceCubit>.value(value: activeCubit),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'lists Manga & Novel alongside the existing Sources entries, right '
      'after Providers',
      (tester) async {
        await pumpSettings(tester);

        await tester.tap(find.text('Sources'));
        await tester.pumpAndSettle();

        for (final t in const [
          'Providers',
          'Manga & Novel',
          'Active source',
          'Source health',
          'Auto-update extensions',
        ]) {
          expect(find.text(t), findsOneWidget, reason: 'tile: $t');
        }

        // Order: unchanged entries keep their relative order, the new entry
        // slots in right after Providers (mirrors it, per the task).
        final providersY = tester.getTopLeft(find.text('Providers')).dy;
        final mangaY = tester.getTopLeft(find.text('Manga & Novel')).dy;
        final activeSourceY = tester.getTopLeft(find.text('Active source')).dy;
        final healthY = tester.getTopLeft(find.text('Source health')).dy;
        expect(providersY, lessThan(mangaY));
        expect(mangaY, lessThan(activeSourceY));
        expect(activeSourceY, lessThan(healthY));
      },
    );

    testWidgets('Manga & Novel is reachable from search too', (tester) async {
      await pumpSettings(tester);

      await tester.enterText(find.byType(TextField), 'manga');
      await tester.pumpAndSettle();

      expect(find.text('Manga & Novel'), findsOneWidget);
    });
  });
}

MigrationBridge _fakeBridge() => MigrationBridge(
      invoke: (_, __) async => const {'ok': false},
      signInPassword: (_, __) async => false,
      verifyOtp: (_, __) async => false,
    );

class _StubSearchPrefs extends SearchPrefs {
  @override
  SearchLayout get layout => SearchLayout.vertical;
}

class _StubAniList implements AniListService {
  @override
  bool get isConnected => false;
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _StubMal implements MalService {
  @override
  bool get isConnected => false;
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _StubSimkl implements SimklService {
  @override
  bool get isConnected => false;
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
