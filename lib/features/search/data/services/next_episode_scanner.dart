import 'package:mediavore/core/domain/entities/media_item.dart';
import 'package:mediavore/core/utils/watch_tail.dart';
import 'package:mediavore/features/search/data/services/media_details_service.dart';

/// Result of [NextEpisodeScanner.scan].
typedef NextEpisodeScan = ({EpisodeRef? episode, bool complete});

/// Walks a series' seasons to find the episode that follows a [WatchTail].
///
/// Shared by the Releases anchoring and the Quick Add queue so both use one
/// definition of "the next episode".
class NextEpisodeScanner {
  final MediaDetailsService details;

  NextEpisodeScanner(this.details);

  /// Finds the episode to anchor a series to.
  ///
  /// [NextEpisodeScan.episode] is the first episode after [tail] that aired and
  /// has not been seen; when every aired episode is seen it falls back to the
  /// first unseen episode regardless of air date (an announced or undated one,
  /// rendered as "date TBA" when it has no air date). Episodes whose key is in
  /// [seenKeys] are skipped, as are those rejected by [where] (see
  /// [findNextEpisodeAfterTail]). [NextEpisodeScan.complete] is `false` when a
  /// season could not be evaluated, so the caller can avoid destructive
  /// reconciliation on partial data.
  Future<NextEpisodeScan> scan(
    MediaItem? detailsItem,
    WatchTail tail,
    Set<String> seenKeys, {
    required bool forceRemote,
    required DateTime now,
    bool Function(EpisodeRef episode)? where,
  }) async {
    final series = detailsItem;
    if (series == null) return (episode: null, complete: false);

    final seasons = series.seasons;
    if (seasons == null || seasons.isEmpty) {
      return (episode: null, complete: false);
    }

    final sortedSeasons = List<TVSeason>.from(seasons)
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));

    final episodes = <EpisodeRef>[];
    var complete = true;
    EpisodeRef? aired;

    for (final season in sortedSeasons) {
      if (season.seasonNumber == 0) continue;
      if (season.seasonNumber < tail.seasonNumber) continue;

      final Map<String, dynamic> seasonDetails;
      try {
        seasonDetails = await details.seasonDetailsForRefresh(
          series.id,
          season.seasonNumber,
          forceRemote: forceRemote,
        );
      } catch (_) {
        // A season with no known episodes (e.g. an announced but unscheduled
        // next season) cannot contain a candidate, so its absence is not
        // "incomplete" data. Seasons that claim episodes make the scan partial.
        if (season.episodeCount > 0) complete = false;
        continue;
      }

      final rawEpisodes = seasonDetails['episodes'];
      if (rawEpisodes is! List) {
        if (season.episodeCount > 0) complete = false;
        continue;
      }

      for (final raw in rawEpisodes) {
        if (raw is! Map) continue;
        final epNum = raw['episode_number'] as int?;
        if (epNum == null) continue;
        final airDateStr = raw['air_date'] as String?;
        episodes.add(
          EpisodeRef(
            seasonNumber: season.seasonNumber,
            episodeNumber: epNum,
            airDate: (airDateStr == null || airDateStr.isEmpty)
                ? null
                : DateTime.tryParse(airDateStr),
            runtime: raw['runtime'] as int?,
          ),
        );
      }

      aired = findFirstAiredUnseenAfterTail(
        tail: tail,
        episodes: episodes,
        seenEpisodeKeys: seenKeys,
        now: now,
        where: where,
      );
      // The first aired unseen episode is final: any later episode sits after it.
      if (aired != null) break;
    }

    return (
      episode:
          aired ??
          findNextEpisodeAfterTail(
            tail: tail,
            episodes: episodes,
            seenEpisodeKeys: seenKeys,
            where: where,
          ),
      complete: complete,
    );
  }
}
