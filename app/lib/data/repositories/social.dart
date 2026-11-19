import 'dart:io';

import 'package:collection/collection.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show RealtimeChannel, PostgresChangeEvent;

import 'package:dearcocoa/data/services/supabase_service.dart';
import 'package:dearcocoa/domain/models/social_models.dart';

/// Supabase-backed social repository: community feed, groups chat, events.
/// Functions are top-level (memex repository pattern) and throw on network
/// errors so callers can surface friendly toasts.
String? _uid() => SupabaseService.instance.currentUserId;

/// Best display name from a profile row: display_name, else username, else
/// [fallback]. Pure function so the mapping is unit-testable.
String bestProfileName({String? display, String? username, String fallback = 'Cocoa friend'}) {
  if (display != null && display.isNotEmpty) return display;
  if (username != null && username.isNotEmpty) return username;
  return fallback;
}

/// Split a stored media reference into its parts.
///
/// Accepted forms:
///  - `https://...` / `http://...`  -> passthrough (seeded demo media)
///  - `bucket/path/file.jpg`        -> (bucket, path)
/// Returns (url, null) for passthrough, (null, (bucket, path)) for storage
/// refs, (null, null) for empty/invalid input. Pure, so it is unit-testable.
(String?, (String, String)?) splitMediaRef(String? ref) {
  if (ref == null) return (null, null);
  final trimmed = ref.trim();
  if (trimmed.isEmpty) return (null, null);
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return (trimmed, null);
  }
  final slash = trimmed.indexOf('/');
  if (slash <= 0 || slash == trimmed.length - 1) return (null, null);
  return (
    null,
    (trimmed.substring(0, slash), trimmed.substring(slash + 1)),
  );
}

/// Resolve a stored media reference to a fetchable URL (see [splitMediaRef]).
String? resolveMediaUrl(String? ref) {
  final (passthrough, storageRef) = splitMediaRef(ref);
  if (passthrough != null) return passthrough;
  if (storageRef == null) return null;
  final (bucket, path) = storageRef;
  try {
    return SupabaseService.instance.client.storage
        .from(bucket)
        .getPublicUrl(path);
  } catch (_) {
    return null;
  }
}

/// Bulk-fetch display names for user ids (client-side join).
///
/// The profiles lookup is deliberately decoupled from the feed/event queries:
/// PostgREST can only resolve `profiles` embeds when the FK references
/// public.profiles, and we never want a profile lookup issue to break the
/// whole feed. Returns uid -> display name; empty map on any error.
Future<Map<String, String>> fetchProfileNames(Iterable<String> uids) async {
  final ids = uids.where((u) => u.isNotEmpty).toSet();
  if (ids.isEmpty) return {};
  try {
    final rows = await SupabaseService.instance.client
        .from('profiles')
        .select('id, username, display_name')
        .inFilter('id', ids.toList());
    final out = <String, String>{};
    for (final r in rows) {
      out[r['id'] as String] = bestProfileName(
        display: r['display_name'] as String?,
        username: r['username'] as String?,
      );
    }
    return out;
  } catch (_) {
    return {};
  }
}

/// Map a space_posts row (without the profiles embed) to CommunityPost.
CommunityPost communityPostFromRow(
  Map<String, dynamic> r,
  Map<String, String> profileNames,
  String? uid,
) {
  final userId = r['user_id'] as String;
  return CommunityPost(
    id: r['id'] as String,
    userId: userId,
    authorName: profileNames[userId] ?? 'Cocoa friend',
    content: r['content'] as String,
    createdAt: DateTime.parse(r['created_at'] as String),
    likeCount: (r['like_count'] as int?) ?? 0,
    commentCount: _commentCount(r),
    likedByMe: _likedByMe(r, uid),
    mediaUrls: _postMediaUrls(r),
  );
}

List<String> _postMediaUrls(Map<String, dynamic> row) {
  try {
    final paths = row['media_paths'];
    if (paths is List) {
      return [
        for (final p in paths)
          if (p is String && resolveMediaUrl(p) != null) resolveMediaUrl(p)!,
      ];
    }
  } catch (_) {}
  return const <String>[];
}

Future<List<CommunityPost>> fetchCommunityFeed({int limit = 50}) async {
  final uid = _uid();
  final rows = await SupabaseService.instance.client
      .from('space_posts')
      .select('''
        id, user_id, content, created_at, like_count, media_paths,
        comments:post_comments(count),
        likes:post_likes(user_id)
      ''')
      .order('created_at', ascending: false)
      .limit(limit);
  final names = await fetchProfileNames(
      rows.map<String>((r) => r['user_id'] as String));
  return [
    for (final r in rows) communityPostFromRow(r, names, uid),
  ];
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

/// Fetch a member profile with activity counts (profile sheet).
/// Returns null when the profile cannot be loaded.
Future<MemberProfile?> fetchMemberProfile(String userId) async {
  try {
    final rows = await SupabaseService.instance.client
        .from('profiles')
        .select('id, username, display_name, bio, avatar_path, created_at')
        .eq('id', userId)
        .limit(1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final postRows = await SupabaseService.instance.client
        .from('space_posts')
        .select('id')
        .eq('user_id', userId);
    return MemberProfile(
      userId: r['id'] as String,
      username: r['username'] as String? ?? '',
      displayName: _displayName(r),
      bio: r['bio'] as String? ?? '',
      avatarUrl: resolveMediaUrl(r['avatar_path'] as String?),
      joinedAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
      postCount: postRows.length,
    );
  } catch (_) {
    return null;
  }
}

Future<void> createPost(String content, {List<String>? mediaPaths}) async {
  final uid = _uid();
  if (uid == null) return;
  await SupabaseService.instance.client
      .from('space_posts')
      .insert({
        'user_id': uid,
        'content': content,
        if (mediaPaths != null && mediaPaths.isNotEmpty)
          'media_paths': mediaPaths,
      });
}

/// Upload picked images to the public post-media bucket and return the
/// `bucket/path` references to store in space_posts.media_paths.
Future<List<String>> uploadPostMedia(List<String> localPaths) async {
  final uid = _uid();
  if (uid == null) return const [];
  final storage = SupabaseService.instance.client.storage;
  final uploaded = <String>[];
  for (var i = 0; i < localPaths.length; i++) {
    try {
      final file = File(localPaths[i]);
      if (!file.existsSync()) continue;
      final ext = localPaths[i].split('.').last.toLowerCase().replaceAll(
          RegExp('[^a-z0-9]'), '');
      final name =
          'posts/$uid/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
      await storage.from('post-media').upload(name, file);
      uploaded.add('post-media/$name');
    } catch (_) {
      // One failed image must not block the whole post.
    }
  }
  return uploaded;
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

/// Map an events row (without the profiles embed) to EventItem.
EventItem eventItemFromRow(
  Map<String, dynamic> r,
  Map<String, String> profileNames,
  String? uid,
) {
  final createdBy = r['created_by'] as String;
  final rsvps = (r['rsvps'] as List? ?? []);
  final goingNames = <String>[];
  for (final s in rsvps) {
    final m = s as Map;
    if (m['status'] != 'going') continue;
    final name = profileNames[m['user_id'] as String? ?? ''];
    if (name != null && name.isNotEmpty) goingNames.add(name);
  }
  return EventItem(
    id: r['id'] as String,
    title: r['title'] as String,
    description: r['description'] as String? ?? '',
    category: r['category'] as String? ?? 'community',
    startsAt: DateTime.parse(r['starts_at'] as String).toLocal(),
    endsAt: r['ends_at'] != null
        ? DateTime.parse(r['ends_at'] as String).toLocal()
        : null,
    capacity: (r['capacity'] as int?) ?? 100,
    rsvpCount: rsvps
        .where((s) => (s as Map)['status'] == 'going')
        .length,
    myStatus: uid == null
        ? null
        : rsvps
            .where((s) => (s as Map)['user_id'] == uid)
            .cast<Map>()
            .map<String?>((s) => s['status'] as String?)
            .firstOrNull,
    hostName: profileNames[createdBy] ?? 'DearCocoa',
    meetingUrl: r['meeting_url'] as String?,
    coverUrl: resolveMediaUrl(r['cover_path'] as String?),
    isVirtual: (r['is_virtual'] as bool?) ?? true,
    location: (r['location'] as String?)?.isNotEmpty == true
        ? r['location'] as String
        : null,
    goingNames: goingNames.take(4).toList(),
    program: [
      for (final p in (r['program'] as List? ?? []))
        EventProgramItem(
          title: (p as Map)['title'] as String,
          speaker: p['speaker'] as String? ?? '',
          description: p['description'] as String? ?? '',
          startsAt: DateTime.parse(p['starts_at'] as String).toLocal(),
        ),
    ],
  );
}

Future<List<EventItem>> fetchEvents() async {
  final uid = _uid();
  final rows = await SupabaseService.instance.client
      .from('events')
      .select('''
        id, title, description, category, starts_at, ends_at, capacity,
        meeting_url, cover_path, is_virtual, location, created_by,
        rsvps:event_rsvps(user_id, status),
        program:event_program(title, speaker, description, starts_at, sort)
      ''')
      .gte('starts_at', DateTime.now().toUtc().toIso8601String())
      .order('starts_at', ascending: true)
      .limit(30);
  final goingUserIds = <String>{
    for (final r in rows)
      for (final s in (r['rsvps'] as List? ?? []))
        if ((s as Map)['status'] == 'going') (s['user_id'] as String),
  };
  final names = await fetchProfileNames(
      {
        ...rows.map<String>((r) => r['created_by'] as String),
        ...goingUserIds,
      });
  return [
    for (final r in rows) eventItemFromRow(r, names, uid),
  ];
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
