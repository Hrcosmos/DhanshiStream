import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/mihon/mihon_mapping.dart';
import 'package:watch_app/core/models/media_detail.dart';
import 'package:watch_app/core/models/provider_info.dart';

void main() {
  // ── mediaItemFromSManga ─────────────────────────────────────────────────────
  group('mediaItemFromSManga', () {
    test('basic mapping, fully populated', () {
      final item = mediaItemFromSManga(
        {
          'url': 'https://source.test/manga/1',
          'title': 'One Piece',
          'thumbnail_url': 'https://img.test/op.jpg',
        },
        sourceId: 'mihon:123456',
      );

      expect(item.id, 'https://source.test/manga/1');
      expect(item.url, 'https://source.test/manga/1');
      expect(item.title, 'One Piece');
      expect(item.cover, 'https://img.test/op.jpg');
      expect(item.sourceId, 'mihon:123456');
      expect(item.type, ProviderType.manga);
    });

    test('null/absent thumbnail_url produces null cover', () {
      final item = mediaItemFromSManga(
        {'url': 'https://source.test/manga/2', 'title': 'Title'},
        sourceId: 'mihon:789',
      );
      expect(item.cover, isNull);
    });

    test('non-empty headers are forwarded as coverHeaders, unmodified', () {
      final item = mediaItemFromSManga(
        {
          'url': 'https://source.test/manga/3',
          'title': 'Cover Headers Test',
          'thumbnail_url': 'https://img.test/cover.jpg',
        },
        sourceId: 'mihon:111',
        headers: {'Referer': 'https://source.test/'},
      );
      expect(item.coverHeaders, {'Referer': 'https://source.test/'});
    });

    test('empty headers produce null coverHeaders', () {
      final item = mediaItemFromSManga(
        {'url': 'u', 'title': 'T'},
        sourceId: 'mihon:222',
        headers: {},
      );
      expect(item.coverHeaders, isNull);
    });

    test('missing url/title default to empty strings, not throw', () {
      expect(
        () => mediaItemFromSManga(const {}, sourceId: 'mihon:0'),
        returnsNormally,
      );
      final item = mediaItemFromSManga(const {}, sourceId: 'mihon:0');
      expect(item.url, '');
      expect(item.title, '');
    });
  });

  // ── mediaDetailFromSManga ───────────────────────────────────────────────────
  group('mediaDetailFromSManga', () {
    test('fully populated manga maps every field', () {
      final detail = mediaDetailFromSManga(
        {
          'url': 'https://source.test/manga/3',
          'title': 'Ongoing Show',
          'thumbnail_url': 'https://img.test/cover.jpg',
          'description': 'A show that is ongoing.',
          'genre': 'Action, Fantasy',
          'status': 1,
          'author': 'Eiichiro Oda',
          'artist': 'Eiichiro Oda',
        },
        const [],
        sourceId: 'mihon:1',
      );

      expect(detail.status, MediaStatus.ongoing);
      expect(detail.genres, ['Action', 'Fantasy']);
      expect(detail.description, 'A show that is ongoing.');
      expect(detail.cover, 'https://img.test/cover.jpg');
      expect(detail.type, ProviderType.manga);
      expect(detail.sourceId, 'mihon:1');
      // author == artist collapses to a single studios entry, not two.
      expect(detail.studios, ['Eiichiro Oda']);
    });

    test('distinct author and artist both land in studios, in order', () {
      final detail = mediaDetailFromSManga(
        {'url': 'u', 'title': 'T', 'author': 'Writer Name', 'artist': 'Artist Name'},
        const [],
        sourceId: 'mihon:2',
      );
      expect(detail.studios, ['Writer Name', 'Artist Name']);
    });

    test('null author and artist produce empty studios', () {
      final detail = mediaDetailFromSManga(
        {'url': 'u', 'title': 'T'},
        const [],
        sourceId: 'mihon:3',
      );
      expect(detail.studios, isEmpty);
    });

    test('only artist present maps to a single-entry studios list', () {
      final detail = mediaDetailFromSManga(
        {'url': 'u', 'title': 'T', 'artist': 'Solo Artist'},
        const [],
        sourceId: 'mihon:4',
      );
      expect(detail.studios, ['Solo Artist']);
    });

    test('non-empty headers are forwarded as coverHeaders on detail', () {
      final detail = mediaDetailFromSManga(
        {'url': 'u', 'title': 'T', 'status': 1},
        const [],
        sourceId: 'mihon:10',
        headers: {'Referer': 'https://source.test/'},
      );
      expect(detail.coverHeaders, {'Referer': 'https://source.test/'});
    });

    test('status 2 -> completed, 5 -> cancelled, 6 -> hiatus, unknown -> unknown', () {
      MediaStatus statusFor(int code) => mediaDetailFromSManga(
            {'url': 'u', 'title': 'T', 'status': code},
            const [],
            sourceId: 'mihon:s',
          ).status;
      expect(statusFor(2), MediaStatus.completed);
      expect(statusFor(5), MediaStatus.cancelled);
      expect(statusFor(6), MediaStatus.hiatus);
      expect(statusFor(99), MediaStatus.unknown);
    });

    test('null genre produces empty genres list', () {
      final detail = mediaDetailFromSManga(
        {'url': 'u', 'title': 'T'},
        const [],
        sourceId: 'mihon:4b',
      );
      expect(detail.genres, isEmpty);
    });

    test('chapters list is embedded unchanged as episodes', () {
      final ch = episodeFromSChapter({
        'url': 'https://source.test/ch/1',
        'name': 'Chapter 1',
        'chapter_number': 1.0,
        'date_upload': 0,
      });
      final detail = mediaDetailFromSManga(
        {'url': 'u', 'title': 'T'},
        [ch],
        sourceId: 'mihon:5',
      );
      expect(detail.episodes, hasLength(1));
      expect(detail.episodes.first.url, 'https://source.test/ch/1');
    });
  });

  // ── episodeFromSChapter ─────────────────────────────────────────────────────
  group('episodeFromSChapter', () {
    test('keeps url in Episode.url and derives number', () {
      final ep = episodeFromSChapter({
        'url': 'https://source.test/ch/1',
        'name': 'Chapter 1',
        'chapter_number': 1.0,
        'date_upload': 0,
      });

      expect(ep.url, 'https://source.test/ch/1');
      expect(ep.number, 1.0);
      // Distinguishes int-vs-double: a chapter_number of exactly 1 must stay
      // a double on Episode.number, not get silently accepted as an int.
      expect(ep.number, isA<double>());
      expect(ep.title, 'Chapter 1');
    });

    test('negative chapter_number treated as null number, id falls back to url', () {
      final ep = episodeFromSChapter({
        'url': 'https://source.test/ch/special',
        'name': 'Special',
        'chapter_number': -1.0,
        'date_upload': 0,
      });

      expect(ep.number, isNull);
      expect(ep.id, 'https://source.test/ch/special');
    });

    test('date_upload millis are converted to ISO string', () {
      final ep = episodeFromSChapter({
        'url': 'https://source.test/ch/2',
        'name': 'Chapter 2',
        'chapter_number': 2.0,
        'date_upload': 1700000000000,
      });

      expect(ep.date, isNotNull);
      expect(ep.date, contains('2023'));
    });

    test('zero date_upload produces null date', () {
      final ep = episodeFromSChapter({
        'url': 'u',
        'name': 'C',
        'chapter_number': 3.0,
        'date_upload': 0,
      });
      expect(ep.date, isNull);
    });

    test('missing keys default without throwing', () {
      expect(() => episodeFromSChapter(const {}), returnsNormally);
      final ep = episodeFromSChapter(const {});
      expect(ep.url, '');
      expect(ep.title, '');
      expect(ep.number, isNull);
      expect(ep.date, isNull);
    });

    test('chapter id uses a fixed-precision number key, distinguishing 1.0 from 1.5', () {
      final whole = episodeFromSChapter({
        'url': 'u1',
        'name': 'C1',
        'chapter_number': 1.0,
        'date_upload': 0,
      });
      final half = episodeFromSChapter({
        'url': 'u2',
        'name': 'C1.5',
        'chapter_number': 1.5,
        'date_upload': 0,
      });
      expect(whole.id, isNot(equals(half.id)));
    });
  });

  // ── pageImageFromJson / pagesFromJson ──────────────────────────────────────
  group('pageImageFromJson', () {
    test('maps imageUrl (not the page url) into PageImage.url', () {
      final page = pageImageFromJson({
        'index': 0,
        'url': 'https://source.test/reader/ch1/1',
        'imageUrl': 'https://cdn.test/ch1/p1.jpg',
        'headers': {'Referer': 'https://source.test/'},
      });
      expect(page, isNotNull);
      expect(page!.url, 'https://cdn.test/ch1/p1.jpg');
      expect(page.headers, {'Referer': 'https://source.test/'});
    });

    test('null imageUrl produces null (unresolved page)', () {
      final page = pageImageFromJson({
        'index': 3,
        'url': 'https://source.test/reader/ch1/4',
        'imageUrl': null,
        'headers': {},
      });
      expect(page, isNull);
    });

    test('empty imageUrl string also produces null', () {
      final page = pageImageFromJson({
        'index': 0,
        'url': 'u',
        'imageUrl': '',
      });
      expect(page, isNull);
    });

    test('empty headers map produces null PageImage.headers', () {
      final page = pageImageFromJson({
        'index': 0,
        'url': 'u',
        'imageUrl': 'https://cdn.test/p.jpg',
        'headers': {},
      });
      expect(page, isNotNull);
      expect(page!.headers, isNull);
    });
  });

  group('pagesFromJson', () {
    test('one unresolvable page (imageUrl: null) is dropped without failing the chapter', () {
      final pages = pagesFromJson([
        {'index': 0, 'url': 'u0', 'imageUrl': 'https://cdn.test/0.jpg'},
        {'index': 1, 'url': 'u1', 'imageUrl': null},
        {'index': 2, 'url': 'u2', 'imageUrl': 'https://cdn.test/2.jpg'},
      ]);

      expect(pages, hasLength(2));
      expect(pages[0].url, 'https://cdn.test/0.jpg');
      expect(pages[1].url, 'https://cdn.test/2.jpg');
    });

    test('all pages unresolved yields an empty (not throwing) list', () {
      final pages = pagesFromJson([
        {'index': 0, 'url': 'u0', 'imageUrl': null},
        {'index': 1, 'url': 'u1', 'imageUrl': null},
      ]);
      expect(pages, isEmpty);
    });

    test('non-list top level returns empty list without throwing', () {
      expect(() => pagesFromJson({'not': 'a list'}), returnsNormally);
      expect(pagesFromJson({'not': 'a list'}), isEmpty);
      expect(pagesFromJson(null), isEmpty);
    });

    test('non-map elements in the list are skipped defensively', () {
      final pages = pagesFromJson([
        'garbage',
        42,
        {'index': 0, 'url': 'u0', 'imageUrl': 'https://cdn.test/0.jpg'},
      ]);
      expect(pages, hasLength(1));
    });

    test('empty list produces empty result', () {
      expect(pagesFromJson(<dynamic>[]), isEmpty);
    });
  });
}
