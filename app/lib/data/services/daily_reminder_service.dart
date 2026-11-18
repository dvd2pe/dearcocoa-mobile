import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// DearCocoa daily writing reminder (diaryvault-style feature ported onto the
/// memex base). One local notification per day at the chosen time.
class DailyReminderService {
  DailyReminderService._();
  static final DailyReminderService instance = DailyReminderService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _androidChannel = AndroidNotificationChannel(
    'dearcocoa_daily_reminder',
    'Daily reminder',
    description: 'A gentle nudge to write a few lines.',
    importance: Importance.defaultImportance,
  );
  static const _notificationId = 42;
  bool _initialized = false;

  static const enabledKey = 'reminder_enabled';
  static const hourKey = 'reminder_hour';
  static const minuteKey = 'reminder_minute';

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
    _initialized = true;
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? false;
  }

  Future<({int hour, int minute})> scheduledTime() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      hour: prefs.getInt(hourKey) ?? 20,
      minute: prefs.getInt(minuteKey) ?? 0,
    );
  }

  /// Enable (or re-schedule) / disable the daily reminder.
  Future<void> setEnabled({
    required bool enabled,
    int? hour,
    int? minute,
  }) async {
    await _ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    if (hour != null) await prefs.setInt(hourKey, hour);
    if (minute != null) await prefs.setInt(minuteKey, minute);
    await prefs.setBool(enabledKey, enabled);

    if (!enabled) {
      await _plugin.cancel(id: _notificationId);
      return;
    }

    final time = await scheduledTime();
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (when.isBefore(now)) {
      when = when.add(const Duration(days: 1));
    }
    try {
      await _plugin.zonedSchedule(
        id: _notificationId,
        title: 'DearCocoa',
        body: 'A few gentle lines are waiting for you.',
        scheduledDate: when,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        matchDateTimeComponents: DateTimeComponents.time,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Reminder scheduling failed: $e');
      rethrow;
    }
  }
}
