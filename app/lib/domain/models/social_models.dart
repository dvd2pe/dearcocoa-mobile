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

  bool get isGoing => myStatus == 'going';
  bool get isFull => rsvpCount >= capacity;
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
