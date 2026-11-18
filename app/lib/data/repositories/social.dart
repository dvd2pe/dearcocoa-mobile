import 'package:collection/collection.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show RealtimeChannel, PostgresChangeEvent;

import 'package:dearcocoa/data/services/supabase_service.dart';
import 'package:dearcocoa/domain/models/social_models.dart';

/// Supabase-backed social repository: community feed, groups chat, events.
/// Functions are top-level (memex repository pattern) and throw on network
/// errors so callers can surface friendly toasts.
String? _uid() => SupabaseService.instance.currentUserId;

Future<List<CommunityPost>> fetchCommunityFeed({int limit = 50}) async {
  final uid = _uid();
  final rows = await SupabaseService.instance.client
      .from('space_posts')
      .select('''
        id, user_id, content, created_at, like_count,
        author_name:profiles!space_posts_user_id_fkey(username),
        comments:post_comments(count),
        likes:post_likes(user_id)
      ''')
      .order('created_at', ascending: false)
      .limit(limit);
  return [
    for (final r in rows)
      CommunityPost(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        authorName: _authorName(r),
        content: r['content'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        likeCount: (r['like_count'] as int?) ?? 0,
        commentCount: _commentCount(r),
        likedByMe: _likedByMe(r, uid),
      ),
  ];
}

String _authorName(Map<String, dynamic> row) {
  try {
    final nested = row['author_name'];
    if (nested is Map && nested['username'] != null) {
      return nested['username'] as String;
    }
    if (nested is String && nested.isNotEmpty) return nested;
  } catch (_) {}
  return 'Cocoa friend';
}

int _commentCount(Map<String, dynamic> row) {
  try {
    final comments = row['comments'];
    if (comments is List && comments.isNotEmpty) {
      final m = comments.first as Map;
      return (m['count'] as int?) ?? 0;
    }
  } catch (_) {}
  return 0;
}

bool _likedByMe(Map<String, dynamic> row, String? uid) {
  try {
    final likes = row['likes'];
    if (likes is List && uid != null) {
      return likes.any((l) => (l as Map)['user_id'] == uid);
    }
  } catch (_) {}
  return false;
}

Future<void> togglePostLike(String postId, {required bool liked}) async {
  final uid = _uid();
  if (uid == null) return;
  if (liked) {
    await SupabaseService.instance.client
        .from('post_likes')
        .delete()
        .match({'post_id': postId, 'user_id': uid});
  } else {
    await SupabaseService.instance.client
        .from('post_likes')
        .insert({'post_id': postId, 'user_id': uid});
  }
}

/// Display name from a profile row, with sensible fallbacks.
String _displayName(Map<String, dynamic>? profile) {
  final dn = profile?['display_name'] as String?;
  if (dn != null && dn.isNotEmpty) return dn;
  final un = profile?['username'] as String?;
  if (un != null && un.isNotEmpty) return un;
  return 'Cocoa friend';
}

Future<void> createPost(String content) async {
  final uid = _uid();
  if (uid == null) return;
  await SupabaseService.instance.client
      .from('space_posts')
      .insert({'user_id': uid, 'content': content});
}

Future<List<CommunityComment>> fetchPostComments(String postId) async {
  final rows = await SupabaseService.instance.client
      .from('post_comments')
      .select('id, content, author_name, created_at')
      .eq('post_id', postId)
      .order('created_at', ascending: true)
      .limit(100);
  return [
    for (final r in rows)
      CommunityComment(
        id: r['id'] as String,
        authorName:
            (r['author_name'] as String?)?.isNotEmpty == true
                ? r['author_name'] as String
                : 'Cocoa friend',
        content: r['content'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
      ),
  ];
}

Future<void> addPostComment(String postId, String content) async {
  final uid = _uid();
  if (uid == null) return;
  final profile = await SupabaseService.instance.fetchOwnProfile();
  await SupabaseService.instance.client.from('post_comments').insert({
    'post_id': postId,
    'user_id': uid,
    'content': content,
    'author_name': _displayName(profile),
  });
}

// ---------------------------------------------------------------- groups

Future<List<GroupInfo>> fetchGroups() async {
  final uid = _uid();
  final rows = await SupabaseService.instance.client
      .from('groups')
      .select('''
        id, name, description,
        memberships:group_members(user_id),
        messages:group_messages(created_at)
      ''')
      .order('created_at', ascending: true)
      .limit(50);
  return [
    for (final r in rows)
      GroupInfo(
        id: r['id'] as String,
        name: r['name'] as String,
        description: r['description'] as String? ?? '',
        isMember: uid != null &&
            (r['memberships'] as List? ?? []).any(
                (m) => (m as Map)['user_id'] == uid),
        messageCount: (r['messages'] as List? ?? []).length,
        lastMessageAt: (r['messages'] as List? ?? [])
            .map<DateTime?>((m) =>
                DateTime.tryParse((m as Map)['created_at'] as String? ?? ''))
            .whereType<DateTime>()
            .fold<DateTime?>(null,
                (a, b) => (a == null || b.isAfter(a)) ? b : a),
      ),
  ];
}

Future<void> joinGroup(String groupId, {required bool join}) async {
  final uid = _uid();
  if (uid == null) return;
  if (join) {
    await SupabaseService.instance.client
        .from('group_members')
        .insert({'group_id': groupId, 'user_id': uid, 'role': 'member'});
  } else {
    await SupabaseService.instance.client
        .from('group_members')
        .delete()
        .match({'group_id': groupId, 'user_id': uid});
  }
}

Future<List<GroupMessage>> fetchGroupMessages(String groupId,
    {int limit = 100}) async {
  final rows = await SupabaseService.instance.client
      .from('group_messages')
      .select('id, user_id, content, author_name, created_at')
      .eq('group_id', groupId)
      .order('created_at', ascending: true)
      .range(0, limit - 1);
  return [
    for (final r in rows)
      GroupMessage(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        authorName:
            (r['author_name'] as String?)?.isNotEmpty == true
                ? r['author_name'] as String
                : 'Member',
        content: r['content'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
      ),
  ];
}

Future<void> sendGroupMessage(String groupId, String content) async {
  final uid = _uid();
  if (uid == null) return;
  final profile = await SupabaseService.instance.fetchOwnProfile();
  await SupabaseService.instance.client.from('group_messages').insert({
    'group_id': groupId,
    'user_id': uid,
    'content': content,
    'author_name': _displayName(profile),
  });
}

/// Subscribe to new rows in a table (Supabase Realtime). Returns the channel
/// to cancel on dispose.
RealtimeChannel subscribeTable(
  String table,
  void Function() onChange,
) {
  final channel = SupabaseService.instance.client.channel('dearcocoa-$table');
  channel.onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    table: table,
    callback: (_) => onChange(),
  );
  channel.subscribe();
  return channel;
}

// ---------------------------------------------------------------- events

Future<List<EventItem>> fetchEvents() async {
  final uid = _uid();
  final rows = await SupabaseService.instance.client
      .from('events')
      .select('''
        id, title, description, category, starts_at, ends_at, capacity,
        meeting_url, host:profiles!events_created_by_fkey(username),
        rsvps:event_rsvps(user_id, status),
        program:event_program(title, speaker, description, starts_at, sort)
      ''')
      .gte('starts_at', DateTime.now().toUtc().toIso8601String())
      .order('starts_at', ascending: true)
      .limit(30);
  return [
    for (final r in rows)
      EventItem(
        id: r['id'] as String,
        title: r['title'] as String,
        description: r['description'] as String? ?? '',
        category: r['category'] as String? ?? 'community',
        startsAt: DateTime.parse(r['starts_at'] as String).toLocal(),
        endsAt: r['ends_at'] != null
            ? DateTime.parse(r['ends_at'] as String).toLocal()
            : null,
        capacity: (r['capacity'] as int?) ?? 100,
        rsvpCount: (r['rsvps'] as List? ?? [])
            .where((s) => (s as Map)['status'] == 'going')
            .length,
        myStatus: uid == null
            ? null
            : (r['rsvps'] as List? ?? [])
                .where((s) => (s as Map)['user_id'] == uid)
                .cast<Map>()
                .map<String?>((s) => s['status'] as String?)
                .firstOrNull,
        hostName: _hostName(r),
        meetingUrl: r['meeting_url'] as String?,
        program: [
          for (final p in (r['program'] as List? ?? []))
            EventProgramItem(
              title: (p as Map)['title'] as String,
              speaker: p['speaker'] as String? ?? '',
              description: p['description'] as String? ?? '',
              startsAt:
                  DateTime.parse(p['starts_at'] as String).toLocal(),
            ),
        ],
      ),
  ];
}

String _hostName(Map<String, dynamic> row) {
  try {
    final host = row['host'];
    if (host is Map && host['username'] != null) {
      return host['username'] as String;
    }
    if (host is String && host.isNotEmpty) return host;
  } catch (_) {}
  return 'DearCocoa';
}

Future<void> setRsvp(String eventId, String? status) async {
  final uid = _uid();
  if (uid == null) return;
  if (status == null || status == 'cancelled') {
    await SupabaseService.instance.client
        .from('event_rsvps')
        .delete()
        .match({'event_id': eventId, 'user_id': uid});
  } else {
    await SupabaseService.instance.client.from('event_rsvps').upsert({
      'event_id': eventId,
      'user_id': uid,
      'status': status,
    });
  }
}
