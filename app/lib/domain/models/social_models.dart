/// Data models for DearCocoa's social layer (community, groups, events).
/// Rows come from Supabase (community schema) and are rendered by the
/// memex-style UI widgets.
class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.content,
    required this.createdAt,
    required this.likeCount,
    required this.commentCount,
    required this.likedByMe,
    this.groupName,
    this.mediaUrls = const <String>[],
  });

  final String id;
  final String userId;
  final String authorName;
  final String content;
  final DateTime createdAt;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final String? groupName;

  /// DearCocoa v0.3.5: photo attachments (post-media storage or external URLs).
  final List<String> mediaUrls;
}

class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.authorName,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String authorName;
  final String content;
  final DateTime createdAt;
}

/// DearCocoa v0.3.5: public member profile (tappable author in the feed).
class MemberProfile {
  const MemberProfile({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.bio,
    this.avatarUrl,
    this.joinedAt,
    this.postCount = 0,
  });

  final String userId;
  final String username;
  final String displayName;
  final String bio;
  final String? avatarUrl;
  final DateTime? joinedAt;
  final int postCount;
}

class GroupInfo {
  const GroupInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.isMember,
    required this.messageCount,
    required this.lastMessageAt,
  });

  final String id;
  final String name;
  final String description;
  final bool isMember;
  final int messageCount;
  final DateTime? lastMessageAt;
}

class GroupMessage {
  const GroupMessage({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String authorName;
  final String content;
  final DateTime createdAt;
}

class EventItem {
  const EventItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.startsAt,
    required this.endsAt,
    required this.capacity,
    required this.rsvpCount,
    required this.myStatus,
    required this.hostName,
    this.program = const <EventProgramItem>[],
    this.meetingUrl,
    this.coverUrl,
    this.isVirtual = true,
    this.location,
    this.goingNames = const <String>[],
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final DateTime startsAt;
  final DateTime? endsAt;
  final int capacity;
  final int rsvpCount;
  final String? myStatus;
  final String hostName;
  final List<EventProgramItem> program;
  final String? meetingUrl;

  /// DearCocoa v0.3.5: richer event cards.
  final String? coverUrl;
  final bool isVirtual;
  final String? location;

  /// Display names of the first going participants (avatar circles).
  final List<String> goingNames;

  bool get isGoing => myStatus == 'going';
  bool get isMaybe => myStatus == 'interested';
  bool get isFull => rsvpCount >= capacity;
  String get placeLabel => isVirtual ? 'Virtual' : (location ?? 'In person');
}

class EventProgramItem {
  const EventProgramItem({
    required this.title,
    required this.speaker,
    required this.description,
    required this.startsAt,
  });

  final String title;
  final String speaker;
  final String description;
  final DateTime startsAt;
}
