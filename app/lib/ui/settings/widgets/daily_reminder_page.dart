import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/themes/app_colors.dart';
import '../../core/themes/app_shadows.dart';
import '../../../data/services/daily_reminder_service.dart';
import '../../../utils/toast_helper.dart';

/// Daily reminder settings (diaryvault-style): toggle + time picker.
class DailyReminderPage extends StatefulWidget {
  const DailyReminderPage({super.key});

  @override
  State<DailyReminderPage> createState() => _DailyReminderPageState();
}

class _DailyReminderPageState extends State<DailyReminderPage> {
  bool _enabled = false;
  ({int hour, int minute}) _time = (hour: 20, minute: 0);
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await DailyReminderService.instance.isEnabled();
    final time = await DailyReminderService.instance.scheduledTime();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _time = time;
        _loading = false;
      });
    }
  }

  Future<void> _apply({bool? enabled, ({int hour, int minute})? time}) async {
    setState(() => _busy = true);
    try {
      if (enabled == true) {
        final granted =
            await PermissionGate.requestNotifications();
        if (!granted) {
          if (mounted) {
            setState(() => _busy = false);
            ToastHelper.showError(
                context, 'Notification permission denied in system settings.');
          }
          return;
        }
      }
      await DailyReminderService.instance.setEnabled(
        enabled: enabled ?? _enabled,
        hour: time?.hour,
        minute: time?.minute,
      );
      if (mounted) {
        setState(() {
          if (enabled != null) _enabled = enabled;
          if (time != null) _time = time;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ToastHelper.showError(context, e);
      }
    }
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Daily reminder',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF64748B), size: 20),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [AppShadows.card],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Remind me to write',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'One gentle local notification a day.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : Switch(
                              value: _enabled,
                              activeColor: AppColors.primary,
                              onChanged: (v) => _apply(enabled: v),
                            ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _enabled && !_busy ? _pickTime : null,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [AppShadows.card],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.iconBgLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.alarm_rounded,
                              size: 22, color: AppColors.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: const Text(
                            'Reminder time',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          '${_two(_time.hour)}:${_two(_time.minute)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Reminders are scheduled on-device (no server involved) and keep working offline.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _time.hour, minute: _time.minute),
    );
    if (picked != null) {
      await _apply(time: (hour: picked.hour, minute: picked.minute));
    }
  }
}

/// Thin wrapper so the page stays testable without the permission plugin.
class PermissionGate {
  const PermissionGate._();

  static Future<bool> requestNotifications() async {
    final status = await Permission.notification.request();
    return status.isGranted || status.isProvisional;
  }
}
