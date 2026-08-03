import 'package:dio/dio.dart';

import '../models/episode.dart';
import '../models/provider_info.dart';

/// One episode's fetched extras. Either field may be null (source had only one).
typedef EpisodeMeta = ({String? title, String? overview});

/// Per-episode title + synopsis for the episode list. Best-effort: every method
/// returns an empty map on any error/timeout and never throws. Anime uses
/// AniZip (by MAL id — a separate API, unaffected by AniList throttling); movie
/// -source TV series use one TMDB season call. Results are cached per session.
class EpisodeMetadataService {
  EpisodeMetadataService(this._dio);

  final Dio _dio;
  static const String _tmdbBase = 'https://api.themoviedb.org/3';

  final Map<int, Map<int, EpisodeMeta>> _animeCache = {};
  final Map<String, Map<int, EpisodeMeta>> _tvCache = {};

  Future<Map<int, EpisodeMeta>> animeEpisodeMeta(int malId) async {
    final cached = _animeCache[malId];
    if (cached != null) return cached;
    try {
      final res = await _dio
          .get<dynamic>(
            'https://api.ani.zip/mappings?mal_id=$malId',
            options: Options(validateStatus: (s) => s != null && s < 500),
          )
          .timeout(const Duration(seconds: 6));
      final out = parseAniZip(res.data);
      _animeCache[malId] = out;
      return out;
    } catch (_) {
      return const {};
    }
  }

  Future<Map<int, EpisodeMeta>> tvEpisodeMeta(int tmdbId, int season) async {
    final key = '$tmdbId:$season';
    final cached = _tvCache[key];
    if (cached != null) return cached;
    try {
      final res = await _dio
          .get<dynamic>(
            '$_tmdbBase/tv/$tmdbId/season/$season',
            options: Options(validateStatus: (s) => s != null && s < 500),
          )
          .timeout(const Duration(seconds: 6));
      final out = parseTmdbSeason(res.data);
      _tvCache[key] = out;
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Return [episodes] with real title + synopsis filled in, best-effort. Anime
  /// (mal id) matches by absolute episode number in one AniZip call; a movie-
  /// source TV series (tmdb id + isTv) fetches each season and matches by number
  /// within it. Anything else / any miss returns the episodes unchanged.
  Future<List<Episode>> enrich({
    required List<Episode> episodes,
    required ProviderType type,
    int? malId,
    int? tmdbId,
    bool tmdbIsTv = false,
  }) async {
    if (episodes.isEmpty) return episodes;
    if (type == ProviderType.anime && malId != null) {
      final meta = await animeEpisodeMeta(malId);
      return mergeMeta(episodes, (e) => meta[_intNumber(e)]);
    }
    if (tmdbId != null && tmdbIsTv) {
      final seasons = <int>{for (final e in episodes) e.season ?? 1};
      final bySeason = <int, Map<int, EpisodeMeta>>{};
      for (final s in seasons) {
        bySeason[s] = await tvEpisodeMeta(tmdbId, s);
      }
      if (bySeason.values.every((m) => m.isEmpty)) return episodes;
      return mergeMeta(
        episodes,
        (e) => bySeason[e.season ?? 1]?[_intNumber(e)],
      );
    }
    return episodes;
  }

  /// AniZip: `{ episodes: { "1": { title{en}, overview }, ... } }`.
  static Map<int, EpisodeMeta> parseAniZip(Object? data) {
    final out = <int, EpisodeMeta>{};
    if (data is Map && data['episodes'] is Map) {
      (data['episodes'] as Map).forEach((k, v) {
        final n = int.tryParse('$k');
        if (n == null || v is! Map) return;
        final meta = _meta(_aniZipTitle(v['title']), v['overview']);
        if (meta != null) out[n] = meta;
      });
    }
    return out;
  }

  /// TMDB season: `{ episodes: [ { episode_number, name, overview } ] }`.
  static Map<int, EpisodeMeta> parseTmdbSeason(Object? data) {
    final out = <int, EpisodeMeta>{};
    if (data is Map && data['episodes'] is List) {
      for (final e in data['episodes'] as List) {
        if (e is! Map) continue;
        final n = (e['episode_number'] as num?)?.toInt();
        if (n == null) continue;
        final meta = _meta(e['name'], e['overview']);
        if (meta != null) out[n] = meta;
      }
    }
    return out;
  }

  /// AniZip stores title as a language map (`{en, x-jat, ...}`) or plain string.
  static String? _aniZipTitle(Object? title) {
    if (title is Map) {
      return (title['en'] ?? title['x-jat'] ?? title['ja']) as String?;
    }
    return title as String?;
  }

  /// Trim + null-out blanks; return null when both fields are empty (nothing
  /// worth merging), so callers can skip the episode.
  static EpisodeMeta? _meta(Object? title, Object? overview) {
    final t = (title is String && title.trim().isNotEmpty)
        ? title.trim()
        : null;
    final o = (overview is String && overview.trim().isNotEmpty)
        ? overview.trim()
        : null;
    return (t == null && o == null) ? null : (title: t, overview: o);
  }

  /// The episode's integer number when it has one (skips half-episode 12.5s).
  static int? _intNumber(Episode e) =>
      (e.number != null && e.number! == e.number!.roundToDouble())
      ? e.number!.toInt()
      : null;
}

/// Return a copy of [eps] where each episode carries the title + synopsis from
/// [lookup] (null → left unchanged). Titles land in [Episode.metaTitle]; the UI
/// decides whether to prefer it over the source's own title.
List<Episode> mergeMeta(
  List<Episode> eps,
  EpisodeMeta? Function(Episode) lookup,
) {
  var changed = false;
  final out = [
    for (final e in eps)
      () {
        final m = lookup(e);
        if (m == null) return e;
        changed = true;
        return e.copyWith(description: m.overview, metaTitle: m.title);
      }(),
  ];
  return changed ? out : eps;
}
