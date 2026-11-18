import 'package:flutter_test/flutter_test.dart';

import 'package:dearcocoa/data/repositories/mood_stats.dart';

Map<String, dynamic> entry(String date, int? mood, {String createdAt = '2026-01-01T10:00:00Z'}) =>
    {'entry_date': date, 'mood': mood, 'created_at': createdAt};

void main() {
  final now = DateTime(2026, 6, 10, 12); // mercoledì

  group('MoodStats.currentStreak', () {
    test('zero senza voci', () {
      expect(MoodStats.currentStreak([], now), 0);
    });

    test('streak continua se c\'è voce oggi', () {
      final entries = [
        entry('2026-06-10', 4),
        entry('2026-06-09', 3),
        entry('2026-06-08', 2),
      ];
      expect(MoodStats.currentStreak(entries, now), 3);
    });

    test('streak valida se l\'ultima voce è ieri', () {
      final entries = [entry('2026-06-09', 4), entry('2026-06-08', 3)];
      expect(MoodStats.currentStreak(entries, now), 2);
    });

    test('streak azzerata se ultima voce due giorni fa', () {
      final entries = [entry('2026-06-08', 4)];
      expect(MoodStats.currentStreak(entries, now), 0);
    });

    test('giorni duplicati contano una volta', () {
      final entries = [
        entry('2026-06-10', 2, createdAt: '2026-06-10T09:00:00Z'),
        entry('2026-06-10', 4, createdAt: '2026-06-10T18:00:00Z'),
        entry('2026-06-09', 3),
      ];
      expect(MoodStats.currentStreak(entries, now), 2);
    });
  });

  group('MoodStats.longestStreak', () {
    test('trova il massimo in mezzo al month', () {
      final entries = [
        entry('2026-06-01', 3),
        entry('2026-06-03', 3),
        entry('2026-06-04', 4),
        entry('2026-06-05', 5),
        entry('2026-06-10', 2),
      ];
      expect(MoodStats.longestStreak(entries), 3);
    });
  });

  group('MoodStats.distribution', () {
    test('conta solo mood validi 1..5', () {
      final entries = [
        entry('2026-06-01', 1),
        entry('2026-06-02', 5),
        entry('2026-06-03', 5),
        entry('2026-06-04', null),
        entry('2026-06-05', 9), // invalido
      ];
      final dist = MoodStats.distribution(entries);
      expect(dist[1], 1);
      expect(dist[5], 2);
      expect(dist[3], 0);
    });
  });

  group('MoodStats.lastDays', () {
    test('serie di 14 giorni con null dove mancano voci; vince la più recente', () {
      final entries = [
        entry('2026-06-10', 2, createdAt: '2026-06-10T09:00:00Z'),
        entry('2026-06-10', 4, createdAt: '2026-06-10T20:00:00Z'),
      ];
      final series = MoodStats.lastDays(entries, now, 3);
      expect(series.length, 3);
      expect(series[0].mood, isNull); // 8 giugno
      expect(series[1].mood, isNull); // 9 giugno
      expect(series[2].mood, 4); // 10 giugno, voce più recente
    });
  });

  group('MoodStats.averageMood', () {
    test('null senza mood validi', () {
      expect(MoodStats.averageMood([entry('2026-06-01', null)]), isNull);
    });

    test('media corretta', () {
      final avg = MoodStats.averageMood([
        entry('2026-06-01', 2),
        entry('2026-06-02', 4),
      ]);
      expect(avg, closeTo(3.0, 0.001));
    });
  });
}
