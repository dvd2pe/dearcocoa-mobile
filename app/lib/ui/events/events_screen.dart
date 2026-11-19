import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:intl/intl.dart';

import '../core/themes/app_colors.dart';
import '../core/themes/app_shadows.dart';
import '../core/themes/app_text_styles.dart';
import '../../data/repositories/social.dart';
import '../../data/services/supabase_service.dart';
import '../../domain/models/social_models.dart';
import '../community/social_debug_sheet.dart';
import '../user_setup/widgets/demo_login_screen.dart';

/// DearCocoa Events: upcoming virtual events with RSVP, rendered with the
/// event-card language (radius 24 card, date block, program list).
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  bool _loading = true;
  String? _error;
  Object? _lastError;
  List<EventItem> _events = [];
  RealtimeChannel? _rsvpChannel;

  @override
  void initState() {
    super.initState();
    _load();
    _rsvpChannel = subscribeTable('event_rsvps', () => _load());
  }

  @override
  void dispose() {
    try {
      _rsvpChannel?.unsubscribe();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final events = await fetchEvents();
      if (mounted) {
        setState(() {
          _events = events;
          _loading = false;
          _error = null;
          _lastError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load events: check your connection.';
          _lastError = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // DearCocoa: RSVP and attendance are per-user (RLS). Without a session,
    // show the one-tap demo picker instead of a network error.
    if (!SupabaseService.instance.isSignedIn) {
      return DemoLoginScreen(
        onSignedIn: () {
          setState(() {});
          _load();
        },
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text('Events', style: AppTextStyles.brandTitle()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Live sessions and circles you can join from anywhere.',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
            TextButton(
              onPressed: () => showSocialDebugSheet(
                context,
                area: 'Events',
                error: _lastError,
              ),
              child: const Text('Diagnostica'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 220),
        cacheExtent: 400,
        itemCount: _events.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _EventCard(
            event: _events[index],
            onOpen: () => _openDetail(_events[index]),
            onRsvp: () => _setRsvp(
              _events[index],
              _events[index].isGoing ? 'cancelled' : 'going',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(EventItem event) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => _EventDetailSheet(event: event),
    );
    _load();
  }

  Future<void> _setRsvp(EventItem event, String status) async {
    try {
      await setRsvp(event.id, status == 'cancelled' ? null : status);
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('RSVP failed: try again')),
        );
      }
    }
  }
}

// ---------------------------------------------------------------- widgets

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onOpen, required this.onRsvp});

  final EventItem event;
  final VoidCallback onOpen;
  final VoidCallback onRsvp;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [AppShadows.eventCard],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DateBlock(event.startsAt),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CategoryChip(category: event.category),
                      const SizedBox(height: 8),
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hosted by ${event.hostName}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 14, color: AppColors.textTertiary),
                          const SizedBox(width: 4),
                          Text(
                            '${_time(event.startsAt)} · virtual',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${event.rsvpCount}/${event.capacity} joined',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _RsvpButton(event: event, onTap: onRsvp),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Event date block: 47×50 rounded 12, primary at 12% alpha — memex/event-card
/// pattern from the approved repos.
class _DateBlock extends StatelessWidget {
  const _DateBlock(this.date);

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 47,
      height: 50,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('MMM').format(date).toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
              color: AppColors.primary,
            ),
          ),
          Text(
            date.day.toString(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.iconBgLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        category[0].toUpperCase() + category.substring(1),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _RsvpButton extends StatelessWidget {
  const _RsvpButton({required this.event, required this.onTap});

  final EventItem event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final going = event.isGoing;
    final disabled = !going && event.isFull;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: going ? AppColors.iconBgLight : AppColors.primary,
        foregroundColor: going ? AppColors.primary : Colors.white,
        disabledBackgroundColor: AppColors.iconBgLight,
        disabledForegroundColor: AppColors.textTertiary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: disabled ? null : onTap,
      child: Text(
        disabled ? 'Full' : (going ? 'Going ✓' : 'Join'),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EventDetailSheet extends StatelessWidget {
  const _EventDetailSheet({required this.event});

  final EventItem event;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _DateBlock(event.startsAt),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              event.description,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _InfoRow(
              icon: Icons.access_time_rounded,
              label: DateFormat('EEE d MMM, HH:mm').format(event.startsAt),
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.videocam_rounded,
              label: 'Virtual · ${event.rsvpCount}/${event.capacity} joined',
            ),
            if (event.meetingUrl != null) ...[
              const SizedBox(height: 8),
              _InfoRow(icon: Icons.link_rounded, label: event.meetingUrl!),
            ],
            const SizedBox(height: 20),
            if (event.program.isNotEmpty) ...[
              const Text(
                'Program',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < event.program.length; i++)
                _ProgramTile(item: event.program[i]),
              const SizedBox(height: 20),
            ],
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    event.isGoing ? AppColors.iconBgLight : AppColors.primary,
                foregroundColor:
                    event.isGoing ? AppColors.danger : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                event.isGoing
                    ? 'You are going — manage in the list'
                    : (event.isFull ? 'Event full' : 'Join this event'),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgramTile extends StatelessWidget {
  const _ProgramTile({required this.item});

  final EventProgramItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
              ),
              Container(
                width: 1.5,
                height: 26,
                color: AppColors.primary.withValues(alpha: 0.25),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${DateFormat('HH:mm').format(item.startsAt)} — ${item.title}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (item.speaker.isNotEmpty)
                  Text(
                    item.speaker,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                  ),
                if (item.description.isNotEmpty)
                  Text(
                    item.description,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textSecondary,
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

String _time(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
