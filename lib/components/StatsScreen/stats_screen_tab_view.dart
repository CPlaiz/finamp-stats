import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:finamp/components/Buttons/cta_medium.dart';
import 'package:finamp/components/album_image.dart';
import 'package:finamp/components/global_snackbar.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/screens/track_stats_screen.dart';
import 'package:finamp/services/downloads_service.dart';
import 'package:finamp/services/finamp_user_helper.dart';
import 'package:finamp/services/jellyfin_api_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../models/jellyfin_models.dart';
import '../../services/finamp_settings_helper.dart';
import '../../services/stats_service.dart';
import '../first_page_progress_indicator.dart';
import '../new_page_progress_indicator.dart';

final statsScreenRefreshStream = StreamController<void>.broadcast();

class StatsScreenTabView extends ConsumerStatefulWidget {
  const StatsScreenTabView({
    super.key,
    required this.statsTabContentType,
    required this.view,
    this.refresh,
    this.tabBarFiltered = false,
    this.sortByOverride,
    this.sortOrderOverride,
  });

  final StatsTabContentType statsTabContentType;
  final BaseItemDto? view;
  final StatsRefreshCallback? refresh;
  final bool tabBarFiltered;
  final StatsSortBy? sortByOverride;
  final SortOrder? sortOrderOverride;

  @override
  ConsumerState<StatsScreenTabView> createState() => _StatsScreenTabViewState();
}

// We use AutomaticKeepAliveClientMixin so that the view keeps its position after the tab is changed.
// https://stackoverflow.com/questions/49439047/how-to-preserve-widget-states-in-flutter-when-navigating-using-bottomnavigation
class _StatsScreenTabViewState extends ConsumerState<StatsScreenTabView>
    with AutomaticKeepAliveClientMixin<StatsScreenTabView> {
  // tabs on the music screen should be kept alive
  @override
  bool get wantKeepAlive => true;

  static const _pageSize = 100;

  final PagingController<int, BaseItemDto> _pagingController = PagingController(
    firstPageKey: 0,
    invisibleItemsThreshold: 70,
  );

  Future<List<BaseItemDto>>? offlineSortedItems;

  final _jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
  final _isarDownloader = GetIt.instance<DownloadsService>();
  StreamSubscription<void>? _statsScreenRefreshStreamSubscription;
  StreamSubscription<void>? _downloadsRefreshStreamSubscription;

  late AutoScrollController controller;
  int _requestedPageKey = -1;
  Timer? timer;
  int? refreshHash;
  int refreshCount = 0;
  int fullyLoadedRefresh = -1;

  Map<String, int> rankingPlaycountForTracks = StatsService.calculatePlaycountRanking();
  Map<String, Duration> rankingPlaytimeForTracks = StatsService.calculatePlaytimeRanking();

  Map<String, int> rankingPlaycountForArtists = StatsService.calculatePlaycountRankingForArtists();
  Map<String, Duration> rankingPlaytimeForArtists = StatsService.calculatePlaytimeRankingForArtists();
  
  Map<String, List<PlaybackEntry>> playbackEntriesForTracks = StatsService.playbackEntriesForTracks;
  Map<String, List<PlaybackEntry>> playbackEntriesForArtists = StatsService.playbackEntriesForArtists;

  (Map<String, int>, Map<String, Duration>, Map<String, List<PlaybackEntry>>) get playbackData {
    switch (widget.statsTabContentType) {
      case StatsTabContentType.track:
        return (rankingPlaycountForTracks, rankingPlaytimeForTracks, playbackEntriesForTracks);
      case StatsTabContentType.artist:
        return (rankingPlaycountForArtists, rankingPlaytimeForArtists, playbackEntriesForArtists);
    }
  }

  Map<String, int> get rankingPlaycount => playbackData.$1;
  Map<String, Duration> get rankingPlaytime => playbackData.$2;
  Map<String, List<PlaybackEntry>> get playbackEntries => playbackData.$3;

  // This function just lets us easily set stuff to the getItems call we want.
  Future<void> _getPage(int pageKey) async {
    // The jump-to-letter widget and main view scrolling may generate duplicate page
    // requests.  Only fetch page once in these cases.
    if (pageKey <= _requestedPageKey) {
      return;
    }
    _requestedPageKey = pageKey;
    var settings = FinampSettingsHelper.finampSettings;
    if (settings.isOffline) {
      return _getPageOffline();
    }
    int localRefreshCount = refreshCount;
    try {
      var sortBy = widget.sortByOverride ??
          settings.statsTabSortBy[widget.statsTabContentType];
      final sortOrder = widget.sortOrderOverride ??
          settings.statsTabSortOrder[widget.statsTabContentType];

      List<BaseItemId> itemsToQuery = switch (sortBy) {
        StatsSortBy.time => rankingPlaytime.keys,
        StatsSortBy.count => rankingPlaycount.keys,
        StatsSortBy.defaultOrder => throw UnimplementedError(),
        null => throw UnimplementedError(),
      }.map((e) => BaseItemId(e)).toList();

       if (sortOrder == SortOrder.ascending) {
         itemsToQuery = itemsToQuery.reversed.toList(); // TODO: pagination
       }

      final items =
          (await _jellyfinApiHelper.getItems(
            sortBy: null,
            sortOrder: null,
            startIndex: pageKey,
            includeItemTypes: widget.statsTabContentType.itemType.idString,
            itemIds: itemsToQuery,
            limit: _pageSize,
          )) ??
              [];


      final newItems = sortItems(
          items, sortBy, sortOrder, rankingPlaycount, rankingPlaytime);

      // Skip appending page if a refresh triggered while processing
      if (localRefreshCount == refreshCount && mounted) {
        if (newItems.length < _pageSize) {
          _pagingController.appendLastPage(newItems);
          fullyLoadedRefresh = localRefreshCount;
        } else {
          _pagingController.appendPage(newItems, pageKey + newItems.length);
        }
      }
    } catch (e) {
      // Ignore errors when logging out
      if (GetIt
          .instance<FinampUserHelper>()
          .currentUser != null) {
        GlobalSnackbar.error(e);
      }
    }
  }

  Future<void> _getPageOffline() async {
    var settings = FinampSettingsHelper.finampSettings;
    int localRefreshCount = refreshCount;
    var artistInfoForType = (settings.defaultArtistType ==
        ArtistType.albumArtist)
        ? BaseItemDtoType.album
        : BaseItemDtoType.track;

    List<DownloadStub> offlineItems;
    // If we're on the tracks tab, just get all of the downloaded items
    // We should probably try to page this, at least if we are sorting by name
    offlineItems = await _isarDownloader.getAllTracks(
      viewFilter: widget.view?.id,
      nullableViewFilters: settings.showDownloadsWithUnknownLibrary,
      genreFilter: null,
    );

    var items = offlineItems
        .map((e) => e.baseItem)
        .nonNulls
        .toList();
    // PlayCount and Last Played are not representative in Offline Mode
    // so we disable it and overwrite it with the Sort Name if it was selected

    // Playlists use different genreIds due to their cross-library functionality.
    // In Online Mode, the api still returns correct data, but in Offline Mode,
    // we only have genres with their "libraryId" but playlists with their
    // "cross-library-genreIds", so we won't get any results. Therefore,
    // we have to load all playlists and manually filter by genreName.

    // Skip appending page if a refresh triggered while processing
    if (localRefreshCount == refreshCount && mounted) {
      _pagingController.appendLastPage(items);
      fullyLoadedRefresh = localRefreshCount;
    }
  }

  @override
  void initState() {
    _pagingController.addPageRequestListener((pageKey) {
      _getPage(pageKey);
    });
    controller = AutoScrollController(
      suggestedRowHeight: 72,
      viewportBoundaryGetter: () =>
          Rect.fromLTRB(0, 0, 0, MediaQuery
              .paddingOf(context)
              .bottom),
      axis: Axis.vertical,
    );
    _statsScreenRefreshStreamSubscription =
        statsScreenRefreshStream.stream.listen((_) {
          _refresh();
        });
    _downloadsRefreshStreamSubscription =
        _isarDownloader.offlineDeletesStream.listen((event) {
          _refresh();
        });
    updateRefreshHash();

    ref.listenManual(finampSettingsProvider, (_, __) {
      updateRefreshHash();
    });

    super.initState();
  }

  @override
  void didUpdateWidget(StatsScreenTabView oldWidget) {
    updateRefreshHash();
    super.didUpdateWidget(oldWidget);
  }

  Duration _getAnimationDurationForOffsetToIndex(int index) {
    final renderedIndices = controller.tagMap.keys;
    if (renderedIndices.isEmpty) return Duration(milliseconds: 200);
    final medianIndex = renderedIndices.elementAt(renderedIndices.length ~/ 2);

    final duration = Duration(
        milliseconds: ((medianIndex - index).abs() / 50 * 300)
            .clamp(200, 7500)
            .round());
    return duration;
  }

  @override
  void dispose() {
    _statsScreenRefreshStreamSubscription?.cancel();
    _downloadsRefreshStreamSubscription?.cancel();
    _pagingController.dispose();
    timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    refreshCount++;
    _requestedPageKey = -1;
    // This makes refreshing actually work in error cases
    _pagingController.value = const PagingState(nextPageKey: 0, itemList: []);
    _pagingController.refresh();
  }

  void updateRefreshHash() {
    final settings = FinampSettingsHelper.finampSettings;
    var newRefreshHash = Object.hash(
      settings.onlyShowFavorites,
      settings.statsTabSortBy[widget.statsTabContentType],
      widget.sortByOverride,
      settings.statsTabSortOrder[widget.statsTabContentType],
      widget.sortOrderOverride,
      settings.onlyShowFullyDownloaded,
      widget.view?.id,
      settings.isOffline,
      settings.tabOrder,
      settings.trackOfflineFavorites,
    );
    if (refreshHash == null) {
      refreshHash = newRefreshHash;
    } else if (refreshHash != newRefreshHash) {
      _refresh();
      refreshHash = newRefreshHash;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    widget.refresh?.callback = _refresh;

    final emptyListIndicator = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 32.0),
      child: Column(
        children: [
          Text(
            AppLocalizations.of(context)!.emptyFilteredListTitle,
            style: TextStyle(fontSize: 24),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ...[
            Text(
              AppLocalizations.of(context)!.emptyFilteredListSubtitle,
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            CTAMedium(
              icon: TablerIcons.filter_x,
              text: AppLocalizations.of(context)!.resetFiltersButton,
              onPressed: () {
                FinampSetters.setOnlyShowFavorites(
                    DefaultSettings.onlyShowFavorites);
                FinampSetters.setOnlyShowFullyDownloaded(
                    DefaultSettings.onlyShowFullyDownloaded);
              },
            ),
          ],
        ],
      ),
    );
    var tabContent = PagedListView<int, BaseItemDto>.separated(
      pagingController: _pagingController,
      scrollController: controller,
      physics: _DeferredLoadingAlwaysScrollableScrollPhysics(tabState: this),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      builderDelegate: PagedChildBuilderDelegate<BaseItemDto>(
        itemBuilder: (context, item, index) {
          String id = item.id.raw;
          int playcount = rankingPlaycount[id] ?? 0;
          int playtime = rankingPlaytime[id]?.inMinutes ?? 0;
          String trailing = !item.isArtist ? " • ${item
              .nullsafeArtistsString()}" : "";
          // Use right padding inherited from fast scroller minus
          // built-in icon padding
          return Padding(
            padding: EdgeInsets.only(right: max(0, MediaQuery
                .paddingOf(context)
                .right - 20)),
            child: CachedBuilder(
              key: ValueKey(item.id),
              cacheKey: (item.id, index),
              builder: (context) {
                return AutoScrollTag(
                  key: ValueKey(index),
                  controller: controller,
                  index: index,
                  child: ListTile(
                    leading: AlbumImage(
                        item: item, borderRadius: BorderRadius.circular(8.0)),
                    title: Text(item.name ?? "NULL"),
                    subtitle: Text(
                        "${playcount}x • $playtime Minuten$trailing"),
                    onTap: () {
                      Navigator.of(context).pushNamed(TrackStatsScreen
                          .routeName, arguments: (item, playbackEntries[id]));
                    },
                  ),
                );
              },
            ),
          );
        },
        firstPageProgressIndicatorBuilder: (
            _) => const FirstPageProgressIndicator(),
        newPageProgressIndicatorBuilder: (
            _) => const NewPageProgressIndicator(),
        noItemsFoundIndicatorBuilder: (_) => emptyListIndicator,
      ),
      separatorBuilder: (context, index) => const SizedBox.shrink(),
    );

    return RefreshIndicator(
        onRefresh: () async => _refresh(), child: tabContent);
  }
}

class StatsRefreshCallback {
  void call() => callback?.call();
  void Function()? callback;
}

class SliverGridDelegateWithFixedSizeTiles extends SliverGridDelegate {
  SliverGridDelegateWithFixedSizeTiles({required this.gridTileSize});

  final double gridTileSize;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    int crossAxisCount = (constraints.crossAxisExtent / gridTileSize).floor();
    // Ensure a minimum count of 1, can be zero and result in an infinite extent
    // below when the window size is 0.
    crossAxisCount = max(1, crossAxisCount);
    final double crossAxisSpacing = (constraints.crossAxisExtent /
        crossAxisCount);
    return SliverGridRegularTileLayout(
      crossAxisCount: crossAxisCount,
      mainAxisStride: gridTileSize,
      crossAxisStride: crossAxisSpacing,
      childMainAxisExtent: gridTileSize,
      childCrossAxisExtent: gridTileSize,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(SliverGridDelegateWithFixedSizeTiles oldDelegate) {
    return oldDelegate.gridTileSize != gridTileSize;
  }
}

class _DeferredLoadingAlwaysScrollableScrollPhysics
    extends AlwaysScrollableScrollPhysics {
  const _DeferredLoadingAlwaysScrollableScrollPhysics(
      {super.parent, required this.tabState});

  final _StatsScreenTabViewState tabState;

  @override
  _DeferredLoadingAlwaysScrollableScrollPhysics applyTo(
      ScrollPhysics? ancestor) {
    return _DeferredLoadingAlwaysScrollableScrollPhysics(
        parent: buildParent(ancestor), tabState: tabState);
  }

  @override
  bool recommendDeferredLoading(double velocity, ScrollMetrics metrics,
      BuildContext context) {
    return super.recommendDeferredLoading(velocity, metrics, context);
  }
}

List<BaseItemDto> sortItems(List<BaseItemDto> itemsToSort,
    StatsSortBy? sortBy,
    SortOrder? sortOrder,
    Map<String, int> playcountRanking,
    Map<String, Duration> playtimeRanking,) {
  itemsToSort.sortBy((a) {
    String id = a.id.raw;
    switch (sortBy ?? StatsSortBy.count) {
      case StatsSortBy.count:
        return playcountRanking[id] ?? 0;
      case StatsSortBy.time:
        return playtimeRanking[id]?.inSeconds ?? 0;
      default:
        throw UnimplementedError("Unimplemented sort mode $sortBy");
    }
  });

  return sortOrder == SortOrder.ascending
      ? itemsToSort.reversed.toList()
      : itemsToSort;
}

// This function helps to sort artist tracks in order they appear in the album list
// There are scenarios where cached provider-data might return a shuffled resultset, I guess,
// so this function should definitely sort all artist tracks always the same
List<BaseItemDto> sortArtistTracks(List<BaseItemDto> items) {
  int _compareNullable<T extends Comparable>(T? a, T? b,
      {bool nullsFirst = false}) {
    if (a == null && b == null) return 0;
    if (a == null) return nullsFirst ? -1 : 1;
    if (b == null) return nullsFirst ? 1 : -1;
    return a.compareTo(b);
  }

  int _compareAlbum(String? a, String? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;

    final numRegex = RegExp(r'^(\d+)');
    final matchA = numRegex.firstMatch(a);
    final matchB = numRegex.firstMatch(b);

    if (matchA != null && matchB != null) {
      final numA = int.tryParse(matchA.group(1)!);
      final numB = int.tryParse(matchB.group(1)!);
      if (numA != null && numB != null) {
        final cmp = numA.compareTo(numB);
        if (cmp != 0) return cmp;
      }
    }
    // fallback to normal string comparison
    return a.compareTo(b);
  }

  items.sort((a, b) {
    // 1. PremiereDate
    final dateA = a.premiereDate == null ? null : DateTime.tryParse(
        a.premiereDate!.trim());
    final dateB = b.premiereDate == null ? null : DateTime.tryParse(
        b.premiereDate!.trim());
    final dateCompare = _compareNullable<DateTime>(
        dateA, dateB, nullsFirst: true);
    if (dateCompare != 0) return dateCompare;
    // 2. Album (numbers first)
    final albumCompare = _compareAlbum(a.album, b.album);
    if (albumCompare != 0) return albumCompare;
    // 3. ParentIndexNumber
    final parentIndexCompare = _compareNullable<int>(
        a.parentIndexNumber, b.parentIndexNumber);
    if (parentIndexCompare != 0) return parentIndexCompare;
    // 4. IndexNumber
    final indexCompare = _compareNullable<int>(a.indexNumber, b.indexNumber);
    if (indexCompare != 0) return indexCompare;
    // 5. SortName
    return _compareNullable<String>(a.sortName, b.sortName);
  });

  return items;
}

List<BaseItemDto> filterItemsByGenreName(List<BaseItemDto> items,
    BaseItemDto genreFilter) {
  if (genreFilter.name == null) return [];

  return items.where((item) {
    final assignedGenres = item.genreItems;
    if (assignedGenres == null) return false;

    return assignedGenres.any((genre) => genre.name == genreFilter.name);
  }).toList();
}

class CachedBuilder<T> extends StatefulWidget {
  const CachedBuilder(
      {required this.builder, required this.cacheKey, super.key});

  final Widget Function(BuildContext context) builder;
  final T cacheKey;

  @override
  State<CachedBuilder<T>> createState() => _CachedBuilderState<T>();
}

class _CachedBuilderState<T> extends State<CachedBuilder<T>> {
  Widget? child;

  @override
  void didUpdateWidget(covariant CachedBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cacheKey != oldWidget.cacheKey) {
      child = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    child ??= widget.builder(context);
    return child!;
  }
}
