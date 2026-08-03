import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'episode.g.dart';

/// One episode within a series. The video-native analogue of Sozo Read's
/// `Chapter` — same wire keys (`id/title/number/url/date`) plus two video
/// extras.
@JsonSerializable()
class Episode extends Equatable {
  final String id;
  final String title;
  final double? number;
  final String url;
  final String? date;
  final String? thumbnail;

  @JsonKey(defaultValue: false)
  final bool filler;

  /// Season number when the source reports one per episode (CloudStream does).
  /// Null for sources that don't — season is then derived from the title
  /// prefix. Not serialized: the detail screen always fetches episodes fresh,
  /// so this never needs to survive a JSON round-trip.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final int? season;

  /// Per-episode synopsis (AniZip/TMDB); null when unknown. Not serialized —
  /// episodes are always fetched fresh, like [season].
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? description;

  /// Real episode title from AniZip/TMDB, shown when the source only gives a
  /// generic "Episode N". Not serialized.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? metaTitle;

  /// Per-episode rating (0–10, AniZip/TMDB) and runtime in minutes. Not
  /// serialized — filled fresh on each detail load, like [description].
  @JsonKey(includeFromJson: false, includeToJson: false)
  final double? rating;
  @JsonKey(includeFromJson: false, includeToJson: false)
  final int? runtimeMinutes;

  const Episode({
    required this.id,
    required this.title,
    this.number,
    required this.url,
    this.date,
    this.thumbnail,
    this.filler = false,
    this.season,
    this.description,
    this.metaTitle,
    this.rating,
    this.runtimeMinutes,
  });

  factory Episode.fromJson(Map<String, dynamic> json) =>
      _$EpisodeFromJson(json);
  Map<String, dynamic> toJson() => _$EpisodeToJson(this);

  Episode copyWith({
    String? description,
    String? metaTitle,
    String? thumbnail,
    String? date,
    double? rating,
    int? runtimeMinutes,
  }) => Episode(
        id: id,
        title: title,
        number: number,
        url: url,
        date: date ?? this.date,
        thumbnail: thumbnail ?? this.thumbnail,
        filler: filler,
        season: season,
        description: description ?? this.description,
        metaTitle: metaTitle ?? this.metaTitle,
        rating: rating ?? this.rating,
        runtimeMinutes: runtimeMinutes ?? this.runtimeMinutes,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        number,
        url,
        date,
        thumbnail,
        filler,
        season,
        description,
        metaTitle,
        rating,
        runtimeMinutes,
      ];
}
