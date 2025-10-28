import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:collection/collection.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:finamp/services/jellyfin_api_helper.dart';
import 'package:finamp/services/music_player_background_task.dart';
import 'package:finamp/services/stats_persistance_helper.dart';
import 'package:get_it/get_it.dart';
import 'package:rxdart/rxdart.dart';

class StatsService {
  static List<PlaybackEntry> consolidatedPlaybackEntries = [];
  static List<PlaybackEntry> consecutivePlaybackEntries = [];

  static List<PlaybackEntry> get playbackEntries {
    final combined = combinePlaybackEntries(consecutivePlaybackEntries);

    // Only add if combined is not null
    if (combined != null) {
      return consolidatedPlaybackEntries + [combined];
    } else {
      return consolidatedPlaybackEntries;
    }
  }
  static MediaItem? lastMediaItem;
  static Duration? playbackSegmentStartPosition;
  static DateTime? playbackSegmentStartTime;

  static Map<String, List<PlaybackEntry>> get playbackEntriesForTracks =>
      groupBy(playbackEntries, (entry) => entry.trackId);

  static Map<String, List<PlaybackEntry>> get playbackEntriesForArtists => playbackEntries
      .expand((entry) => entry.artistIds.map((artist) => MapEntry(artist, entry)))
      .fold(<String, List<PlaybackEntry>>{}, (map, entry) => map..putIfAbsent(entry.key, () => []).add(entry.value));

  static void init() {
    consolidatedPlaybackEntries = StatsPersistanceHelper.persistentStats;
    listen();
    startSyncTimer();
  }

  static void startSyncTimer() {
    print("start timer");
    Timer.periodic(const Duration(minutes: 1), (timer) async {
        await syncWithServer();
    });
  }

  static Future<void> syncWithServer() async {
    final settings = FinampSettingsHelper.finampSettings;
    var lastStatsSync = settings.lastStatsSync;
    var newLastStatsSync = DateTime.timestamp();
    final results = await Future.wait([
      getEntriesFromServer(lastStatsSync),
      pushNewEntries(lastStatsSync, playbackEntries),
    ]);

    final newEntries = results[0] as List<PlaybackEntry>?;
    final pushResult = results[1] as bool;

    if (newEntries != null && pushResult) {
      FinampSetters.setLastStatsSync(newLastStatsSync);
      consolidatedPlaybackEntries += newEntries;
    }
  }

  static Future<List<PlaybackEntry>?> getEntriesFromServer(DateTime? lastStatsSync) async {
    var apiHelper = GetIt.instance<JellyfinApiHelper>();
    return apiHelper.getUserTrackItems(since: lastStatsSync);
  }

  static Future<bool> pushNewEntries(DateTime? lastStatsSync, List<PlaybackEntry> entries) async {
    final newEntries = lastStatsSync == null
        ? entries
        : entries.where((obj) => obj.startTime.isAfter(lastStatsSync)).toList();

    if (newEntries.isEmpty) return true;

    var apiHelper = GetIt.instance<JellyfinApiHelper>();

    return apiHelper.addUserTrackItems(playbackEntries: newEntries);
  }

  static void saveEntry(
    String id,
    List<String> artistIds,
    Duration startPosition,
    Duration endPosition,
    DateTime startTime,
  ) {
    Duration duration = endPosition - startPosition;
    consecutivePlaybackEntries.add(
      PlaybackEntry(trackId: id, artistIds: artistIds, startTime: startTime, duration: duration),
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

  static void consolidateEntries() {
    // TODO: run on app exit
    final combined = combinePlaybackEntries(consecutivePlaybackEntries);
    if (combined != null) {
      consolidatedPlaybackEntries.add(combined);
    }
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
      trackId: firstEntry.trackId,
      artistIds: firstEntry.artistIds,
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
      final timestamp = DateTime.timestamp();

      String? currentItemId;
      String? previousItemId;
      List<String>? currentArtistIds;
      List<String>? previousArtistIds;
      if (currentMediaItem != null) {
        final extras = currentMediaItem.extras;
        if (extras != null && extras["itemJson"] is Map<String, dynamic>) {
          final itemJson = extras["itemJson"] as Map<String, dynamic>;
          if (itemJson["Id"] is String) {
            currentItemId = itemJson["Id"] as String;
            currentArtistIds =  (itemJson["ArtistItems"] as List<dynamic>?)?.map((e) => e['Id'] as String).toList();
          }
        }
      }

      if (previousMediaItem != null) {
        final extras = previousMediaItem.extras;
        if (extras != null && extras["itemJson"] is Map<String, dynamic>) {
          final itemJson = extras["itemJson"] as Map<String, dynamic>;
          if (itemJson["Id"] is String) {
            previousItemId = itemJson["Id"] as String;
            previousArtistIds = (itemJson["ArtistItems"] as List<dynamic>?)?.map((e) => e['Id'] as String).toList();
          }
        }
      }

      if (currentMediaItem == null) return;

      if (previousMediaItem != null) {
        if (currentMediaItem == previousMediaItem) {
          final Duration timeBetweenCycles = currentPlaybackState.position - previousPlaybackState.position;
          if (timeBetweenCycles.inSeconds != 0 &&
              playbackSegmentStartTime != null &&
              playbackSegmentStartPosition != null) {
            saveEntry(
              previousItemId!,
              previousArtistIds!,
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
              previousItemId!,
              previousArtistIds!,
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
            currentItemId!,
            currentArtistIds!,
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
      final id = play.trackId;
      countsById[id] = (countsById[id] ?? 0) + 1;
    }
    return countsById;
  }

  static Map<String, Duration> calculatePlaytimeRanking() {
    final Map<String, Duration> timeById = {};

    for (final play in playbackEntries) {
      final id = play.trackId;
      timeById[id] = (timeById[id] ?? Duration.zero) + play.duration;
    }
    return timeById;
  }

  static Map<String, int> calculatePlaycountRankingForArtists() {
    final Map<String, int> countsById = {};

    for (final play in playbackEntries) {
      for (final artist in play.artistIds) {
        countsById[artist] = (countsById[artist] ?? 0) + 1;
      }
    }
    return countsById;
  }

  static Map<String, Duration> calculatePlaytimeRankingForArtists() {
    final Map<String, Duration> timeById = {};

    for (final play in playbackEntries) {
      for (final artist in play.artistIds) {
        timeById[artist] = (timeById[artist] ?? Duration.zero) + play.duration;
      }
    }
    return timeById;
  }
}
