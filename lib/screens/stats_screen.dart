import 'dart:io';

import 'package:finamp/components/StatsScreen/stats_screen_tab_view.dart';
import 'package:finamp/components/StatsScreen/stats_sort_by_menu_button.dart';
import 'package:finamp/components/StatsScreen/stats_sort_order_button.dart';
import 'package:finamp/components/now_playing_bar.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/screens/music_screen.dart';
import 'package:finamp/services/finamp_user_helper.dart';
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
    this.tabTypeFilter,
    this.sortByOverrideInit,
    this.sortOrderOverrideInit,
  });

  static const routeName = "/stats";

  // Optional parameters for genre and tab filtering
  final StatsTabContentType? tabTypeFilter;
  final StatsSortBy? sortByOverrideInit;
  final SortOrder? sortOrderOverrideInit;

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen>
    with TickerProviderStateMixin {
  bool isSearching = false;
  TextEditingController textEditingController = TextEditingController();
  final Map<StatsTabContentType, StatsRefreshCallback> refreshMap = {};
  StatsSortBy? sortByOverride;
  SortOrder? sortOrderOverride;

  TabController? _tabController;

  final _finampUserHelper = GetIt.instance<FinampUserHelper>();

  void _tabIndexCallback() {
    // We have to rebuild, otherwise the Action Buttons
    // in the AppBar might not get the correct current tab
    setState(() {});
  }

  void _buildTabController() {
    _tabController?.removeListener(_tabIndexCallback);

    final tabs = StatsTabContentType.values;

    _tabController =
        TabController(length: tabs.length, vsync: this, initialIndex: 0);

    _tabController!.addListener(_tabIndexCallback);
  }

  @override
  void initState() {
    super.initState();
    sortByOverride = widget.sortByOverrideInit;
    sortOrderOverride = widget.sortOrderOverrideInit;
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
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
    final sortedTabs = StatsTabContentType.values;
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
          bottom:  TabBar(
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
          ),
          //leading: (widget.genreFilter != null ? BackButton(onPressed: () => Navigator.of(context).pop()) : null),
          actions: [
            if (!Platform.isIOS && !Platform.isAndroid)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  refreshMap[sortedTabs.elementAt(_tabController!.index)]!();
                },
              ),
            StatsSortOrderButton(
              tabType: sortedTabs.elementAt(_tabController!.index),
              sortOrderOverride: sortOrderOverride,
              onOverrideChanged: (newOrder) =>
                  setState(() {
                    sortOrderOverride = newOrder;
                  }),
            ),
            StatsSortByMenuButton(
              tabType: sortedTabs.elementAt(_tabController!.index),
              sortByOverride: sortByOverride,
              onOverrideChanged: (newSortBy) =>
                  setState(() {
                    sortByOverride = newSortBy;
                  }),
            ),
            if (ref.watch(finampSettingsProvider.isOffline) &&
                sortedTabs.elementAt(_tabController!.index) !=
                    StatsTabContentType.track)
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
                    Expanded(
                      child: StatsScreenTabView(
                        statsTabContentType: tabType,
                        view: _finampUserHelper.currentUser?.currentView,
                        refresh: refreshMap[tabType],
                        tabBarFiltered: (widget.tabTypeFilter != null),
                        sortByOverride: sortByOverride,
                        sortOrderOverride: sortOrderOverride,
                      ),
                    ),
                  ],
                );
              }).toList(),
            );
            return child;
          },
        ),
      ),
    );
  }
}