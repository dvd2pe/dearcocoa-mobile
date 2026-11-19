import 'package:flutter/material.dart';

import 'package:dearcocoa/l10n/app_localizations.dart';
import 'package:dearcocoa/ui/core/themes/app_colors.dart' as composer_colors;
import 'package:dearcocoa/data/repositories/mood_repository.dart';
import 'package:dearcocoa/data/services/card_renderer.dart';
import 'package:dearcocoa/data/services/event_bus_service.dart';
import 'package:dearcocoa/data/services/file_system_service.dart';
import 'package:dearcocoa/domain/models/card_model.dart';
import 'package:dearcocoa/utils/logger.dart';
import 'package:dearcocoa/utils/toast_helper.dart';
import 'package:dearcocoa/utils/user_storage.dart';

final _logger = getLogger('SimpleNoteComposer');

/// Simple note composer shown when no AI provider is configured.
///
/// The "+" button must always produce a timeline entry — with no working
/// AI setup the Super Agent chat cannot create cards, so this composer
/// writes the card file directly (no LLM involved):
///  - Note: free text + optional mood face (logged to the mood tracker).
///  - Task: a checklist card with editable subtasks.
///  - Rating: a 1-5 star rating card.
class SimpleNoteComposer extends StatefulWidget {
  const SimpleNoteComposer({super.key});

  @override
  State<SimpleNoteComposer> createState() => _SimpleNoteComposerState();
}

enum _ComposerMode { note, task, rating }

/// Localized mood label for 1..5 (shared with the mood screen).
String _moodLabel(AppLocalizations l10n, int mood) {
  switch (mood) {
    case 1:
      return l10n.moodVeryLow;
    case 2:
      return l10n.moodLow;
    case 3:
      return l10n.moodOkay;
    case 4:
      return l10n.moodGood;
    default:
      return l10n.moodGreat;
  }
}

class _SimpleNoteComposerState extends State<SimpleNoteComposer> {
  static const _moodIcons = [
    Icons.sentiment_very_dissatisfied_rounded,
    Icons.sentiment_dissatisfied_rounded,
    Icons.sentiment_neutral_rounded,
    Icons.sentiment_satisfied_rounded,
    Icons.sentiment_very_satisfied_rounded,
  ];

  /// Per-mood colors (1=very low … 5=great) — same palette as the chart.
  static const _moodColors = [
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFEAB308),
    Color(0xFF22C55E),
    Color(0xFF10B981),
  ];

  _ComposerMode _mode = _ComposerMode.note;
  final _textController = TextEditingController();
  final _titleController = TextEditingController();
  final _subjectController = TextEditingController();
  final List<TextEditingController> _subtaskControllers = [
    TextEditingController(),
  ];
  int? _selectedMood;
  int _ratingScore = 4;
  bool _saving = false;

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    _subjectController.dispose();
    for (final c in _subtaskControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit {
    switch (_mode) {
      case _ComposerMode.note:
        return _textController.text.trim().isNotEmpty;
      case _ComposerMode.task:
        return _subtaskControllers.any((c) => c.text.trim().isNotEmpty);
      case _ComposerMode.rating:
        return _subjectController.text.trim().isNotEmpty;
    }
  }

  Future<void> _submit() async {
    if (_saving || !_canSubmit) return;
    setState(() => _saving = true);
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final fs = FileSystemService.instance;
      final now = DateTime.now();
      final factId = await fs.allocateCardFactId(userId);
      final epoch = now.millisecondsSinceEpoch ~/ 1000;
      final l10n = UserStorage.l10n;

      final List<UiConfig> uiConfigs;
      String? title;
      String fact;
      switch (_mode) {
        case _ComposerMode.note:
          final text = _textController.text.trim();
          title = text.split('\n').first.trim();
          if (title.length > 60) title = '${title.substring(0, 60)}…';
          fact = text;
          uiConfigs = [
            UiConfig(templateId: 'snippet', data: {
              'text': text,
              'style': 'default',
            }),
          ];
          break;
        case _ComposerMode.task:
          final items = _subtaskControllers
              .map((c) => c.text.trim())
              .where((t) => t.isNotEmpty)
              .toList();
          title = _titleController.text.trim().isEmpty
              ? l10n.composerTaskDefaultTitle
              : _titleController.text.trim();
          fact = items.map((t) => '- [ ] $t').join('\n');
          uiConfigs = [
            UiConfig(templateId: 'task', data: {
              'title': title,
              'subtasks': [
                for (final t in items) {'title': t, 'completed': false},
              ],
            }),
          ];
          break;
        case _ComposerMode.rating:
          title = _subjectController.text.trim();
          fact = '$title — $_ratingScore/5';
          uiConfigs = [
            UiConfig(templateId: 'rating', data: {
              'subject': title,
              'score': _ratingScore,
              'max_score': 5,
            }),
          ];
          break;
      }

      final card = CardData(
        factId: factId,
        createdAt: epoch,
        timestamp: epoch,
        status: 'completed',
        title: title,
        tags: const [],
        fact: fact,
        uiConfigs: uiConfigs,
      );
      final ok = await fs.safeWriteCardFile(userId, factId, card);
      if (!ok) {
        throw Exception('Failed to write card file $factId');
      }

      // Optional mood face: also log today's mood in the mood tracker.
      if (_mode == _ComposerMode.note && _selectedMood != null) {
        try {
          await MoodRepository.instance.setMoodForDay(
            userId: userId,
            entryDate: now.toIso8601String().substring(0, 10),
            mood: _selectedMood!,
          );
        } catch (e) {
          _logger.warning('Failed to log mood from composer: $e');
        }
      }

      // Same publish path as the demo service: timeline picks up the card.
      final renderResult = await renderCard(
        userId: userId,
        cardData: card,
        factContent: fact,
      );
      EventBusService.instance.emitEvent(CardAddedMessage(
        id: factId,
        html: renderResult.html ?? '',
        timestamp: card.timestamp,
        tags: card.tags,
        status: renderResult.status,
        title: card.title,
        uiConfigs: renderResult.uiConfigs,
        rawText: fact,
      ));

      if (mounted) {
        ToastHelper.showSuccess(context, l10n.composerSaved);
        Navigator.pop(context);
      }
    } catch (e) {
      _logger.severe('Simple composer submit failed: $e');
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
    final l10n = UserStorage.l10n;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
              Text(
                l10n.composerTitle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              // Mode chips
              Row(
                children: [
                  _modeChip(
                    icon: Icons.notes_rounded,
                    label: l10n.composerModeNote,
                    selected: _mode == _ComposerMode.note,
                    onTap: () => setState(() => _mode = _ComposerMode.note),
                  ),
                  const SizedBox(width: 8),
                  _modeChip(
                    icon: Icons.checklist_rounded,
                    label: l10n.composerModeTask,
                    selected: _mode == _ComposerMode.task,
                    onTap: () => setState(() => _mode = _ComposerMode.task),
                  ),
                  const SizedBox(width: 8),
                  _modeChip(
                    icon: Icons.star_rounded,
                    label: l10n.composerModeRating,
                    selected: _mode == _ComposerMode.rating,
                    onTap: () => setState(() => _mode = _ComposerMode.rating),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildModeBody(l10n),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _canSubmit && !_saving ? _submit : null,
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _canSubmit && !_saving
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
                      : Text(
                          l10n.sendLabel,
                          style: const TextStyle(
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

  Widget _modeChip({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? composer_colors.AppColors.primary
                : const Color(0xFFF2F4FF),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? Colors.white
                    : composer_colors.AppColors.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Colors.white
                        : composer_colors.AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeBody(AppLocalizations l10n) {
    switch (_mode) {
      case _ComposerMode.note:
        return _buildNoteBody(l10n);
      case _ComposerMode.task:
        return _buildTaskBody(l10n);
      case _ComposerMode.rating:
        return _buildRatingBody(l10n);
    }
  }

  Widget _buildNoteBody(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _textController,
          minLines: 3,
          maxLines: 8,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: l10n.composerHint,
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color:
                    composer_colors.AppColors.primary.withValues(alpha: 0.5),
              ),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _selectedMood == null
              ? l10n.composerMoodOptional
              : l10n.moodLoggedAs(_moodLabel(l10n, _selectedMood!)),
          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 1; i <= 5; i++)
              GestureDetector(
                onTap: () => setState(() {
                  _selectedMood = _selectedMood == i ? null : i;
                }),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _selectedMood == i
                        ? _moodColors[i - 1].withValues(alpha: 0.15)
                        : const Color(0xFFF2F4FF),
                    border: _selectedMood == i
                        ? Border.all(color: _moodColors[i - 1], width: 2)
                        : null,
                  ),
                  child: Icon(
                    _moodIcons[i - 1],
                    size: 24,
                    color: _selectedMood == i
                        ? _moodColors[i - 1]
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTaskBody(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            hintText: l10n.composerTaskDefaultTitle,
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
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _subtaskControllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subtaskControllers[i],
                    autofocus: i == _subtaskControllers.length - 1 &&
                        _subtaskControllers.length > 1,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: l10n.composerTaskItemHint,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                if (_subtaskControllers.length > 1)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        size: 20, color: Color(0xFF94A3B8)),
                    onPressed: () => setState(() {
                      _subtaskControllers[i].dispose();
                      _subtaskControllers.removeAt(i);
                    }),
                  ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(
                () => _subtaskControllers.add(TextEditingController())),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.composerAddItem),
          ),
        ),
      ],
    );
  }

  Widget _buildRatingBody(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _subjectController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: l10n.composerRatingDefaultSubject,
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
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              GestureDetector(
                onTap: () => setState(() => _ratingScore = i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    i <= _ratingScore
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 36,
                    color: i <= _ratingScore
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFCBD5E1),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
