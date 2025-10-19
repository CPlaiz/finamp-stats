import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:finamp/components/StatsScreen/stats_screen_tab_view.dart';
import 'package:finamp/components/global_snackbar.dart';
import 'package:finamp/components/now_playing_bar.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/screens/music_screen.dart';
import 'package:finamp/services/audio_service_helper.dart';
import 'package:finamp/services/finamp_user_helper.dart';
import 'package:finamp/services/jellyfin_api_helper.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import '../models/jellyfin_models.dart';
import '../services/finamp_settings_helper.dart';

final _statsScreenLogger = Logger("StatsScreen");

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({
    super.key,
    this.genreFilter,
    this.tabTypeFilter,
    this.sortByOverrideInit,
    this.sortOrderOverrideInit,
    this.isFavoriteOverrideInit,
  });

  static const routeName = "/stats";

  // Optional parameters for genre and tab filtering
  final BaseItemDto? genreFilter;
  final StatsTabContentType? tabTypeFilter;
  final SortBy? sortByOverrideInit;
  final SortOrder? sortOrderOverrideInit;
  final bool? isFavoriteOverrideInit;

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen>
    with TickerProviderStateMixin {
  bool isSearching = false;
  TextEditingController textEditingController = TextEditingController();
  final Map<StatsTabContentType, StatsRefreshCallback> refreshMap = {};
  SortBy? sortByOverride;
  SortOrder? sortOrderOverride;
  bool? isFavoriteOverride;

  TabController? _tabController;

  final _audioServiceHelper = GetIt.instance<AudioServiceHelper>();
  final _finampUserHelper = GetIt.instance<FinampUserHelper>();
  final _jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();

  void _tabIndexCallback() {
    // We have to rebuild, otherwise the Action Buttons
    // in the AppBar might not get the correct current tab
    setState(() {});
  }

  void _buildTabController() {
    _tabController?.removeListener(_tabIndexCallback);

    final tabs = [StatsTabContentType.all];

    _tabController =
        TabController(length: tabs.length, vsync: this, initialIndex: 0);

    _tabController!.addListener(_tabIndexCallback);
  }

  @override
  void initState() {
    super.initState();
    sortByOverride = widget.sortByOverrideInit;
    sortOrderOverride = widget.sortOrderOverrideInit;
    isFavoriteOverride = widget.isFavoriteOverrideInit;
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  FloatingActionButton? getFloatingActionButton(
      List<StatsTabContentType> sortedTabs) {
    // Show the floating action button only on the albums, artists, generes and tracks tab.
    if (_tabController!.index ==
        sortedTabs.indexOf(StatsTabContentType.all)) {
      return FloatingActionButton(
        tooltip: AppLocalizations.of(context)!.shuffleAll,
        onPressed: () async {
          try {
            await _audioServiceHelper.shuffleAll(
              onlyShowFavorites:
              (isFavoriteOverride == true ||
                  (isFavoriteOverride == null &&
                      ref.read(finampSettingsProvider.onlyShowFavorites))),
              genreFilter: widget.genreFilter,
            );
          } catch (e) {
            GlobalSnackbar.error(e);
          }
        },
        child: const Icon(Icons.shuffle),
      );
    } else {
      return null;
    }
  }

  void refreshTab(StatsTabContentType tabType) {
    refreshMap[tabType]?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_tabController == null) {
      _buildTabController();
    }
    ref.watch(FinampUserHelper.finampCurrentUserProvider);
    // Get the filtered tab or the tabs from the user's tab order,
    // and filter them to only include enabled tabs
    /*final sortedTabs = widget.tabTypeFilter != null
        ? [widget.tabTypeFilter!]
        : ref
        .watch(finampSettingsProvider.tabOrder);*/
    final sortedTabs = [StatsTabContentType.all];
    refreshMap[sortedTabs.elementAt(_tabController!.index)] =
        StatsRefreshCallback();

    if (sortedTabs.length != _tabController?.length) {
      _statsScreenLogger.info(
        "Rebuilding StatsScreen tab controller (${sortedTabs
            .length} != ${_tabController?.length})",
      );
      _buildTabController();
    }

    return PopScope(
      canPop: !isSearching,
      child: Scaffold(
        extendBody: true,
        appBar: AppBar(
          titleSpacing: 0,
          // The surrounding iconButtons provide enough padding
          title: Text("Statistiken"),
          bottom: widget.genreFilter == null
              ? TabBar(
            controller: _tabController,
            tabs: sortedTabs
                .map(
                  (tabType) =>
                  Tab(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 50),
                      alignment: Alignment.center,
                      child: Text(tabType.name.toUpperCase()),
                    ),
                  ),
            ).toList(),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
          )
              : PreferredSize(
            preferredSize: const Size.fromHeight(36),
            child: Container(
              alignment: Alignment.centerLeft,
              width: double.infinity,
              height: 36.0,
              padding: EdgeInsets.only(left: 12, right: 12),
              color: Theme
                  .of(context)
                  .colorScheme
                  .primary,
              child: Text(
                widget.genreFilter?.name ?? "",
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme
                    .of(context)
                    .colorScheme
                    .onPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          leading: (widget.genreFilter != null ? BackButton(onPressed: () => Navigator.of(context).pop()) : null),
          actions: [
            if (!Platform.isIOS && !Platform.isAndroid)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  refreshMap[sortedTabs.elementAt(_tabController!.index)]!();
                },
              ),
            /*SortOrderButton(
              tabType: sortedTabs.elementAt(_tabController!.index),
              sortOrderOverride: sortOrderOverride,
              onOverrideChanged: (newOrder) =>
                  setState(() {
                    sortOrderOverride = newOrder;
                  }),
            ),
            SortByMenuButton(
              tabType: sortedTabs.elementAt(_tabController!.index),
              sortByOverride: sortByOverride,
              onOverrideChanged: (newSortBy) =>
                  setState(() {
                    sortByOverride = newSortBy;
                  }),
            ),*/
            if (ref.watch(finampSettingsProvider.isOffline) &&
                sortedTabs.elementAt(_tabController!.index) !=
                    StatsTabContentType.all)
              IconButton(
                icon: ref.watch(finampSettingsProvider.onlyShowFullyDownloaded)
                    ? const Icon(Icons.download)
                    : const Icon(Icons.download_outlined),
                onPressed: ref.read(finampSettingsProvider.isOffline)
                    ? () =>
                    FinampSetters.setOnlyShowFullyDownloaded(
                      !ref.read(finampSettingsProvider.onlyShowFullyDownloaded),
                    )
                    : null,
                tooltip: AppLocalizations.of(context)!.onlyShowFullyDownloaded,
              )
          ],
        ),
        bottomNavigationBar: const NowPlayingBar(),
        floatingActionButton: Padding(
          padding: EdgeInsets.only(
              right: ref.watch(finampSettingsProvider.showFastScroller)
                  ? 24.0
                  : 8.0),
          child: getFloatingActionButton(sortedTabs.toList()),
        ),
        body: Builder(
          builder: (context) {
            final child = TabBarView(
              controller: _tabController,
              physics: ref.watch(finampSettingsProvider.disableGesture) ||
                  MediaQuery.disableAnimationsOf(context)
                  ? const NeverScrollableScrollPhysics()
                  : widget.tabTypeFilter != null
                  ? NeverScrollableScrollPhysics()
                  : AlwaysScrollableScrollPhysics(),
              dragStartBehavior: DragStartBehavior.down,
              children: sortedTabs.map((tabType) {
                return Column(
                  children: [
                    /*ArtistTypeSelectionRow(
                      tabType: tabType,
                      defaultArtistType: ref.watch(
                          finampSettingsProvider.defaultArtistType),
                      refreshTab: refreshTab,
                    ),*/
                    Expanded(
                      child: StatsScreenTabView(
                        statsTabContentType: tabType,
                        view: _finampUserHelper.currentUser?.currentView,
                        refresh: refreshMap[tabType],
                        genreFilter:
                        (widget.genreFilter != null &&
                            (tabType == StatsTabContentType.all))
                            ? widget.genreFilter
                            : null,
                        tabBarFiltered: (widget.tabTypeFilter != null),
                        sortByOverride: sortByOverride,
                        sortOrderOverride: sortOrderOverride,
                        isFavoriteOverride: isFavoriteOverride,
                      ),
                    ),
                  ],
                );
              }).toList(),
            );

            if (Platform.isAndroid) {
              return TransparentRightSwipeDetector(
                action: () {
                  if (_tabController?.index == 0 &&
                      !ref.watch(finampSettingsProvider.disableGesture)) {
                    Scaffold.of(context).openDrawer();
                  }
                },
                child: child,
              );
            }

            return child;
          },
        ),
      ),
    );
  }
}