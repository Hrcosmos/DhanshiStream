import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/skip_service.dart';

SkipInterval _iv(int startS, int endS, String type) => SkipInterval(
  start: Duration(seconds: startS),
  end: Duration(seconds: endS),
  type: type,
);

void main() {
  final op = _iv(60, 150, 'op');
  final ed = _iv(1300, 1390, 'ed');
  final skips = [op, ed];

  group('isEndingSkip', () {
    test('routes AniSkip types to the right toggle', () {
      expect(isEndingSkip('op'), isFalse);
      expect(isEndingSkip('ed'), isTrue);
      expect(isEndingSkip('mixed-ed'), isTrue);
      // "mixed" itself contains "ed", so a contains() check would wrongly send
      // a mixed opening to the ending toggle.
      expect(isEndingSkip('mixed-op'), isFalse);
      expect(isEndingSkip('recap'), isFalse);
    });
  });

  group('autoSkipAt', () {
    test('fires inside the opening when the OP toggle is on', () {
      final iv = autoSkipAt(
        skips,
        const Duration(seconds: 70),
        op: true,
        ed: false,
        fired: {},
      );
      expect(iv, same(op));
    });

    test('stays quiet outside every interval', () {
      expect(
        autoSkipAt(skips, const Duration(seconds: 400),
            op: true, ed: true, fired: {}),
        isNull,
      );
    });

    test('honours each toggle independently', () {
      // Sitting in the ending with only the OP toggle on.
      expect(
        autoSkipAt(skips, const Duration(seconds: 1320),
            op: true, ed: false, fired: {}),
        isNull,
      );
      expect(
        autoSkipAt(skips, const Duration(seconds: 1320),
            op: false, ed: true, fired: {}),
        same(ed),
      );
    });

    test('fires once per interval — seeking back in does not bounce you out',
        () {
      final fired = <int>{};
      final first = autoSkipAt(skips, const Duration(seconds: 70),
          op: true, ed: true, fired: fired);
      expect(first, same(op));
      fired.add(first!.start.inMilliseconds);

      // User deliberately seeks back into the opening to watch it.
      expect(
        autoSkipAt(skips, const Duration(seconds: 70),
            op: true, ed: true, fired: fired),
        isNull,
      );
      // The ending is a different interval and still fires.
      expect(
        autoSkipAt(skips, const Duration(seconds: 1320),
            op: true, ed: true, fired: fired),
        same(ed),
      );
    });

    test('leaves the last second alone', () {
      // 149s is inside [60,150) but within the 1s tail guard.
      expect(
        autoSkipAt(skips, const Duration(seconds: 149),
            op: true, ed: true, fired: {}),
        isNull,
      );
      expect(
        autoSkipAt(skips, const Duration(seconds: 148),
            op: true, ed: true, fired: {}),
        same(op),
      );
    });

    test('start is inclusive, end is exclusive', () {
      expect(
        autoSkipAt(skips, const Duration(seconds: 60),
            op: true, ed: true, fired: {}),
        same(op),
      );
      expect(
        autoSkipAt(skips, const Duration(seconds: 150),
            op: true, ed: true, fired: {}),
        isNull,
      );
    });
  });
}
