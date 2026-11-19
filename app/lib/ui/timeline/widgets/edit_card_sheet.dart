import 'package:flutter/material.dart';

import 'package:dearcocoa/data/services/card_renderer.dart';
import 'package:dearcocoa/data/services/event_bus_service.dart';
import 'package:dearcocoa/data/services/file_system_service.dart';
import 'package:dearcocoa/domain/models/card_detail_model.dart';
import 'package:dearcocoa/utils/logger.dart';
import 'package:dearcocoa/utils/toast_helper.dart';
import 'package:dearcocoa/utils/user_storage.dart';

final _logger = getLogger('EditCardSheet');

/// DearCocoa v0.3.5: manual editing of a timeline record (title, text, tags).
///
/// Until now entries could only be deleted or re-timed by the AI; this sheet
/// gives the user direct edit access. Saves through the same local-first
/// card-file path the composers use, then emits [CardUpdatedMessage] so the
/// timeline re-renders the card in place.
///
/// Returns true when the card was saved.
Future<bool> showEditCardSheet(
  BuildContext context,
  CardDetailModel detail,
) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _EditCardSheet(detail: detail),
  );
  return result == true;
}

class _EditCardSheet extends StatefulWidget {
  final CardDetailModel detail;

  const _EditCardSheet({required this.detail});

  @override
  State<_EditCardSheet> createState() => _EditCardSheetState();
}

class _EditCardSheetState extends State<_EditCardSheet> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final TextEditingController _tags;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.detail.title);
    _content = TextEditingController(text: widget.detail.rawContent);
    _tags = TextEditingController(text: widget.detail.tags.join(', '));
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _tags.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving &&
      (_title.text.trim().isNotEmpty || _content.text.trim().isNotEmpty);

  Future<void> _save() async {
    if (_saving || !_canSave) return;
    setState(() => _saving = true);
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        if (mounted) Navigator.pop(context, false);
        return;
      }
      final fs = FileSystemService.instance;
      final existing = await fs.readCardFile(userId, widget.detail.id);
      if (existing == null) {
        throw Exception('Card ${widget.detail.id} not found');
      }

      final tags = [
        for (final t in _tags.text.split(','))
          if (t.trim().isNotEmpty) t.trim(),
      ];
      final title = _title.text.trim().isEmpty
          ? existing.title
          : _title.text.trim();
      final fact =
          _content.text.trim().isEmpty ? existing.fact : _content.text.trim();

      final updated = existing.copyWith(
        title: title,
        tags: tags,
        fact: fact,
      );
      final ok = await fs.safeWriteCardFile(userId, widget.detail.id, updated);
      if (!ok) {
        throw Exception('Failed to write card file ${widget.detail.id}');
      }

      final renderResult = await renderCard(
        userId: userId,
        cardData: updated,
        factContent: fact ?? '',
      );
      EventBusService.instance.emitEvent(CardUpdatedMessage(
        id: widget.detail.id,
        html: renderResult.html ?? '',
        timestamp: updated.timestamp,
        tags: updated.tags,
        status: renderResult.status,
        title: updated.title,
        uiConfigs: renderResult.uiConfigs,
        rawText: fact,
        address: updated.address,
      ));

      if (mounted) {
        ToastHelper.showSuccess(context, 'Entry updated');
        Navigator.pop(context, true);
      }
    } catch (e) {
      _logger.severe('Edit card failed: $e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Edit entry',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 14),
              _label('Title'),
              TextField(
                controller: _title,
                onChanged: (_) => setState(() {}),
                decoration: _decoration('Title'),
              ),
              const SizedBox(height: 12),
              _label('Text'),
              TextField(
                controller: _content,
                minLines: 4,
                maxLines: 10,
                onChanged: (_) => setState(() {}),
                decoration: _decoration('Entry text'),
              ),
              const SizedBox(height: 12),
              _label('Tags (comma separated)'),
              TextField(
                controller: _tags,
                decoration: _decoration('personal, work, ideas'),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _canSave ? _save : null,
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _canSave
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save changes',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF475569),
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: const Color(0xFF5B6CFF).withValues(alpha: 0.5),
          ),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
}
