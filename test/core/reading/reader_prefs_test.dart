import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/reading/reader_prefs.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('reader_prefs');
    Hive.init(dir.path);
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('defaults', () async {
    await ReaderPrefs.init();
    final p = ReaderPrefs();
    expect(p.fontSize, 16);
    expect(p.lineHeight, 1.6);
    expect(p.theme, 'dark');
    expect(p.marginWidth, 20);
    expect(p.direction, 'ltr');
    expect(p.background, 'black');
    expect(p.keepScreenOn, isTrue);
  });

  test('persists changes', () async {
    await ReaderPrefs.init();
    final p = ReaderPrefs();
    await p.setFontSize(20);
    await p.setDirection('rtl');
    final q = ReaderPrefs();
    expect(q.fontSize, 20);
    expect(q.direction, 'rtl');
  });

  test('numeric prefs coerce int round-trips to double', () async {
    // Hive can round-trip a value written as an int back as an int even
    // though the field is typed double — the same trap PlaybackPrefs guards
    // against. setFontSize(20) below writes an int literal; the getter must
    // still hand back a double or this throws a cast error.
    await ReaderPrefs.init();
    final p = ReaderPrefs();
    await p.setFontSize(20);
    await p.setLineHeight(2);
    await p.setMarginWidth(30);
    expect(p.fontSize, isA<double>());
    expect(p.fontSize, 20.0);
    expect(p.lineHeight, isA<double>());
    expect(p.lineHeight, 2.0);
    expect(p.marginWidth, isA<double>());
    expect(p.marginWidth, 30.0);
  });
}
