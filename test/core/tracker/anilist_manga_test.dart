import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/anilist/anilist_api.dart';
import 'package:watch_app/core/tracker/tracker.dart';

// Golden strings: the EXACT query text anilist_api.dart sent for anime before
// this file existed. Copied verbatim (not retyped) from the pre-refactor
// source so a change to any of these fails loudly — the whole point of Task
// 15 is that MediaKind.manga must not perturb the anime request by one byte.
const _malIdAnimeGolden =
    r'query($idMal:Int){ Media(idMal:$idMal, type:ANIME){ id episodes } }';
const _searchAnimeGolden =
    r'query($search:String){ Media(search:$search, type:ANIME){ id episodes } }';
const _entryAnimeGolden =
    r'query($id:Int){ Media(id:$id){ episodes '
    r'nextAiringEpisode{ episode airingAt } '
    r'mediaListEntry{ status score(format:POINT_10) progress } } }';
const _searchMediaAnimeGolden =
    r'query($q:String,$n:Int){ Page(perPage:$n){ media(search:$q,type:ANIME){ '
    r'id idMal episodes format seasonYear '
    r'title{ romaji english } coverImage{ medium } } } }';

void main() {
  group('anime queries — golden (byte-identical to pre-Task-15 text)', () {
    test('mediaByMalIdQuery', () {
      expect(mediaByMalIdQuery(MediaKind.anime), _malIdAnimeGolden);
    });

    test('mediaBySearchQuery', () {
      expect(mediaBySearchQuery(MediaKind.anime), _searchAnimeGolden);
    });

    test('mediaEntryQuery', () {
      expect(mediaEntryQuery(MediaKind.anime), _entryAnimeGolden);
    });

    test('searchMediaQuery', () {
      expect(searchMediaQuery(MediaKind.anime), _searchMediaAnimeGolden);
    });

    test('searchMediaQuery ignores novelFormat when kind is anime', () {
      // A novel is a manga sub-format on AniList — the flag must be inert
      // outside MediaKind.manga, even if a caller passes it by mistake.
      expect(
        searchMediaQuery(MediaKind.anime, novelFormat: true),
        _searchMediaAnimeGolden,
      );
    });
  });

  group('manga queries — type: MANGA, chapters/volumes not episodes', () {
    test('mediaByMalIdQuery', () {
      final q = mediaByMalIdQuery(MediaKind.manga);
      expect(q, contains('type:MANGA'));
      expect(q, contains('chapters'));
      expect(q, contains('volumes'));
      expect(q, isNot(contains('episodes')));
      expect(q, isNot(contains('type:ANIME')));
    });

    test('mediaBySearchQuery', () {
      final q = mediaBySearchQuery(MediaKind.manga);
      expect(q, contains('type:MANGA'));
      expect(q, contains('chapters'));
      expect(q, contains('volumes'));
      expect(q, isNot(contains('episodes')));
    });

    test('mediaEntryQuery selects chapters+volumes, keeps the rest intact', () {
      final q = mediaEntryQuery(MediaKind.manga);
      expect(q, contains('chapters'));
      expect(q, contains('volumes'));
      expect(q, isNot(contains('episodes')));
      // Everything else about the entry read is unchanged.
      expect(q, contains('nextAiringEpisode{ episode airingAt }'));
      expect(
        q,
        contains('mediaListEntry{ status score(format:POINT_10) progress }'),
      );
    });

    test('searchMediaQuery', () {
      final q = searchMediaQuery(MediaKind.manga);
      expect(q, contains('type:MANGA'));
      expect(q, contains('chapters'));
      expect(q, contains('volumes'));
      expect(q, isNot(contains('episodes')));
      expect(q, isNot(contains('format_in')));
    });

    test('searchMediaQuery(novelFormat: true) adds format_in: [NOVEL]', () {
      final q = searchMediaQuery(MediaKind.manga, novelFormat: true);
      expect(q, contains('type:MANGA'));
      expect(q, contains('format_in:[NOVEL]'));
    });

    test('searchMediaQuery(novelFormat: false) stays plain manga', () {
      final q = searchMediaQuery(MediaKind.manga, novelFormat: false);
      expect(q, isNot(contains('format_in')));
    });
  });
}
