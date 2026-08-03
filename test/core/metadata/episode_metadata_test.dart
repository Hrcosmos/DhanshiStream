import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/metadata/episode_metadata_service.dart';
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

  group('parseAniZip', () {
    test('maps episode number -> overview, drops empty', () {
      final m = EpisodeMetadataService.parseAniZip({
        'episodes': {
          '1': {'overview': 'First ep.'},
          '2': {'overview': '   '},
          '3': {'overview': 'Third ep.'},
        }
      });
      expect(m, {1: 'First ep.', 3: 'Third ep.'});
    });
    test('non-map / missing episodes -> empty', () {
      expect(EpisodeMetadataService.parseAniZip(null), isEmpty);
      expect(EpisodeMetadataService.parseAniZip({'x': 1}), isEmpty);
    });
  });

  group('parseTmdbSeason', () {
    test('maps episode_number -> overview, drops empty', () {
      final m = EpisodeMetadataService.parseTmdbSeason({
        'episodes': [
          {'episode_number': 1, 'overview': 'Pilot.'},
          {'episode_number': 2, 'overview': ''},
          {'episode_number': 3, 'overview': 'Third.'},
        ]
      });
      expect(m, {1: 'Pilot.', 3: 'Third.'});
    });
  });

  group('mergeDescriptions', () {
    const eps = [
      Episode(id: '1', title: 'A', number: 1, url: 'u1'),
      Episode(id: '2', title: 'B', number: 2, url: 'u2'),
      Episode(id: '3', title: 'C', number: 3, url: 'u3'),
    ];
    test('sets description on matching episode numbers', () {
      final out = mergeDescriptions(eps, {1: 'one', 3: 'three'});
      expect(out[0].description, 'one');
      expect(out[1].description, isNull); // no match
      expect(out[2].description, 'three');
    });
    test('empty map returns the same list', () {
      expect(identical(mergeDescriptions(eps, const {}), eps), isTrue);
    });
    test('non-integer / null numbers are skipped', () {
      const e = [Episode(id: 'x', title: 'X', number: 1.5, url: 'u')];
      expect(mergeDescriptions(e, {1: 'one'})[0].description, isNull);
    });
  });
}
