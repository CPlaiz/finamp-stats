import 'package:collection/collection.dart';
import 'package:finamp/components/album_image.dart';
import 'package:finamp/components/now_playing_bar.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/services/finamp_user_helper.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:intl/intl.dart';

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
  final dateTimeFormatter = DateFormat('EEE, MMM d, y, H:mm:ss');
  final yearFormatter = DateFormat('y');

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
    final playcountsPerDay = _calculatePlayCountPerDay(playbackEntries);
    final playtimePerDay = _calculatePlaytimePerDay(playbackEntries);

    final firstDayPlayed = DateTime(firstPlay.startTime.year, firstPlay.startTime.month, firstPlay.startTime.day);
    final lastDayPlayed = DateTime(lastPlay.startTime.year, lastPlay.startTime.month, lastPlay.startTime.day);

    final dayRange = List.generate(
      lastDayPlayed.difference(firstDayPlayed).inDays + 1,
      (i) => DateTime(firstPlay.startTime.year, firstPlay.startTime.month, firstPlay.startTime.day + i),
    );

    final colorScheme = Theme.of(context).colorScheme;

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
          const SizedBox(height: 32),

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
                    _statsInfoBox(dateTimeFormatter.format(firstPlay.startTime.toLocal()), 'First Stream', context),
                    _statsInfoBox(dateTimeFormatter.format(lastPlay.startTime.toLocal()), 'Last Stream', context),
                  ])
                    SizedBox(width: itemWidth, child: item),
                ],
              );
            },
          ),

          const SizedBox(height: 32),

          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Row(
                spacing: 8,
                children: [
                  Container(width: 12, height: 12, color: colorScheme.secondary),
                  Text('Play count'),
                ],
              ),
              Row(
                spacing: 8,
                children: [
                  Container(width: 12, height: 12, color: colorScheme.tertiary),
                  Text('Playtime (min)'),
                ],
              ),
            ],
          ),
          Container(
            height: 350,
            padding: const EdgeInsets.all(20),
            width: MediaQuery.of(context).size.width * 0.9,
            decoration: BoxDecoration(color: colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
            child: BarChart(
              BarChartData(
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final date = dayRange[value.toInt()];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            date.month == 1 && date.day == 1 ? yearFormatter.format(date) : "",
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),

                barGroups: [
                  for (final (i, day) in dayRange.indexed)
                    BarChartGroupData(
                      x: i,
                      groupVertically: false, // makes them side-by-side
                      barRods: [
                        BarChartRodData(
                          toY: playcountsPerDay[day]?.toDouble() ?? 0,
                          color: colorScheme.secondary,
                          // change colors to differentiate
                          width: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        BarChartRodData(
                          toY: playtimePerDay[day]?.inMinutes.toDouble() ?? 0,
                          color: colorScheme.tertiary,
                          width: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                ],

                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final date = dayRange[group.x.toInt()];
                      final label = rodIndex == 0 ? "plays" : "minutes";
                      final value = rod.toY.toInt();

                      return BarTooltipItem(
                        '${date.day}.${date.month}.${date.year} - $value $label',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsInfoBox(String title, String subtitle, BuildContext context) {
    return Card(
      surfaceTintColor: Theme.of(context).colorScheme.primary, // uses app theme card color
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

  Map<DateTime, int> _calculatePlayCountPerDay(List<PlaybackEntry> entries) {
    final Map<DateTime, int> playCounts = {};
    for (final entry in entries) {
      final date = DateTime(entry.startTime.year, entry.startTime.month, entry.startTime.day);
      playCounts[date] = (playCounts[date] ?? 0) + 1;
    }
    return playCounts;
  }

  Map<DateTime, Duration> _calculatePlaytimePerDay(List<PlaybackEntry> entries) {
    final Map<DateTime, Duration> playtime = {};
    for (final entry in entries) {
      final date = DateTime(entry.startTime.year, entry.startTime.month, entry.startTime.day);
      playtime[date] = (playtime[date] ?? Duration.zero) + entry.duration;
    }
    return playtime;
  }
}
