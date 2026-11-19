import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/themes/app_colors.dart';
import '../core/themes/app_shadows.dart';
import '../core/themes/app_text_styles.dart';
import '../../data/repositories/social.dart';
import '../../data/services/supabase_service.dart';
import '../../domain/models/social_models.dart';
import '../user_setup/widgets/demo_login_screen.dart';

import 'community_sheets.dart';
import 'social_debug_sheet.dart';
import 'groups_chat_screen.dart';

/// DearCocoa Community: spaces feed + group conversations, rendered with the
/// memex design system (white cards, radius 16, AppShadows.card, Inter body).
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  bool _showFeed = true;
  bool _loading = true;
  String? _error;
  Object? _lastError;
  List<CommunityPost> _posts = [];
  List<GroupInfo> _groups = [];
  RealtimeChannel? _postChannel;
  RealtimeChannel? _messageChannel;

  @override
  void initState() {
    super.initState();
    _load();
    _postChannel = subscribeTable('space_posts', () => _load());
    _messageChannel = subscribeTable('group_messages', () => _load());
  }

  @override
  void dispose() {
    try {
      _postChannel?.unsubscribe();
      _messageChannel?.unsubscribe();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final posts = await fetchCommunityFeed();
      final groups = await fetchGroups();
      if (mounted) {
        setState(() {
          _posts = posts;
          _groups = groups;
          _loading = false;
          _error = null;
          _lastError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not reach the community: check your connection.';
          _lastError = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // DearCocoa: the social layer requires a Supabase session (RLS protects
    // every table). Without one, show the one-tap demo account picker instead
    // of a misleading "could not reach" network error.
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
            _buildHeader(),
            _buildSegmented(),
            Expanded(child: _showFeed ? _buildFeed() : _buildGroups()),
          ],
        ),
      ),
      floatingActionButton: _showFeed ? _buildComposeFab() : null,
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Text('Community', style: AppTextStyles.brandTitle()),
    );
  }

  Widget _buildSegmented() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Container(
        height: 36,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [AppShadows.card],
        ),
        child: Row(
          children: [
            _SegmentButton(
              label: 'Spaces',
              selected: _showFeed,
              onTap: () => setState(() => _showFeed = true),
            ),
            _SegmentButton(
              label: 'Groups',
              selected: !_showFeed,
              onTap: () => setState(() => _showFeed = false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposeFab() {
    return FloatingActionButton.extended(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      onPressed: () async {
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          isScrollControlled: true,
          builder: (_) => const CreatePostSheet(),
        );
        _load();
      },
      label: const Text('Share'),
      icon: const Icon(Icons.edit_note_rounded, size: 20),
    );
  }

  Widget _buildFeed() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load, lastError: _lastError);
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 220),
        cacheExtent: 400,
        itemCount: _posts.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _PostCard(
            post: _posts[index],
            onLike: () async {
              final post = _posts[index];
              await togglePostLike(post.id, liked: post.likedByMe);
              _load();
            },
            onComment: () async {
              await showModalBottomSheet<void>(
                context: context,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                isScrollControlled: true,
                builder: (_) => CommentsSheet(post: _posts[index]),
              );
              _load();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGroups() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load, lastError: _lastError);
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 220),
        itemCount: _groups.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _GroupCard(
            group: _groups[index],
            onOpen: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupChatScreen(group: _groups[index]),
                ),
              );
              _load();
            },
            onJoinToggle: () async {
              await joinGroup(_groups[index].id,
                  join: !_groups[index].isMember);
              _load();
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- widgets

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.tagActiveBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : AppColors.textSecondary,
              letterSpacing: -0.15,
            ),
          ),
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.onLike, required this.onComment});

  final CommunityPost post;
  final VoidCallback onLike;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AvatarBubble(name: post.authorName, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      _relativeTime(post.createdAt),
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
          const SizedBox(height: 12),
          Text(
            post.content,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _ActionChip(
                icon: post.likedByMe
                    ? Icons.favorite_rounded
                    : Icons.favorite_outline_rounded,
                label: '${post.likeCount}',
                color: post.likedByMe ? AppColors.danger : AppColors.textSecondary,
                onTap: onLike,
              ),
              const SizedBox(width: 8),
              _ActionChip(
                icon: Icons.chat_bubble_outline_rounded,
                label: '${post.commentCount}',
                color: AppColors.textSecondary,
                onTap: onComment,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.onOpen,
    required this.onJoinToggle,
  });

  final GroupInfo group;
  final VoidCallback onOpen;
  final VoidCallback onJoinToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.iconBgLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.forum_outlined,
                  size: 22,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${group.messageCount} messages',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              group.isMember
                  ? OutlinedButton(
                      onPressed: onOpen,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Open'),
                    )
                  : FilledButton(
                      onPressed: onJoinToggle,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Join'),
                    ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            group.description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.iconBgLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  const _AvatarBubble({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.avatarGradient,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    this.lastError,
  });

  final String message;
  final VoidCallback onRetry;
  final Object? lastError;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
            TextButton(
              onPressed: () => showSocialDebugSheet(
                context,
                area: 'Community',
                error: lastError,
              ),
              child: const Text('Diagnostica'),
            ),
          ],
        ),
      ),
    );
  }
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('d MMM').format(time);
}
