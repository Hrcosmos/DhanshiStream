// Task 12 fix round 1, Finding 1: ListStatusSheet is the one long-form
// `.label` consumer, so it's the one place labelFor() needed wiring.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/mode/content_mode.dart';
import 'package:watch_app/core/mode/content_mode_cubit.dart';
import 'package:watch_app/core/ui/list_status_sheet.dart';

class _FakeContentModeCubit extends Cubit<ContentMode>
    implements ContentModeCubit {
  _FakeContentModeCubit(super.initial);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUp(() async {
    await sl.reset();
  });

  tearDown(() async {
    await sl.reset();
  });

  Future<void> pumpSheet(WidgetTester tester, ContentMode mode) async {
    sl.registerSingleton<ContentModeCubit>(_FakeContentModeCubit(mode));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ListStatusSheet(current: null, inList: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'anime mode keeps the unchanged long labels (Watching / Plan to Watch)',
    (tester) async {
      await pumpSheet(tester, ContentMode.anime);

      expect(find.text('Watching'), findsOneWidget);
      expect(find.text('Plan to Watch'), findsOneWidget);
      expect(find.text('Reading'), findsNothing);
      expect(find.text('Plan to Read'), findsNothing);
    },
  );

  testWidgets(
    'a reading mode shows Reading / Plan to Read instead',
    (tester) async {
      await pumpSheet(tester, ContentMode.novel);

      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Plan to Read'), findsOneWidget);
      expect(find.text('Watching'), findsNothing);
      expect(find.text('Plan to Watch'), findsNothing);
    },
  );

  testWidgets(
    'Completed/Paused/Dropped are unchanged in either mode',
    (tester) async {
      await pumpSheet(tester, ContentMode.manga);

      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Dropped'), findsOneWidget);
    },
  );
}
