import 'package:dio/dio.dart';

import '../models/episode.dart';

/// Per-episode descriptions for the episode list. Best-effort: every method
/// returns an empty map on any error/timeout and never throws. Anime uses
/// AniZip (by MAL id — a separate API, unaffected by AniList throttling); movie
/// -source TV series use one TMDB season call. Results are cached per session.
class EpisodeMetadataService {
  EpisodeMetadataService(this._dio);

  final Dio _dio;
  static const String _tmdbBase = 'https://api.themoviedb.org/3';

  final Map<int, Map<int, String>> _animeCache = {};
  final Map<String, Map<int, String>> _tvCache = {};

  Future<Map<int, String>> animeEpisodeOverviews(int malId) async {
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

  Future<Map<int, String>> tvEpisodeOverviews(int tmdbId, int season) async {
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

  /// AniZip: `{ episodes: { "1": { overview }, ... } }` -> {number: overview}.
  static Map<int, String> parseAniZip(Object? data) {
    final out = <int, String>{};
    if (data is Map && data['episodes'] is Map) {
      (data['episodes'] as Map).forEach((k, v) {
        final n = int.tryParse('$k');
        final ov = (v is Map ? v['overview'] : null) as String?;
        if (n != null && ov != null && ov.trim().isNotEmpty) {
          out[n] = ov.trim();
        }
      });
    }
    return out;
  }

  /// TMDB season: `{ episodes: [ { episode_number, overview } ] }`.
  static Map<int, String> parseTmdbSeason(Object? data) {
    final out = <int, String>{};
    if (data is Map && data['episodes'] is List) {
      for (final e in data['episodes'] as List) {
        if (e is! Map) continue;
        final n = (e['episode_number'] as num?)?.toInt();
        final ov = e['overview'] as String?;
        if (n != null && ov != null && ov.trim().isNotEmpty) {
          out[n] = ov.trim();
        }
      }
    }
    return out;
  }
}

/// Return a copy of [eps] where episodes whose integer number is a key in
/// [byNumber] carry that description. Empty map -> the same list unchanged.
List<Episode> mergeDescriptions(List<Episode> eps, Map<int, String> byNumber) {
  if (byNumber.isEmpty) return eps;
  return [
    for (final e in eps)
      if (e.number != null &&
          e.number! == e.number!.roundToDouble() &&
          byNumber.containsKey(e.number!.toInt()))
        e.copyWith(description: byNumber[e.number!.toInt()])
      else
        e,
  ];
}
