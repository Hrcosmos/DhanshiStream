import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/metadata/episode_metadata_service.dart';
import 'package:watch_app/core/models/episode.dart';

void main() {
  test('copyWith sets description + metaTitle, preserves other fields', () {
    const e = Episode(id: 'a', title: 'Ep', number: 1, url: 'u', season: 2);
    final e2 = e.copyWith(description: 'A synopsis.', metaTitle: 'Real Title');
    expect(e2.description, 'A synopsis.');
    expect(e2.metaTitle, 'Real Title');
    expect(e2.id, 'a');
    expect(e2.number, 1);
    expect(e2.season, 2);
    expect(e.description, isNull); // original untouched
    expect(e.metaTitle, isNull);
  });

  group('parseAniZip', () {
    test('maps number -> title+overview, drops empty', () {
      final m = EpisodeMetadataService.parseAniZip({
        'episodes': {
          '1': {
            'title': {'en': 'The Start', 'x-jat': 'Hajimari'},
            'overview': 'First ep.',
          },
          '2': {'overview': '   '}, // blank overview, no title -> dropped
          '3': {'overview': 'Third ep.'}, // overview only
        }
      });
      expect(m[1], (title: 'The Start', overview: 'First ep.'));
      expect(m.containsKey(2), isFalse);
      expect(m[3], (title: null, overview: 'Third ep.'));
    });
    test('title-only episode is kept', () {
      final m = EpisodeMetadataService.parseAniZip({
        'episodes': {
          '1': {
            'title': {'en': 'Named'},
          },
        }
      });
      expect(m[1], (title: 'Named', overview: null));
    });
    test('non-map / missing episodes -> empty', () {
      expect(EpisodeMetadataService.parseAniZip(null), isEmpty);
      expect(EpisodeMetadataService.parseAniZip({'x': 1}), isEmpty);
    });
  });

  group('parseTmdbSeason', () {
    test('maps episode_number -> name+overview, drops empty', () {
      final m = EpisodeMetadataService.parseTmdbSeason({
        'episodes': [
          {'episode_number': 1, 'name': 'Pilot', 'overview': 'Pilot ep.'},
          {'episode_number': 2, 'name': '', 'overview': ''}, // both blank
          {'episode_number': 3, 'name': 'Third', 'overview': 'Third.'},
        ]
      });
      expect(m[1], (title: 'Pilot', overview: 'Pilot ep.'));
      expect(m.containsKey(2), isFalse);
      expect(m[3], (title: 'Third', overview: 'Third.'));
    });
  });

  group('mergeMeta', () {
    const eps = [
      Episode(id: '1', title: 'A', number: 1, url: 'u1'),
      Episode(id: '2', title: 'B', number: 2, url: 'u2'),
      Episode(id: '3', title: 'C', number: 3, url: 'u3'),
    ];
    final byNum = <int, EpisodeMeta>{
      1: (title: 'One', overview: 'one'),
      3: (title: null, overview: 'three'),
    };

    test('sets title + description on matching episode numbers', () {
      final out = mergeMeta(
        eps,
        (e) => byNum[e.number?.toInt()],
      );
      expect(out[0].metaTitle, 'One');
      expect(out[0].description, 'one');
      expect(out[1].metaTitle, isNull); // no match
      expect(out[1].description, isNull);
      expect(out[2].metaTitle, isNull); // overview-only match
      expect(out[2].description, 'three');
    });

    test('no matches returns the same list instance', () {
      expect(identical(mergeMeta(eps, (_) => null), eps), isTrue);
    });
  });
}
