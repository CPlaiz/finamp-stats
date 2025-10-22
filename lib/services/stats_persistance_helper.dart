import 'package:hive_ce_flutter/adapters.dart';

import '../models/finamp_models.dart';

class StatsPersistanceHelper {
  static List<PlaybackEntry> get persistentStats =>
      Hive.box<PlaybackEntry>("PersistentStats").values.toList();

  static void updateEntries(List<PlaybackEntry> entries) {
    Box<PlaybackEntry> box = Hive.box<PlaybackEntry>("PersistentStats");
    box.clear();
    box.addAll(entries);
  }
}
