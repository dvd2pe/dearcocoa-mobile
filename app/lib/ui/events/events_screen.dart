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
import '../core/widgets/local_image.dart';
import '../user_setup/widgets/demo_login_screen.dart';

/// DearCocoa Events: rich event cards (cover image, participant circles,
/// per-category colors, in-person + virtual) with working RSVP.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

/// Category accent colors (DearCocoa palette).
const _kCategoryColors = <String, Color>{
  'wellness': Color(0xFF10B981),
  'workshop': Color(0xFF5B6CFF),
  'community': Color(0xFFEC4899),
  'meditation': Color(0xFF8B5CF6),
  'social': Color(0xFFF59E0B),
};

Color _categoryColor(String category) =>
    _kCategoryColors[category] ?? const Color(0xFF5B6CFF);

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
                'Live sessions, circles and meetups — online or in person.',
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
            onRsvp: (status) => _setRsvp(_events[index], status),
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
      builder: (_) => _EventDetailSheet(
        event: event,
        onRsvp: (status) => _setRsvp(event, status),
      ),
    );
    _load();
  }

  Future<void> _setRsvp(EventItem event, String? status) async {
    try {
      await setRsvp(event.id, status);
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

/// Avatar circle with initials (shared by event cards and detail sheet).
class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({required this.name, this.size = 26});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// Overlapping participant circles + "+N" and a "N going" caption.
class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.event});

  final EventItem event;

  @override
  Widget build(BuildContext context) {
    final names = event.goingNames.take(3).toList();
    final extra = event.rsvpCount - names.length;
    return Row(
      children: [
        SizedBox(
          width: names.isEmpty ? 0 : (names.length * 18.0 + 8),
          child: Stack(
            children: [
              for (var i = 0; i < names.length; i++)
                Positioned(
                  left: i * 18.0,
                  child: _AvatarCircle(name: names[i]),
                ),
            ],
          ),
        ),
        if (extra > 0) ...[
          Transform.translate(
            offset: const Offset(-4, 0),
            child: _AvatarCircle(name: '+$extra', size: 26),
          ),
        ] else if (names.isNotEmpty)
          const SizedBox(width: 6),
        Text(
          '${event.rsvpCount}/${event.capacity} going',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Colored category chip.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, this.solid = false});

  final String category;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        category[0].toUpperCase() + category.substring(1),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: solid ? Colors.white : color,
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onOpen, required this.onRsvp});

  final EventItem event;
  final VoidCallback onOpen;
  final void Function(String? status) onRsvp;

  @override
  Widget build(BuildContext context) {
    final accent = _categoryColor(event.category);
    final going = event.isGoing;
    final maybe = event.isMaybe;
    final disabled = !going && !maybe && event.isFull;

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [AppShadows.eventCard],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Cover image (top) with category + date overlay
            Stack(
              children: [
                if (event.coverUrl != null)
                  SizedBox(
                    height: 132,
                    width: double.infinity,
                    child: LocalImage(
                      url: event.coverUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _coverFallback(accent),
                    ),
                  )
                else
                  _coverFallback(accent),
                Positioned(
                  top: 10,
                  left: 12,
                  child: _CategoryChip(category: event.category, solid: true),
                ),
                Positioned(
                  bottom: 10,
                  left: 12,
                  child: _DateBlock(event.startsAt, onImage: event.coverUrl != null),
                ),
              ],
            ),
            // --- Body
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        event.isVirtual
                            ? Icons.videocam_rounded
                            : Icons.place_rounded,
                        size: 14,
                        color: accent,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.isVirtual
                              ? '${_time(event.startsAt)} · Virtual'
                              : '${_time(event.startsAt)} · ${event.location ?? 'In person'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _ParticipantRow(event: event),
                  const SizedBox(height: 12),
                  // --- RSVP buttons (working)
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                going ? accent.withValues(alpha: 0.12) : accent,
                            foregroundColor: going ? accent : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: disabled
                              ? null
                              : () => onRsvp(going ? null : 'going'),
                          icon: Icon(
                            going ? Icons.check_rounded : Icons.add_rounded,
                            size: 18,
                          ),
                          label: Text(
                            disabled
                                ? 'Full'
                                : (going ? 'Going' : 'Join'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                maybe ? _kCategoryColors['social']! : AppColors.textSecondary,
                            side: BorderSide(
                              color: maybe
                                  ? _kCategoryColors['social']!
                                  : AppColors.textTertiary.withValues(alpha: 0.4),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () =>
                              onRsvp(maybe ? null : 'interested'),
                          icon: Icon(
                            maybe
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'Maybe',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverFallback(Color accent) {
    return Container(
      height: 76,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.85), accent],
        ),
      ),
    );
  }
}

/// Event date block: rounded square with month + day.
class _DateBlock extends StatelessWidget {
  const _DateBlock(this.date, {this.onImage = false});

  final DateTime date;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final bg = onImage ? Colors.white : AppColors.primary.withValues(alpha: 0.12);
    final fg = onImage ? AppColors.primary : AppColors.primary;
    return Container(
      width: 47,
      height: 50,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: onImage
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('MMM').format(date).toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
              color: fg,
            ),
          ),
          Text(
            date.day.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventDetailSheet extends StatelessWidget {
  const _EventDetailSheet({required this.event, required this.onRsvp});

  final EventItem event;
  final void Function(String? status) onRsvp;

  @override
  Widget build(BuildContext context) {
    final accent = _categoryColor(event.category);
    final going = event.isGoing;
    final maybe = event.isMaybe;
    final disabled = !going && !maybe && event.isFull;
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
            // Cover
            if (event.coverUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: LocalImage(
                    url: event.coverUrl!,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: accent),
                  ),
                ),
              ),
            if (event.coverUrl != null) const SizedBox(height: 16),
            Row(
              children: [
                _DateBlock(event.startsAt),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CategoryChip(category: event.category),
                      const SizedBox(height: 6),
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
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
              icon: event.isVirtual
                  ? Icons.videocam_rounded
                  : Icons.place_rounded,
              label: event.isVirtual
                  ? 'Virtual · ${event.rsvpCount}/${event.capacity} joined'
                  : '${event.location ?? 'In person'} · ${event.rsvpCount}/${event.capacity} joined',
            ),
            if (event.isVirtual && event.meetingUrl != null) ...[
              const SizedBox(height: 8),
              _InfoRow(icon: Icons.link_rounded, label: event.meetingUrl!),
            ],
            const SizedBox(height: 14),
            if (event.goingNames.isNotEmpty) ...[
              const Text(
                'Who is going',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final name in event.goingNames)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _AvatarCircle(name: name, size: 38),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 52,
                          child: Text(
                            name.split(' ').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
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
              const SizedBox(height: 16),
            ],
            // --- Working RSVP actions
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          going ? accent.withValues(alpha: 0.12) : accent,
                      foregroundColor: going ? accent : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: disabled
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            onRsvp(going ? null : 'going');
                          },
                    child: Text(
                      disabled
                          ? 'Event full'
                          : (going
                              ? "You're going — tap to cancel"
                              : 'Join this event'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          maybe ? _kCategoryColors['social']! : AppColors.textSecondary,
                      side: BorderSide(
                        color: maybe
                            ? _kCategoryColors['social']!
                            : AppColors.textTertiary.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      onRsvp(maybe ? null : 'interested');
                    },
                    child: Text(
                      maybe ? 'Maybe — cancel' : 'Maybe',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
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
