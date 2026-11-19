import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/themes/app_colors.dart';
import '../core/themes/app_shadows.dart';
import '../core/themes/app_text_styles.dart';
import '../../data/repositories/mood_repository.dart';
import '../../data/repositories/mood_stats.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/user_storage.dart';

/// DearCocoa mood tracking: one tap logs today's mood, the chart shows the
/// last 14 days, streaks reward consistency. Data lives locally (drift).
class MoodScreen extends StatefulWidget {
  const MoodScreen({super.key});

  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

/// Localized mood label for 1..5 (shared with the note composer).
String moodLabel(AppLocalizations l10n, int mood) {
  switch (mood) {
    case 1:
      return l10n.moodVeryLow;
    case 2:
      return l10n.moodLow;
    case 3:
      return l10n.moodOkay;
    case 4:
      return l10n.moodGood;
    default:
      return l10n.moodGreat;
  }
}

/// Per-mood color scale (1=very low … 5=great) used by the picker, the
/// composer faces and the 14-day chart so the scoring is always readable.
const moodColors = [
  Color(0xFFEF4444), // very low  — red
  Color(0xFFF97316), // low       — orange
  Color(0xFFEAB308), // okay      — yellow
  Color(0xFF22C55E), // good      — green
  Color(0xFF10B981), // great     — emerald
];

const moodIcons = [
  Icons.sentiment_very_dissatisfied_rounded,
  Icons.sentiment_dissatisfied_rounded,
  Icons.sentiment_neutral_rounded,
  Icons.sentiment_satisfied_rounded,
  Icons.sentiment_very_satisfied_rounded,
];

class _MoodScreenState extends State<MoodScreen> {
  List<Map<String, dynamic>> _rows = [];
  int? _todayMood;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = await UserStorage.getUserId();
    if (userId == null) return;
    final rows = await MoodRepository.instance.getAllMoodRows(userId);
    final today =
        DateTime.now().toIso8601String().substring(0, 10);
    final todayMood = await MoodRepository.instance.getMoodForDay(
        userId: userId, entryDate: today);
    if (mounted) {
      setState(() {
        _rows = rows;
        _todayMood = todayMood;
        _loading = false;
      });
    }
  }

  Future<void> _pickMood(int mood) async {
    final userId = await UserStorage.getUserId();
    if (userId == null) return;
    await MoodRepository.instance.setMoodForDay(
      userId: userId,
      entryDate: DateTime.now().toIso8601String().substring(0, 10),
      mood: mood,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final now = DateTime.now();
    final streak = MoodStats.currentStreak(_rows, now);
    final longest = MoodStats.longestStreak(_rows);
    final average = MoodStats.averageMood(_rows);
    final days = MoodStats.lastDays(_rows, now, 14);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.moodTitle,
          style: AppTextStyles.cardListTitle.copyWith(fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF64748B), size: 20),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  _TodayPicker(mood: _todayMood, onPick: _pickMood),
                  const SizedBox(height: 20),
                  _MoodChart(days: days),
                  const SizedBox(height: 16),
                  _StreakRow(
                    streak: streak,
                    longest: longest,
                    average: average,
                  ),
                ],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------- widgets

class _TodayPicker extends StatelessWidget {
  const _TodayPicker({required this.mood, required this.onPick});

  final int? mood;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.moodTodayTitle,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            mood == null
                ? l10n.moodTodayHint
                : l10n.moodLoggedAs(moodLabel(l10n, mood!)),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 1; i <= 5; i++)
                GestureDetector(
                  onTap: () => onPick(i),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: mood == i
                          ? moodColors[i - 1]
                          : moodColors[i - 1].withValues(alpha: 0.12),
                      border: mood == i
                          ? Border.all(color: moodColors[i - 1], width: 2)
                          : null,
                    ),
                    child: Icon(
                      moodIcons[i - 1],
                      size: 28,
                      color: mood == i ? Colors.white : moodColors[i - 1],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 1; i <= 5; i++)
                Expanded(
                  child: Text(
                    moodLabel(l10n, i),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          mood == i ? FontWeight.w600 : FontWeight.w400,
                      color: mood == i
                          ? moodColors[i - 1]
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoodChart extends StatelessWidget {
  const _MoodChart({required this.days});

  final List<({DateTime day, int? mood})> days;

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.moodLast14Days,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.moodChartHint,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 5,
                minY: 0,
                barTouchData: BarTouchData(enabled: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: const Color(0xFFEEF2F7),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 44,
                      getTitlesWidget: (value, meta) {
                        final mood = value.toInt();
                        if (mood < 1 || mood > 5) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(moodIcons[mood - 1],
                                  size: 12, color: moodColors[mood - 1]),
                              const SizedBox(width: 3),
                              Text(
                                '$mood',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: moodColors[mood - 1],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= days.length) {
                          return const SizedBox.shrink();
                        }
                        final day = days[index].day;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${day.day}',
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < days.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: days[i].mood?.toDouble() ?? 0,
                          width: 10,
                          borderRadius: BorderRadius.circular(5),
                          color: days[i].mood == null
                              ? AppColors.iconBgLight
                              : moodColors[days[i].mood! - 1],
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Scoring legend: color → label, so every bar is readable.
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              for (var i = 1; i <= 5; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: moodColors[i - 1],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      moodLabel(l10n, i),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({
    required this.streak,
    required this.longest,
    required this.average,
  });

  final int streak;
  final int longest;
  final double? average;

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
              label: l10n.moodCurrentStreak,
              value: '$streak',
              unit: l10n.moodDays),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
              label: l10n.moodLongestStreak,
              value: '$longest',
              unit: l10n.moodDays),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: l10n.moodAverageMood,
            value: average == null
                ? '—'
                : average!.toStringAsFixed(1),
            unit: l10n.moodOf5,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextSpan(
                  text: '  $unit',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
