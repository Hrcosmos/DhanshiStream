import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/provider/provider_downloader.dart';
import 'package:watch_app/core/provider/provider_manager.dart';
import 'package:watch_app/core/provider/provider_registry.dart';
import 'package:watch_app/core/provider/provider_repo_registry.dart';
import 'package:watch_app/features/sources/bloc/sources_bloc.dart';
import 'package:watch_app/features/sources/zangetsu_recommended_repos.dart';
import 'package:watch_app/features/sources/zangetsu_sources_screen.dart';

// Task E4 / Part B: the Zangetsu (JS-provider) "Add repo" dialog should
// offer the Sozo Read pack as a *recommended* source — an opt-in suggestion
// inside the dialog, never pre-installed. This is the PHONE view only
// (isTv: false); the TV variant (_ZTvAddRepoDialog / _ZTvView) is untouched
// by Task E4 and is not exercised here.

/// No-op runtime loader — no source is actually installed in these tests.
class _FakeManager implements ProviderRuntimeLoader {
  @override
  JsProvider? get(String id) => null;

  @override
  void load({
    required String sourceId,
    required String jsSource,
    String originRepoUrl = '',
    String displayName = '',
  }) {}

  @override
  void setSettings(String sourceId, Map<String, dynamic> s) {}

  @override
  void remove(String id) {}
}

/// Stub fetcher — installing sources isn't exercised in these tests.
class _FakeFetcher implements ProviderJsFetcher {
  @override
  Future<CachedProvider> fetch({
    required String name,
    required String url,
    bool force = false,
  }) async => CachedProvider(
    name: name,
    jsCode: '// $name',
    url: url,
    fetchedAt: DateTime.now(),
  );

  @override
  Future<void> remove(String name) async {}
}

/// Fake HTTP transport for [ProviderReposRegistry.fetchAndCache] — returns a
/// canned manifest for ANY request so adding the recommended repo never
/// touches the network.
class _FakeManifestAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode({
      'name': "Spyou's Sozo Providers",
      'description': 'Default manga + novel sources for Sozo Read.',
      'sources': [
        {
          'id': 'mangapill',
          'name': 'Mangapill',
          'version': '1.0.0',
          'type': 'manga',
          'lang': 'en',
          'file': 'mangapill.js',
        },
      ],
    });
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zangetsu_add_repo_test');
    Hive.init(tempDir.path);
    await ProviderRegistry.init();
    await ProviderReposRegistry.init();

    final sl = GetIt.instance;
    sl.registerSingleton<AppMode>(const AppMode(isTv: false));
    sl.registerSingleton<ProviderRegistry>(
      ProviderRegistry(downloader: _FakeFetcher(), manager: _FakeManager()),
    );
    sl.registerSingleton<ProviderReposRegistry>(
      ProviderReposRegistry(
        dio: Dio()..httpClientAdapter = _FakeManifestAdapter(),
      ),
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  // Fixed pumps rather than pumpAndSettle(): the dialog's manifest-URL
  // TextField is autofocus:true, and its blinking cursor keeps scheduling
  // frames for as long as it's focused — pumpAndSettle() would wait for
  // that to stop, which it never does, and hang until its own internal
  // timeout. A couple of pumps is plenty for the AlertDialog's enter
  // transition.
  Future<void> openAddRepoDialog(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ZangetsuSourcesScreen()));
    await tester.pump();
    await tester.tap(find.text('Add Zangetsu repo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Add repo dialog renders the recommended Sozo Read pack', (
    tester,
  ) async {
    await openAddRepoDialog(tester);

    final rec = kRecommendedZangetsuRepos.single;
    expect(find.text(rec.name), findsOneWidget);
    expect(find.text(rec.desc), findsOneWidget);
    // Callers must be able to tell this is manga/novel, not another anime
    // repo.
    expect(rec.desc.toLowerCase(), contains('manga'));
    expect(rec.desc.toLowerCase(), contains('novel'));
  });

  testWidgets('tapping the recommended tile fills in the manifest URL field', (
    tester,
  ) async {
    await openAddRepoDialog(tester);

    final rec = kRecommendedZangetsuRepos.single;
    await tester.tap(find.text('Use'));
    await tester.pump();

    final urlField = tester.widget<TextField>(
      find.widgetWithText(TextField, rec.url),
    );
    expect(urlField.controller!.text, rec.url);
  });

  // "Submitting the recommended repo adds it" is exercised at the bloc
  // level rather than by driving the full dialog: _submit() is a thin
  // wrapper around bloc.addRepo() (see zangetsu_sources_screen.dart), and
  // the "Use" tile filling in the URL field is already covered by the
  // widget test above. Going through the widget tree here would mean
  // pumping past the manifest-URL TextField's autofocus + blinking cursor
  // again while the submit spinner (an indeterminate — i.e. perpetually
  // animating — CircularProgressIndicator) is up, which is exactly the
  // combination pumpAndSettle() can never settle through. Testing the
  // bloc call directly proves the same behavior without fighting that.
  test('SourcesBloc.addRepo persists the recommended Sozo repo', () async {
    final bloc = SourcesBloc(
      registry: GetIt.instance<ProviderRegistry>(),
      repos: GetIt.instance<ProviderReposRegistry>(),
    );
    addTearDown(bloc.close);

    final rec = kRecommendedZangetsuRepos.single;
    final error = await bloc.addRepo(rec.url);

    expect(error, isNull);
    expect(GetIt.instance<ProviderReposRegistry>().has(rec.url), isTrue);
  });
}
