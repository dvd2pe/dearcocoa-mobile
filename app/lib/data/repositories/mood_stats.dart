/// Mood statistics computable in unit tests without Flutter dependencies.
/// Ported from the DearCocoa MVP (commit 675a61b, tests 10/10) onto the
/// memex base. Input rows: {'entry_date': 'YYYY-MM-DD', 'mood': int 1..5,
/// 'created_at': ISO string (optional)}.
class MoodStats {
  MoodStats._();

  /// Current streak: consecutive days with at least one entry, closed on
  /// today or yesterday (one empty day breaks it).
  static int currentStreak(List<Map<String, dynamic>> entries, DateTime now) {
    final days = _distinctDays(entries);
    if (days.isEmpty) return 0;
    var cursor = DateTime(now.year, now.month, now.day);
    final last = DateTime(days.last.year, days.last.month, days.last.day);
    final gap = daysBetween(last, cursor);
    if (gap > 1) return 0; // last entry older than yesterday
    if (gap == 1) {
      cursor = cursor.subtract(const Duration(days: 1)); // streak closed yesterday
    }
    var streak = 0;
    while (days.any((d) => sameDay(d, cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Longest streak across the whole history.
  static int longestStreak(List<Map<String, dynamic>> entries) {
    final days = _distinctDays(entries);
    if (days.isEmpty) return 0;
    var best = 1;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      run = daysBetween(days[i - 1], days[i]) == 1 ? run + 1 : 1;
      if (run > best) best = run;
    }
    return best;
  }

  /// Mood for the last [n] days (null = no entry that day). If several
  /// entries share a day, the most recent (created_at) wins.
  static List<({DateTime day, int? mood})> lastDays(
    List<Map<String, dynamic>> entries,
    DateTime now,
    int n,
  ) {
    final byDate = <String, Map<String, dynamic>>{};
    for (final e in entries) {
      final date = e['entry_date'] as String? ?? '';
      final created = (e['created_at'] as String?) ?? '';
      final existing = byDate[date];
      if (existing == null ||
          created.compareTo((existing['created_at'] as String?) ?? '') > 0) {
        byDate[date] = e;
      }
    }
    final result = <({DateTime day, int? mood})>[];
    var cursor = DateTime(now.year, now.month, now.day);
    for (var i = 0; i < n; i++) {
      final key = cursor.toIso8601String().substring(0, 10);
      final e = byDate[key];
      result.add((day: cursor, mood: e == null ? null : e['mood'] as int?));
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return result.reversed.toList();
  }

  /// Mood distribution (keys 1..5, value = number of entries).
  static Map<int, int> distribution(List<Map<String, dynamic>> entries) {
    final dist = <int, int>{for (var i = 1; i <= 5; i++) i: 0};
    for (final e in entries) {
      final mood = e['mood'];
      if (mood is int && mood >= 1 && mood <= 5) {
        dist[mood] = dist[mood]! + 1;
      }
    }
    return dist;
  }

  /// Average mood (null when no entry carries a mood).
  static double? averageMood(List<Map<String, dynamic>> entries) {
    final moods = entries
        .map((e) => e['mood'])
        .whereType<int>()
        .where((m) => m >= 1 && m <= 5)
        .toList();
    if (moods.isEmpty) return null;
    return moods.reduce((a, b) => a + b) / moods.length;
  }

  static List<DateTime> _distinctDays(List<Map<String, dynamic>> entries) {
    final set = <String>{};
    final days = <DateTime>[];
    for (final e in entries) {
      final date = e['entry_date'] as String? ?? '';
      if (date.isEmpty || !set.add(date)) continue;
      final d = DateTime.tryParse(date);
      if (d != null) days.add(d);
    }
    days.sort();
    return days;
  }
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int daysBetween(DateTime a, DateTime b) {
  final da = DateTime(a.year, a.month, a.day);
  final db = DateTime(b.year, b.month, b.day);
  return db.difference(da).inDays;
}
