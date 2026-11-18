import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../core/themes/app_colors.dart';
import '../core/themes/app_shadows.dart';
import '../../data/repositories/social.dart';
import '../../data/services/supabase_service.dart';
import '../../domain/models/social_models.dart';

/// Realtime group conversation (Supabase group_messages + Realtime).
class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key, required this.group});

  final GroupInfo group;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  List<GroupMessage> _messages = [];
  RealtimeChannel? _channel;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _myUserId = SupabaseService.instance.currentUserId;
    _load();
    _channel = subscribeTable('group_messages', _load);
  }

  @override
  void dispose() {
    try {
      _channel?.unsubscribe();
    } catch (_) {}
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final messages =
          await fetchGroupMessages(widget.group.id);
      if (!mounted) return;
      setState(() => _messages = messages);
      _scrollToBottom();
    } catch (_) {
      // network hiccup: keep current messages, realtime may refresh later
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || text.length > 2000) return;
    setState(() => _sending = true);
    try {
      await sendGroupMessage(widget.group.id, text);
      _controller.clear();
      await _load();
      if (mounted) setState(() => _sending = false);
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            Text(
              widget.group.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              '${widget.group.messageCount} messages · realtime',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Color(0xFF64748B)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildMessages()),
            _buildInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined,
                size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            const Text(
              'No messages yet.\nSay hello to the group!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final mine = message.userId == _myUserId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _MessageBubble(
            message: message,
            mine: mine,
          ),
        );
      },
    );
  }

  Widget _buildInput() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [AppShadows.card],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Write to the group…',
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});

  final GroupMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      decoration: BoxDecoration(
        color: mine ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            Text(
              message.authorName,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Text(
            message.content,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: mine ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _time(message.createdAt),
            style: TextStyle(
              fontSize: 10,
              color: mine
                  ? Colors.white.withValues(alpha: 0.7)
                  : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
    );
  }
}

String _time(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
