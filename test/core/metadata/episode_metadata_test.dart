import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/episode.dart';

void main() {
  test('copyWith sets description and preserves other fields', () {
    const e = Episode(id: 'a', title: 'Ep', number: 1, url: 'u', season: 2);
    final e2 = e.copyWith(description: 'A synopsis.');
    expect(e2.description, 'A synopsis.');
    expect(e2.id, 'a');
    expect(e2.number, 1);
    expect(e2.season, 2);
    expect(e.description, isNull); // original untouched
  });
}
