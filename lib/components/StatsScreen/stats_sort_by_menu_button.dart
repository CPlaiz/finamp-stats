import 'package:finamp/components/global_snackbar.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/jellyfin_models.dart';
import '../../services/finamp_settings_helper.dart';

class StatsSortByMenuButton extends ConsumerWidget {
  const StatsSortByMenuButton({
    super.key,
    required this.tabType,
    this.sortByOverride,
    this.onOverrideChanged
  });

  final StatsTabContentType tabType;
  final StatsSortBy? sortByOverride;
  final void Function(StatsSortBy newStatsSortBy)? onOverrideChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sortOptions = StatsSortBy.defaultsFor(type: tabType);
    var selectedStatsSortBy = (sortByOverride ?? ref.watch(finampSettingsProvider.statsTabSortBy(tabType)));
    // PlayCount and Last Played are not representative in Offline Mode
    // so we disable it and overwrite it with the Sort Name if it was selected
    return PopupMenuButton<StatsSortBy>(
      icon: const Icon(Icons.sort),
      tooltip: AppLocalizations.of(context)!.sortBy,
      itemBuilder: (context) => [
        for (StatsSortBy sortBy in sortOptions)
          PopupMenuItem(
            value: sortBy,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      sortBy.getIcon(),
                      size: 18,
                      color: ((selectedStatsSortBy == sortBy) ? Theme.of(context).colorScheme.secondary : null),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sortBy.toLocalisedString(context),
                    style: TextStyle(
                      color: ((selectedStatsSortBy == sortBy) ? Theme.of(context).colorScheme.secondary : null),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      onSelected: (value) {
        if (sortByOverride != null && onOverrideChanged != null) {
          onOverrideChanged!(value);
        } else {
          FinampSetters.setStatsTabSortBy(tabType, value);
        }
      },
    );
  }
}
