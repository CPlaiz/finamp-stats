import 'package:audio_service/audio_service.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/services/music_player_background_task.dart';
import 'package:finamp/services/stats_persistance_helper.dart';
import 'package:get_it/get_it.dart';
import 'package:rxdart/rxdart.dart';

class StatsService {
  static List<PlaybackEntry> consolidatedPlaybackEntries = [];
  static List<PlaybackEntry> consecutivePlaybackEntries = [];

  static List<PlaybackEntry> get playbackEntries =>
      consolidatedPlaybackEntries + [?combinePlaybackEntries(consecutivePlaybackEntries)];
  static MediaItem? lastMediaItem;
  static Duration? playbackSegmentStartPosition;
  static DateTime? playbackSegmentStartTime;

  static void init() {
    consolidatedPlaybackEntries = StatsPersistanceHelper.persistentStats;
    listen();
  }

  static void saveEntry(MediaItem mediaItem, Duration startPosition, Duration endPosition, DateTime startTime) {
    Duration duration = endPosition - startPosition;
    consecutivePlaybackEntries.add(
      PlaybackEntry(trackInfo: TrackInfo.fromMediaItem(mediaItem), startTime: startTime, duration: duration),
    );
    reset();
  }

  static void reset() {
    playbackSegmentStartPosition = null;
    playbackSegmentStartTime = null;
  }

  static void startEntry(DateTime startTime, Duration startPosition) {
    playbackSegmentStartTime ??= startTime;
    playbackSegmentStartPosition ??= startPosition;
  }

  static void consolidateEntries() { // TODO: run on app exit
    consolidatedPlaybackEntries += [?combinePlaybackEntries(consecutivePlaybackEntries)];
    consecutivePlaybackEntries.clear();
    writeEntriesToPersistence();
  }

  static void writeEntriesToPersistence() {
    if (playbackEntries.isEmpty) return;
    StatsPersistanceHelper.updateEntries(playbackEntries);
  }

  static PlaybackEntry? combinePlaybackEntries(List<PlaybackEntry> entries) {
    if (entries.isEmpty) return null;
    final PlaybackEntry firstEntry = entries.first;
    return PlaybackEntry(
      trackInfo: firstEntry.trackInfo,
      startTime: firstEntry.startTime,
      duration: entries.fold(Duration.zero, (sum, entry) => sum + entry.duration),
    );
  }

  static void listen() {
    final audioHandler = GetIt.instance<MusicPlayerBackgroundTask>();
    Rx.combineLatest2<MediaItem?, PlaybackState, (MediaItem?, PlaybackState)>(
      audioHandler.mediaItem,
      audioHandler.playbackState,
      (mediaItem, state) => (mediaItem, state),
    ).pairwise().listen((eventPair) {
      final (previousMediaItem, previousPlaybackState) = eventPair[0];
      final (currentMediaItem, currentPlaybackState) = eventPair[1];
      final timestamp = DateTime.now();

      if (currentMediaItem == null) return;

      if (previousMediaItem != null) {
        if (currentMediaItem == previousMediaItem) {
          final Duration timeBetweenCycles = currentPlaybackState.position - previousPlaybackState.position;
          if (timeBetweenCycles.inSeconds != 0 &&
              playbackSegmentStartTime != null &&
              playbackSegmentStartPosition != null) {
            saveEntry(
              previousMediaItem,
              playbackSegmentStartPosition!,
              previousPlaybackState.position,
              playbackSegmentStartTime!,
            );
            if (currentPlaybackState.playing) {
              startEntry(timestamp, currentPlaybackState.position);
            }
          }
        } else {
          if (playbackSegmentStartTime != null && playbackSegmentStartPosition != null) {
            saveEntry(
              previousMediaItem,
              playbackSegmentStartPosition!,
              previousPlaybackState.position,
              playbackSegmentStartTime!,
            );
          }
          consolidateEntries();
          if (currentPlaybackState.playing) {
            startEntry(timestamp, currentPlaybackState.position);
          }
        }
      }

      if (previousPlaybackState.playing) {
        if (!currentPlaybackState.playing) {
          saveEntry(
            currentMediaItem,
            playbackSegmentStartPosition!,
            previousPlaybackState.position,
            playbackSegmentStartTime!,
          );
        }
      } else {
        if (currentPlaybackState.playing) {
          startEntry(timestamp, currentPlaybackState.position);
        }
      }
    });
  }

  static Map<String, int> calculatePlaycountRanking() {
    final Map<String, int> countsById = {};

    for (final play in playbackEntries) {
      final id = play.trackInfo.id;
      countsById[id] = (countsById[id] ?? 0) + 1;
    }
    return countsById;
  }

  static Map<String, Duration> calculatePlaytimeRanking() {
    final Map<String, Duration> timeById = {};

    for (final play in playbackEntries) {
      final id = play.trackInfo.id;
      timeById[id] = (timeById[id] ?? Duration.zero) + play.duration;
    }
    return timeById;
  }

  static Map<String, int> calculatePlaycountRankingForArtists() {
    final Map<String, int> countsById = {};

    for (final play in playbackEntries) {
      for (final artist in play.trackInfo.artists) {
        countsById[artist] = (countsById[artist] ?? 0) + 1;
      }
    }
    return countsById;
  }

  static Map<String, Duration> calculatePlaytimeRankingForArtists() {
    final Map<String, Duration> timeById = {};

    for (final play in playbackEntries) {
      for (final artist in play.trackInfo.artists) {
        timeById[artist] = (timeById[artist] ?? Duration.zero) + play.duration;
      }
    }
    return timeById;
  }
}
