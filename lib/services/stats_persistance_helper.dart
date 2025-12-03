import 'package:hive_ce_flutter/adapters.dart';

import '../models/finamp_models.dart';

class StatsPersistanceHelper {
  static PersistentStats get persistentStats => Hive.box<PersistentStats>("PersistentStats").get("PersistentStats", defaultValue: PersistentStats())!;

  static void _updatePersistentStats(PersistentStats newPersistentStats) =>
      Hive.box<PersistentStats>("PersistentStats").put("PersistentStats", newPersistentStats);

  static void updateConsecutiveEntries(List<PlaybackEntry> entries) {
    PersistentStats persistentStatsTemp = persistentStats;
    persistentStatsTemp.consecutiveEntries = entries;
    _updatePersistentStats(persistentStatsTemp);
  }

  static void updateConsolidatedEntries(List<PlaybackEntry> entries) {
    PersistentStats persistentStatsTemp = persistentStats;
    persistentStatsTemp.consolidatedEntries = entries;
    _updatePersistentStats(persistentStatsTemp);
  }

  static void updateLastStatsSync(DateTime newLastStatsSync) {
    PersistentStats persistentStatsTemp = persistentStats;
    persistentStatsTemp.lastStatsSync = newLastStatsSync;
    _updatePersistentStats(persistentStatsTemp);
  }
}
