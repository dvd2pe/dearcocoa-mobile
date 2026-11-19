import 'package:flutter_test/flutter_test.dart';
import 'package:dearcocoa/data/repositories/social.dart';

void main() {
  group('bestProfileName', () {
    test('prefers display_name when present', () {
      expect(
        bestProfileName(display: 'Sofia Rossi', username: 'sofia_r'),
        'Sofia Rossi',
      );
    });

    test('falls back to username when display_name empty', () {
      expect(
        bestProfileName(display: '', username: 'sofia_r'),
        'sofia_r',
      );
      expect(
        bestProfileName(display: null, username: 'sofia_r'),
        'sofia_r',
      );
    });

    test('falls back to given fallback when both missing', () {
      expect(
        bestProfileName(display: null, username: null, fallback: 'DearCocoa'),
        'DearCocoa',
      );
      expect(
        bestProfileName(display: null, username: null),
        'Cocoa friend',
      );
    });
  });

  group('communityPostFromRow', () {
    final baseRow = <String, dynamic>{
      'id': 'p1',
      'user_id': 'u1',
      'content': 'Good morning ☀️',
      'created_at': '2026-11-19T08:30:00Z',
      'like_count': 3,
      'comments': [
        {'count': 2},
      ],
      'likes': [
        {'user_id': 'u1'},
        {'user_id': 'u9'},
      ],
    };

    test('maps author name from the client-side profile join', () {
      final post = communityPostFromRow(baseRow, {'u1': 'Sofia Rossi'}, 'u1');
      expect(post.id, 'p1');
      expect(post.authorName, 'Sofia Rossi');
      expect(post.likeCount, 3);
      expect(post.commentCount, 2);
      expect(post.likedByMe, isTrue);
    });

    test('falls back to Cocoa friend when profile missing', () {
      final post = communityPostFromRow(baseRow, {}, 'u1');
      expect(post.authorName, 'Cocoa friend');
    });

    test('likedByMe false when uid not in likes or uid null', () {
      expect(communityPostFromRow(baseRow, {}, 'u7').likedByMe, isFalse);
      expect(communityPostFromRow(baseRow, {}, null).likedByMe, isFalse);
    });

    test('missing optional aggregates map to zero defaults', () {
      final bare = <String, dynamic>{
        'id': 'p2',
        'user_id': 'u2',
        'content': 'x',
        'created_at': '2026-11-19T08:30:00Z',
        'like_count': null,
      };
      final post = communityPostFromRow(bare, {}, null);
      expect(post.likeCount, 0);
      expect(post.commentCount, 0);
      expect(post.likedByMe, isFalse);
    });
  });

  group('eventItemFromRow', () {
    final baseRow = <String, dynamic>{
      'id': 'e1',
      'created_by': 'u1',
      'title': 'Full Moon Journaling Night',
      'description': 'Write under the full moon.',
      'category': 'wellness',
      'starts_at': '2026-11-23T10:27:19Z',
      'ends_at': '2026-11-23T11:27:19Z',
      'capacity': 50,
      'meeting_url': 'https://meet.example/x',
      'rsvps': [
        {'user_id': 'u1', 'status': 'going'},
        {'user_id': 'u2', 'status': 'interested'},
        {'user_id': 'u3', 'status': 'going'},
      ],
      'program': [
        {
          'title': 'Welcome circle',
          'speaker': 'Sofia',
          'description': 'Short intro',
          'starts_at': '2026-11-23T10:30:00Z',
        },
      ],
    };

    test('maps host name from the client-side profile join', () {
      final ev = eventItemFromRow(baseRow, {'u1': 'Sofia Rossi'}, null);
      expect(ev.hostName, 'Sofia Rossi');
      expect(ev.title, 'Full Moon Journaling Night');
      expect(ev.category, 'wellness');
      expect(ev.rsvpCount, 2);
      expect(ev.capacity, 50);
      expect(ev.isFull, isFalse);
      expect(ev.meetingUrl, 'https://meet.example/x');
      expect(ev.program, hasLength(1));
      expect(ev.program.first.title, 'Welcome circle');
    });

    test('falls back to DearCocoa when host profile missing', () {
      final ev = eventItemFromRow(baseRow, {}, null);
      expect(ev.hostName, 'DearCocoa');
    });

    test('myStatus reflects the current user rsvp', () {
      expect(eventItemFromRow(baseRow, {}, 'u1').myStatus, 'going');
      expect(eventItemFromRow(baseRow, {}, 'u2').myStatus, 'interested');
      expect(eventItemFromRow(baseRow, {}, 'u9').myStatus, isNull);
      expect(eventItemFromRow(baseRow, {}, null).myStatus, isNull);
    });

    test('defaults when optional columns missing', () {
      final bare = <String, dynamic>{
        'id': 'e2',
        'created_by': 'u2',
        'title': 'Circle',
        'starts_at': '2026-11-23T10:27:19Z',
      };
      final ev = eventItemFromRow(bare, {}, null);
      expect(ev.description, '');
      expect(ev.category, 'community');
      expect(ev.capacity, 100);
      expect(ev.rsvpCount, 0);
      expect(ev.endsAt, isNull);
      expect(ev.program, isEmpty);
    });

    test('v0.3.5: maps cover, in-person location and going names', () {
      final row = <String, dynamic>{
        ...baseRow,
        'cover_path': 'https://picsum.photos/seed/cocoa-moon/800/450',
        'is_virtual': false,
        'location': 'Villa Borghese, north gate',
      };
      final ev = eventItemFromRow(row, {
        'u1': 'Sofia Rossi',
        'u3': 'Luca Bianchi',
      }, 'u1');
      expect(ev.coverUrl, 'https://picsum.photos/seed/cocoa-moon/800/450');
      expect(ev.isVirtual, isFalse);
      expect(ev.location, 'Villa Borghese, north gate');
      expect(ev.placeLabel, 'Villa Borghese, north gate');
      expect(ev.isMaybe, isFalse);
      // going names exclude the 'interested' RSVP and are capped at 4
      expect(ev.goingNames, containsAll(['Sofia Rossi', 'Luca Bianchi']));
      expect(ev.goingNames, isNot(contains('Giulia Ferrari')));
    });

    test('v0.3.5: virtual defaults and maybe flag', () {
      final row = <String, dynamic>{
        ...baseRow,
        'is_virtual': true,
        'location': null,
      };
      final ev = eventItemFromRow(row, {}, 'u2');
      expect(ev.isVirtual, isTrue);
      expect(ev.placeLabel, 'Virtual');
      expect(ev.coverUrl, isNull);
      expect(ev.isMaybe, isTrue);
    });
  });

  group('splitMediaRef', () {
    test('passthrough for http(s) urls', () {
      final (url, ref) =
          splitMediaRef('https://picsum.photos/seed/cocoa-run/900/600');
      expect(url, 'https://picsum.photos/seed/cocoa-run/900/600');
      expect(ref, isNull);
    });

    test('splits bucket/path for storage refs', () {
      final (url, ref) = splitMediaRef('post-media/posts/u1/123_0.jpg');
      expect(url, isNull);
      expect(ref, isNotNull);
      expect(ref!.$1, 'post-media');
      expect(ref.$2, 'posts/u1/123_0.jpg');
    });

    test('returns empty parts for invalid refs', () {
      var (url, ref) = splitMediaRef(null);
      expect(url, isNull);
      expect(ref, isNull);
      (url, ref) = splitMediaRef('');
      expect(url, isNull);
      expect(ref, isNull);
      (url, ref) = splitMediaRef('   ');
      expect(url, isNull);
      expect(ref, isNull);
      (url, ref) = splitMediaRef('noslash');
      expect(url, isNull);
      expect(ref, isNull);
      (url, ref) = splitMediaRef('bucket/');
      expect(url, isNull);
      expect(ref, isNull);
    });
  });
}
