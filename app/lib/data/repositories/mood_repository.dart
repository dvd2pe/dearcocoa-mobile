import 'package:drift/drift.dart';

import '../../db/app_database.dart';

/// Mood tracking persistence (drift). Rows feed [MoodStats] helpers via the
/// plain-map shape it expects: {'entry_date', 'mood', 'created_at'}.
class MoodRepository {
  MoodRepository._();
  static final MoodRepository instance = MoodRepository._();

  /// Insert (or overwrite) the mood for a given day. One row per day: an
  /// existing row for the same (userId, entryDate) is updated.
  Future<void> setMoodForDay({
    required String userId,
    required String entryDate,
    required int mood,
    String note = '',
  }) async {
    assert(mood >= 1 && mood <= 5);
    final db = AppDatabase.instance;
    final existing = await (db.select(db.moodEntries)
          ..where((t) => t.userId.equals(userId) & t.entryDate.equals(entryDate)))
        .getSingleOrNull();
    if (existing != null) {
      await (db.update(db.moodEntries)
            ..where((t) => t.id.equals(existing.id)))
          .write(MoodEntriesCompanion(
        mood: Value(mood),
        note: Value(note),
        createdAt: Value(DateTime.now()),
      ));
    } else {
      await db.into(db.moodEntries).insert(MoodEntriesCompanion.insert(
            userId: userId,
            entryDate: entryDate,
            mood: mood,
            note: Value(note),
            createdAt: DateTime.now(),
          ));
    }
  }

  Future<int?> getMoodForDay({
    required String userId,
    required String entryDate,
  }) async {
    final db = AppDatabase.instance;
    final row = await (db.select(db.moodEntries)
          ..where((t) => t.userId.equals(userId) & t.entryDate.equals(entryDate)))
        .getSingleOrNull();
    return row?.mood;
  }

  /// All mood rows for the user, newest last. Shape matches [MoodStats].
  Future<List<Map<String, dynamic>>> getAllMoodRows(String userId) async {
    final db = AppDatabase.instance;
    final rows = await (db.select(db.moodEntries)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.entryDate, mode: OrderingMode.asc)
          ]))
        .get();
    return [
      for (final r in rows)
        {
          'entry_date': r.entryDate,
          'mood': r.mood,
          'created_at': r.createdAt.toIso8601String(),
        },
    ];
  }
}
