import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:dearcocoa/data/services/card_renderer.dart';
import 'package:dearcocoa/data/services/event_bus_service.dart';
import 'package:dearcocoa/data/services/file_system_service.dart';
import 'package:dearcocoa/domain/models/card_model.dart';
import 'package:dearcocoa/utils/logger.dart';
import 'package:dearcocoa/utils/toast_helper.dart';
import 'package:dearcocoa/utils/user_storage.dart';
import 'package:dearcocoa/ui/core/widgets/local_image.dart';

import 'template_registry.dart';

final _logger = getLogger('TemplateComposer');

/// Generic per-template creation form (v0.3.5).
///
/// Opened from the simple composer ("More types") and from the template
/// gallery preview ("Use this template"). Fills the fields declared in
/// [TemplateSpec] and saves a timeline card through the same local-first
/// path used by the simple composer (no LLM involved).
Future<void> showTemplateComposer(BuildContext context, TemplateSpec spec) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TemplateComposerSheet(spec: spec),
  );
}

class _TemplateComposerSheet extends StatefulWidget {
  final TemplateSpec spec;

  const _TemplateComposerSheet({required this.spec});

  @override
  State<_TemplateComposerSheet> createState() => _TemplateComposerSheetState();
}

class _TemplateComposerSheetState extends State<_TemplateComposerSheet> {
  final Map<String, TextEditingController> _text = {};
  final Map<String, dynamic> _values = {};
  final Map<String, List<TextEditingController>> _listText = {};
  final Map<String, List<(TextEditingController, TextEditingController)>> _kv =
      {};
  bool _saving = false;

  TemplateSpec get spec => widget.spec;
  String get _tplId => spec.templateId;

  @override
  void initState() {
    super.initState();
    for (final f in spec.fields) {
      switch (f.type) {
        case TemplateFieldType.text:
        case TemplateFieldType.multiline:
        case TemplateFieldType.number:
        case TemplateFieldType.int:
          _text[f.key] =
              TextEditingController(text: f.initial?.toString() ?? '');
          break;
        case TemplateFieldType.stars:
          _values[f.key] = (f.initial as int?) ?? 4;
          break;
        case TemplateFieldType.mood:
          _values[f.key] = (f.initial as int?) ?? 3;
          break;
        case TemplateFieldType.datetime:
          _values[f.key] = '';
          break;
        case TemplateFieldType.image:
          _values[f.key] = '';
          break;
        case TemplateFieldType.images:
          _values[f.key] = <String>[];
          break;
        case TemplateFieldType.listText:
          _listText[f.key] = [TextEditingController()];
          break;
        case TemplateFieldType.kv:
          _kv[f.key] = [
            (TextEditingController(), TextEditingController()),
          ];
          break;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    for (final list in _listText.values) {
      for (final c in list) {
        c.dispose();
      }
    }
    for (final rows in _kv.values) {
      for (final (a, b) in rows) {
        a.dispose();
        b.dispose();
      }
    }
    super.dispose();
  }

  bool get _canSubmit {
    for (final f in spec.fields) {
      if (!f.required) continue;
      switch (f.type) {
        case TemplateFieldType.text:
        case TemplateFieldType.multiline:
        case TemplateFieldType.number:
        case TemplateFieldType.int:
          if (_text[f.key]!.text.trim().isEmpty) return false;
          break;
        case TemplateFieldType.stars:
        case TemplateFieldType.mood:
          if ((_values[f.key] as int?) == null) return false;
          break;
        case TemplateFieldType.datetime:
          if ((_values[f.key] as String?)?.isEmpty ?? true) return false;
          break;
        case TemplateFieldType.image:
          if ((_values[f.key] as String?)?.isEmpty ?? true) return false;
          break;
        case TemplateFieldType.images:
          if ((_values[f.key] as List?)?.isEmpty ?? true) return false;
          break;
        case TemplateFieldType.listText:
          if (!_listText[f.key]!.any((c) => c.text.trim().isNotEmpty)) {
            return false;
          }
          break;
        case TemplateFieldType.kv:
          break; // kv never required
      }
    }
    return true;
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

      // Fill values from controllers.
      final values = <String, dynamic>{..._values};
      for (final e in _text.entries) {
        final f = spec.fields.firstWhere((f) => f.key == e.key);
        if (f.type == TemplateFieldType.number) {
          values[e.key] = num.tryParse(e.value.text.replaceAll(',', '.')) ?? 0;
        } else if (f.type == TemplateFieldType.int) {
          values[e.key] = int.tryParse(e.value.text) ?? (f.initial as int?) ?? 0;
        } else {
          values[e.key] = e.value.text.trim();
        }
      }
      for (final e in _listText.entries) {
        values[e.key] = [
          for (final c in e.value)
            if (c.text.trim().isNotEmpty) c.text.trim(),
        ];
      }
      for (final e in _kv.entries) {
        final map = <String, String>{};
        for (final (k, v) in e.value) {
          if (k.text.trim().isEmpty) continue;
          map[k.text.trim()] = v.text.trim();
        }
        values[e.key] = map;
      }

      final data = buildTemplateData(spec, values);
      final title = templateRecordTitle(spec, data);
      final fact = templateRecordFact(spec, data);
      final now = DateTime.now();
      final factId = await fs.allocateCardFactId(userId);
      final epoch = now.millisecondsSinceEpoch ~/ 1000;

      final card = CardData(
        factId: factId,
        createdAt: epoch,
        timestamp: epoch,
        status: 'completed',
        title: title,
        tags: [spec.category],
        fact: fact,
        assets: _collectAssets(data),
        uiConfigs: [UiConfig(templateId: _tplId, data: data)],
      );
      final ok = await fs.safeWriteCardFile(userId, factId, card);
      if (!ok) {
        throw Exception('Failed to write card file $factId');
      }

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
        ToastHelper.showSuccess(context, '${spec.label} saved');
        Navigator.pop(context);
      }
    } catch (e) {
      _logger.severe('Template composer submit failed: $e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  List<String> _collectAssets(Map<String, dynamic> data) {
    final urls = <String>[];
    final single = data['image_url'];
    if (single is String && single.startsWith('fs://')) urls.add(single);
    final multi = data['image_urls'];
    if (multi is List) {
      for (final u in multi) {
        if (u is String && u.startsWith('fs://')) urls.add(u);
      }
    }
    return [for (final u in urls) '![image]($u)'];
  }

  // ------------------------------------------------------------ form UI

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
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: templateCategoryColor(spec.category)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(spec.icon,
                        size: 20, color: templateCategoryColor(spec.category)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spec.label,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          spec.category,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  children: [
                    for (final f in spec.fields) _buildField(f),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              const SizedBox(height: 12),
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
                      : const Text(
                          'Save card',
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

  Widget _buildField(TemplateField f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${f.label}${f.required ? ' *' : ''}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 6),
          _buildFieldInput(f),
        ],
      ),
    );
  }

  Widget _buildFieldInput(TemplateField f) {
    switch (f.type) {
      case TemplateFieldType.text:
        return _textField(f.key, f.hint, maxLines: 1);
      case TemplateFieldType.multiline:
        return _textField(f.key, f.hint, maxLines: 4);
      case TemplateFieldType.number:
        return _textField(f.key, f.hint,
            maxLines: 1, keyboardType: TextInputType.number);
      case TemplateFieldType.int:
        return _textField(f.key, f.hint,
            maxLines: 1, keyboardType: TextInputType.number);
      case TemplateFieldType.stars:
        return _starsRow(f.key);
      case TemplateFieldType.mood:
        return _moodRow(f.key);
      case TemplateFieldType.datetime:
        return _datetimeField(f);
      case TemplateFieldType.image:
        return _imageField(f);
      case TemplateFieldType.images:
        return _imagesField(f);
      case TemplateFieldType.listText:
        return _listField(f);
      case TemplateFieldType.kv:
        return _kvField(f);
    }
  }

  Widget _textField(
    String key,
    String? hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final controller = _text[key]!;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      decoration: _inputDecoration(hint),
    );
  }

  InputDecoration _inputDecoration(String? hint) => InputDecoration(
        hintText: hint,
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
            color: templateCategoryColor(spec.category).withValues(alpha: 0.5),
          ),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  Widget _starsRow(String key) {
    final score = (_values[key] as int?) ?? 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTap: () => setState(() => _values[key] = i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                i <= score ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 34,
                color: i <= score
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFFCBD5E1),
              ),
            ),
          ),
      ],
    );
  }

  static const _moodIcons = [
    Icons.sentiment_very_dissatisfied_rounded,
    Icons.sentiment_dissatisfied_rounded,
    Icons.sentiment_neutral_rounded,
    Icons.sentiment_satisfied_rounded,
    Icons.sentiment_very_satisfied_rounded,
  ];
  static const _moodColors = [
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFEAB308),
    Color(0xFF22C55E),
    Color(0xFF10B981),
  ];

  Widget _moodRow(String key) {
    final selected = (_values[key] as int?) ?? 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTap: () => setState(() => _values[key] = i),
            child: Container(
              width: 42,
              height: 42,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected == i
                    ? _moodColors[i - 1].withValues(alpha: 0.15)
                    : const Color(0xFFF2F4FF),
                border: selected == i
                    ? Border.all(color: _moodColors[i - 1], width: 2)
                    : null,
              ),
              child: Icon(
                _moodIcons[i - 1],
                size: 22,
                color: selected == i
                    ? _moodColors[i - 1]
                    : const Color(0xFF94A3B8),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _pickDateTime(String key) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => _values[key] = dt.toIso8601String());
  }

  Widget _datetimeField(TemplateField f) {
    final value = _values[f.key] as String? ?? '';
    final dt = DateTime.tryParse(value);
    final label = dt == null
        ? (f.hint ?? 'Pick date and time')
        : MaterialLocalizations.of(context).formatFullDate(dt) +
            ', ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: () => _pickDateTime(f.key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_outlined,
                size: 18, color: Color(0xFF94A3B8)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: dt == null
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _savePickedImage(XFile file) async {
    final userId = await UserStorage.getUserId();
    if (userId == null) return null;
    final fs = FileSystemService.instance;
    final (filename, _) = await fs.saveAssetFromFile(
      userId: userId,
      sourcePath: file.path,
      assetType: 'img',
    );
    return 'fs://$filename';
  }

  Widget _imageField(TemplateField f) {
    final value = _values[f.key] as String? ?? '';
    return GestureDetector(
      onTap: () async {
        final picker = ImagePicker();
        final file = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 82,
          maxWidth: 1600,
        );
        if (file == null) return;
        final url = await _savePickedImage(file);
        if (url != null && mounted) setState(() => _values[f.key] = url);
      },
      child: Container(
        height: 84,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: value.isEmpty
            ? const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        size: 18, color: Color(0xFF94A3B8)),
                    SizedBox(width: 8),
                    Text('Choose from gallery',
                        style: TextStyle(color: Color(0xFF94A3B8))),
                  ],
                ),
              )
            : Row(
                children: [
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: _ImageOrIcon(url: value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('Tap to change',
                      style: TextStyle(color: Color(0xFF94A3B8))),
                ],
              ),
      ),
    );
  }

  Widget _imagesField(TemplateField f) {
    final urls = (_values[f.key] as List?)?.cast<String>() ?? <String>[];
    return Column(
      children: [
        GestureDetector(
          onTap: () async {
            final picker = ImagePicker();
            final files = await picker.pickMultiImage(imageQuality: 82);
            if (files.isEmpty) return;
            final saved = <String>[];
            for (final file in files) {
              final url = await _savePickedImage(file);
              if (url != null) saved.add(url);
            }
            if (saved.isNotEmpty && mounted) {
              setState(() => _values[f.key] = [...urls, ...saved]);
            }
          },
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 18, color: Color(0xFF94A3B8)),
                  SizedBox(width: 8),
                  Text('Add photos',
                      style: TextStyle(color: Color(0xFF94A3B8))),
                ],
              ),
            ),
          ),
        ),
        if (urls.isNotEmpty)
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  child: _ImageOrIcon(url: urls[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _listField(TemplateField f) {
    final controllers = _listText[f.key]!;
    return Column(
      children: [
        for (var i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controllers[i],
                    onChanged: (_) => setState(() {}),
                    decoration:
                        _inputDecoration(f.hint ?? 'Item ${i + 1}'),
                  ),
                ),
                if (controllers.length > 1)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        size: 20, color: Color(0xFF94A3B8)),
                    onPressed: () => setState(() {
                      controllers[i].dispose();
                      controllers.removeAt(i);
                    }),
                  ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => controllers.add(TextEditingController())),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add item'),
          ),
        ),
      ],
    );
  }

  Widget _kvField(TemplateField f) {
    final rows = _kv[f.key]!;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: rows[i].$1,
                    decoration: _inputDecoration('Key'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: rows[i].$2,
                    decoration: _inputDecoration('Value'),
                  ),
                ),
                if (rows.length > 1)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        size: 20, color: Color(0xFF94A3B8)),
                    onPressed: () => setState(() {
                      rows[i].$1.dispose();
                      rows[i].$2.dispose();
                      rows.removeAt(i);
                    }),
                  ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() =>
                rows.add((TextEditingController(), TextEditingController()))),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add row'),
          ),
        ),
      ],
    );
  }
}

/// Renders a fs:// asset or a network URL; falls back to an icon.
class _ImageOrIcon extends StatelessWidget {
  final String url;
  const _ImageOrIcon({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const Icon(Icons.image_outlined, color: Color(0xFFCBD5E1));
    }
    return LocalImage(
      url: url,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.image_outlined, color: Color(0xFFCBD5E1)),
    );
  }
}
