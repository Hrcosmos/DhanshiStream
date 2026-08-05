import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/watch_status.dart';
import 'package:watch_app/core/tracker/mal_service.dart';
import 'package:watch_app/core/tracker/tracker.dart';

// Golden strings: the EXACT path text mal_service.dart sent for anime before
// this file existed — copied verbatim (not retyped) from the pre-refactor
// source at the cited line numbers, with a representative title/id/query so
// the interpolation is fully resolved. Same technique as Task 15's
// anilist_manga_test.dart: pin the anime text byte-for-byte first, so a
// change to any of these fails loudly — MediaKind.manga must not perturb the
// anime request by one byte.
//
// mal_service.dart:243 — `_resolve`'s title-search GET.
const _searchAnimeGolden = 'anime?q=Naruto&limit=1&fields=num_episodes';
// mal_service.dart:271 — `_totalEpisodes`'s by-id GET.
const _totalAnimeGolden = 'anime/21?fields=num_episodes';
// mal_service.dart:508 (fetchEntry) — the single-entry read GET.
const _entryAnimeGolden = 'anime/21?fields=num_episodes,my_list_status';
// mal_service.dart:568-569 (searchEntries) — the match-fixer search GET.
const _searchEntriesAnimeGolden =
    'anime?q=Naruto&limit=12&fields=num_episodes,media_type,start_season,main_picture';
// mal_service.dart:309/404 (_patch / removeFromList) — my_list_status path.
const _listStatusAnimeGolden = 'anime/21/my_list_status';

void main() {
  group('anime paths — golden (byte-identical to pre-Task-16 text)', () {
    test('malSearchPath', () {
      expect(malSearchPath(MediaKind.anime, 'Naruto'), _searchAnimeGolden);
    });

    test('malTotalPath', () {
      expect(malTotalPath(MediaKind.anime, 21), _totalAnimeGolden);
    });

    test('malEntryPath', () {
      expect(malEntryPath(MediaKind.anime, 21), _entryAnimeGolden);
    });

    test('malSearchEntriesPath', () {
      expect(
        malSearchEntriesPath(MediaKind.anime, 'Naruto'),
        _searchEntriesAnimeGolden,
      );
    });

    test('malListStatusPath', () {
      expect(malListStatusPath(MediaKind.anime, 21), _listStatusAnimeGolden);
    });

    test('malProgressField is num_watched_episodes', () {
      expect(malProgressField(MediaKind.anime), 'num_watched_episodes');
    });

    test(
      'malStatusFor(reading: false) is byte-identical to WatchStatusX.mal',
      () {
        for (final s in WatchStatus.values) {
          expect(malStatusFor(s, reading: false), s.mal);
        }
      },
    );
  });

  group('manga/novel paths — /v2/manga, num_chapters not num_episodes', () {
    test('malSearchPath', () {
      expect(
        malSearchPath(MediaKind.manga, 'Naruto'),
        'manga?q=Naruto&limit=1&fields=num_chapters',
      );
    });

    test('malTotalPath', () {
      expect(malTotalPath(MediaKind.manga, 21), 'manga/21?fields=num_chapters');
    });

    test('malEntryPath', () {
      expect(
        malEntryPath(MediaKind.manga, 21),
        'manga/21?fields=num_chapters,my_list_status',
      );
    });

    test('malSearchEntriesPath', () {
      expect(
        malSearchEntriesPath(MediaKind.manga, 'Naruto'),
        'manga?q=Naruto&limit=12&fields=num_chapters,media_type,start_season,main_picture',
      );
    });

    test('malListStatusPath', () {
      expect(malListStatusPath(MediaKind.manga, 21), 'manga/21/my_list_status');
    });

    test('malProgressField is num_chapters_read', () {
      expect(malProgressField(MediaKind.manga), 'num_chapters_read');
    });

    test(
      'malStatusFor(reading: true): watching→reading, planning→plan_to_read',
      () {
        expect(malStatusFor(WatchStatus.watching, reading: true), 'reading');
        expect(
          malStatusFor(WatchStatus.planning, reading: true),
          'plan_to_read',
        );
      },
    );

    test(
      'malStatusFor(reading: true): completed/paused/dropped are shared',
      () {
        expect(
          malStatusFor(WatchStatus.completed, reading: true),
          WatchStatus.completed.mal,
        );
        expect(
          malStatusFor(WatchStatus.paused, reading: true),
          WatchStatus.paused.mal,
        );
        expect(
          malStatusFor(WatchStatus.dropped, reading: true),
          WatchStatus.dropped.mal,
        );
      },
    );
  });

  group(
    'id-space isolation (manga resolver cache must not touch the anime one)',
    () {
      test('malRoot picks the right list root', () {
        expect(malRoot(MediaKind.anime), 'anime');
        expect(malRoot(MediaKind.manga), 'manga');
      });
    },
  );
}
