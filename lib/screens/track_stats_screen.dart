import 'package:collection/collection.dart';
import 'package:finamp/components/album_image.dart';
import 'package:finamp/components/now_playing_bar.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/services/finamp_user_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../models/jellyfin_models.dart';

final _trackStatsScreenLogger = Logger("TrackStatsScreen");

class TrackStatsScreen extends ConsumerStatefulWidget {
  const TrackStatsScreen({super.key, this.widgetTrackStats});

  static const routeName = "/stats/track";

  final (BaseItemDto, List<PlaybackEntry>)? widgetTrackStats;

  @override
  ConsumerState<TrackStatsScreen> createState() => _TrackStatsScreenState();
}

class _TrackStatsScreenState extends ConsumerState<TrackStatsScreen> with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final (BaseItemDto, List<PlaybackEntry>) trackStatsData =
        widget.widgetTrackStats ?? ModalRoute.settingsOf(context)!.arguments as (BaseItemDto, List<PlaybackEntry>);
    final BaseItemDto item = trackStatsData.$1;
    final List<PlaybackEntry> playbackEntries = trackStatsData.$2;
    final playcount = _calculatePlaycount(playbackEntries);
    final playtime = _calculatePlaytime(playbackEntries);
    final firstPlay = _calculateFirstPlay(playbackEntries);
    final lastPlay = _calculateLastPlay(playbackEntries);

    ref.watch(FinampUserHelper.finampCurrentUserProvider);

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        titleSpacing: 0,
        // The surrounding iconButtons provide enough padding
        title: Text("Statistiken für ${item.name}"),
      ),
      bottomNavigationBar: const NowPlayingBar(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Cover
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 8,
            children: [
              SizedBox(
                height: 100,
                child: AlbumImage(
                  item: item,
                  borderRadius: BorderRadius.circular(8.0),
                  decoration: BoxDecoration(
                    boxShadow: [BoxShadow(blurRadius: 24, offset: Offset(0, 4), color: Colors.black.withOpacity(0.3))],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(item.name ?? ""), Text(item.artists?.join(", ") ?? "")],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3 rows of 2 buttons each
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 16) / 2; // subtract total horizontal spacing
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final item in [
                    _statsInfoBox("${playcount}x", 'times streamed', context),
                    _statsInfoBox(playtime.inMinutes.toString(), 'minutes streamed', context),
                    _statsInfoBox(firstPlay.startTime.toIso8601String(), 'First Stream', context),
                    _statsInfoBox(lastPlay.startTime.toIso8601String(), 'Last Stream', context),
                  ])
                    SizedBox(
                      width: itemWidth,
                      child: item,
                    ),
                ],
              );
            },
          )

        ],
      ),
    );
  }

  Widget _statsInfoBox(String title, String subtitle, BuildContext context) {
    return Card(
      color: Theme.of(context).cardColor, // uses app theme card color
      elevation: 2, // subtle shadow, can adjust
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // matches modern material style
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0), // inner spacing
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // align text to start
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge, // uses theme text
            ),
            const SizedBox(height: 8), // spacing between title & subtitle
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium, // themed subtitle
            ),
          ],
        ),
      ),
    );

  }

  Duration _calculatePlaytime(List<PlaybackEntry> playbackEntries) =>
      playbackEntries.fold<Duration>(Duration.zero, (total, play) => total + play.duration);

  int _calculatePlaycount(List<PlaybackEntry> playbackEntries) => playbackEntries.length;

  PlaybackEntry _calculateFirstPlay(List<PlaybackEntry> playbackEntries) =>
      playbackEntries.reduce((a, b) => a.startTime.isBefore(b.startTime) ? a : b);

  PlaybackEntry _calculateLastPlay(List<PlaybackEntry> playbackEntries) =>
      playbackEntries.reduce((a, b) => a.startTime.isAfter(b.startTime) ? a : b);
}
