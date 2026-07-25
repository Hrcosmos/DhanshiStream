import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/home_section.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/features/home/home_screen_tv.dart';

void main() {
  testWidgets('poster rail shows the section title and item titles', (
    tester,
  ) async {
    const section = HomeSection(
      title: 'Trending Now',
      items: [
        MediaItem(
          id: '1',
          title: 'Frieren',
          url: 'u1',
          type: ProviderType.anime,
          sourceId: 's',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TvRail(section: section, onTap: (_) {})),
      ),
    );
    await tester.pump();
    expect(find.text('Trending Now'), findsOneWidget);
    expect(find.text('Frieren'), findsWidgets); // title now rendered below the poster
  });
}
