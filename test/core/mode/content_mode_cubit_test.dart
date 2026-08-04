import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/mode/content_mode.dart';
import 'package:watch_app/core/mode/content_mode_cubit.dart';
import 'package:watch_app/core/state/active_source_cubit.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mode_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('defaults to anime and persists mode', () async {
    await ActiveSourceCubit.init();
    final active = ActiveSourceCubit(box: Hive.box(ActiveSourceCubit.boxName));
    final cubit = await ContentModeCubit.create(active);
    expect(cubit.state, ContentMode.anime);

    await cubit.setMode(ContentMode.manga);
    expect(cubit.state, ContentMode.manga);

    final reloaded = await ContentModeCubit.create(active);
    expect(reloaded.state, ContentMode.manga);
  });

  test('remembers a separate active source per mode', () async {
    await ActiveSourceCubit.init();
    final active = ActiveSourceCubit(box: Hive.box(ActiveSourceCubit.boxName));
    final cubit = await ContentModeCubit.create(active);

    active.setSource('js:animesrc');
    await cubit.setMode(ContentMode.manga); // stores js:animesrc under src.anime
    active.setSource('js:mangasrc');
    await cubit.setMode(ContentMode.anime); // stores js:mangasrc under src.manga
    expect(active.state, 'js:animesrc'); // anime source restored

    await cubit.setMode(ContentMode.manga);
    expect(active.state, 'js:mangasrc'); // manga source restored
  });
}
