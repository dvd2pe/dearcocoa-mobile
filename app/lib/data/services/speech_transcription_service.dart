import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:dearcocoa/data/services/asset_safety_service.dart';
import 'package:dearcocoa/domain/models/agent_definitions.dart';
import 'package:dearcocoa/domain/models/llm_config.dart';
import 'package:dearcocoa/utils/logger.dart';
import 'package:dearcocoa/utils/user_storage.dart';

class SpeechTranscriptionResult {
  final String? text;
  final ModelUsage? usage;
  final String model;

  const SpeechTranscriptionResult({
    required this.text,
    required this.usage,
    required this.model,
  });
}

/// Speech-to-text service (v0.3.0).
///
/// The bundled offline whisper model (sherpa_onnx) was removed: it made the
/// release APK unreasonably large. Transcription now runs in the cloud only:
/// - Groq Whisper (whisper-large-v3-turbo) when a Groq API key is set in
///   Settings (preferred: fast, cheap, purpose-built for transcription).
/// - Otherwise the configured multimodal LLM (same as before, via AudioPart).
/// Voice notes are always recorded and stored as audio regardless of whether
/// any transcription provider is configured.
class SpeechTranscriptionService {
  SpeechTranscriptionService._();

  static final SpeechTranscriptionService instance =
      SpeechTranscriptionService._();

  final Logger _logger = getLogger('SpeechTranscriptionService');

  /// Local (offline) speech-to-text was removed in v0.3.0.
  Future<bool> isUsingLocalModel() async => false;

  /// No local model needs downloading anymore (kept for compatibility).
  Future<bool> requiresLocalModelDownload() async => false;

  /// Real-time streaming transcription was only possible with the removed
  /// local model.
  Future<bool> supportsStreamingTranscription() async => false;

  Future<String?> transcribeFile(
    String audioPath, {
    bool skipLengthCheck = false,
  }) async {
    final result = await transcribeFileWithMetadata(
      audioPath,
      skipLengthCheck: skipLengthCheck,
    );
    return result.text;
  }

  Future<SpeechTranscriptionResult> transcribeFileWithMetadata(
    String audioPath, {
    bool skipLengthCheck = false,
  }) async {
    return _transcribeFileWithCloud(audioPath);
  }

  Future<String?> transcribeSamples(Float32List samples) async {
    final result = await transcribeSamplesWithMetadata(samples);
    return result.text;
  }

  Future<SpeechTranscriptionResult> transcribeSamplesWithMetadata(
    Float32List samples,
  ) async {
    return _transcribeSamplesWithCloud(samples);
  }

  Future<SpeechTranscriptionResult> _transcribeFileWithCloud(
    String audioPath,
  ) async {
    final safety = await _inspectAudioForTranscription(audioPath);
    if (!safety.safeForAnalysis) {
      _logger.warning(
        'Skipping unsafe cloud audio transcription for $audioPath: ${safety.reason}',
      );
      return const SpeechTranscriptionResult(
        text: null,
        usage: null,
        model: 'asset-safety',
      );
    }
    final file = File(audioPath);
    final bytes = await file.readAsBytes();
    final mimeType = _mimeTypeForPath(audioPath);
    return _transcribeAudioBytesWithCloud(bytes, mimeType: mimeType);
  }

  Future<AssetSafetyReport> _inspectAudioForTranscription(
    String audioPath,
  ) async {
    final file = File(audioPath);
    if (!file.existsSync()) {
      throw Exception('Audio file not found: $audioPath');
    }
    return AssetSafetyService.instance.inspectFile(audioPath);
  }

  Future<SpeechTranscriptionResult> _transcribeSamplesWithCloud(
    Float32List samples,
  ) async {
    final bytes = _samplesToWavBytes(samples);
    return _transcribeAudioBytesWithCloud(bytes, mimeType: 'audio/wav');
  }

  /// Preferred path when the user configured a Groq API key: the OpenAI-
  /// compatible /audio/transcriptions endpoint (whisper-large-v3-turbo).
  /// Returns null when no key is set or the request fails (caller falls
  /// back to the multimodal LLM path).
  Future<SpeechTranscriptionResult?> _transcribeWithGroq(
    List<int> bytes, {
    required String mimeType,
  }) async {
    final apiKey = await UserStorage.getGroqSpeechApiKey();
    if (apiKey.isEmpty) return null;

    try {
      final uri = Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..fields['model'] = 'whisper-large-v3-turbo'
        ..fields['response_format'] = 'json'
        ..fields['temperature'] = '0'
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: _filenameForMime(mimeType),
          ),
        );

      final streamed = await request
          .send()
          .timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        _logger.warning(
          'Groq transcription failed (HTTP ${response.statusCode}): '
          '${response.body.length > 300 ? response.body.substring(0, 300) : response.body}',
        );
        return null;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final text = (decoded['text'] as String?)?.trim();
      if (text == null || text.isEmpty) return null;

      return SpeechTranscriptionResult(
        text: text,
        usage: null,
        model: 'groq-whisper-large-v3-turbo',
      );
    } catch (e) {
      _logger.warning('Groq transcription error: $e');
      return null;
    }
  }

  Future<SpeechTranscriptionResult> _transcribeAudioBytesWithCloud(
    List<int> bytes, {
    required String mimeType,
  }) async {
    final groqResult = await _transcribeWithGroq(bytes, mimeType: mimeType);
    if (groqResult != null) return groqResult;

    final resources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.chatAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );

    const systemPrompt = '''You are a speech transcription engine.
Your job is to return only a transcript, never an explanation.''';
    const prompt = '''Transcribe the spoken audio exactly.
Return the result wrapped in XML tags as:
<transcript>...</transcript>
Rules:
- Output exactly one transcript block.
- Do not add any text before or after the transcript block.
- Do not add introductions, labels, translations, summaries, notes, or quotes.
- Preserve the spoken language as-is.
- If the audio contains no recognizable speech, return <transcript></transcript>.''';
    final response = await resources.client.generate([
      SystemMessage(systemPrompt),
      UserMessage([TextPart(prompt), AudioPart(base64Encode(bytes), mimeType)]),
    ], modelConfig: resources.modelConfig);

    return SpeechTranscriptionResult(
      text: _normalizeCloudTranscript(response.textOutput),
      usage: response.usage,
      model: response.model,
    );
  }

  String? _normalizeCloudTranscript(String? text) {
    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty) return trimmed;

    final tagged = _extractTaggedTranscript(trimmed);
    if (tagged != null) {
      return _trimOuterQuotes(tagged);
    }

    if (_looksLikePlainTranscript(trimmed)) {
      return _trimOuterQuotes(trimmed);
    }

    _logger.warning(
      'Cloud speech transcription returned non-transcript text: $trimmed',
    );
    return null;
  }

  String? _extractTaggedTranscript(String text) {
    final match = RegExp(
      r'<transcript>([\s\S]*?)</transcript>',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    return match.group(1)?.trim();
  }

  bool _looksLikePlainTranscript(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return true;

    if (normalized.contains('```')) return false;

    final nonEmptyLines = normalized
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (nonEmptyLines.isEmpty) return true;

    final firstLine = nonEmptyLines.first;
    final lowerFirstLine = firstLine.toLowerCase();
    const explanatoryFragments = [
      'here is',
      'below is',
      'the following',
      'transcript of the speech',
      'transcript:',
      'transcription:',
      'following is a transcript',
      '以下是',
      '文字稿',
      '转写结果',
      '识别结果',
      '语音识别',
      '语音转写',
    ];

    if (explanatoryFragments.any(lowerFirstLine.contains) &&
        nonEmptyLines.length > 1) {
      return false;
    }

    if (RegExp(r'^[-*•]\s').hasMatch(firstLine)) return false;

    return true;
  }

  String _trimOuterQuotes(String text) {
    var normalized = text.trim();
    if ((normalized.startsWith('"') && normalized.endsWith('"')) ||
        (normalized.startsWith("'") && normalized.endsWith("'")) ||
        (normalized.startsWith('“') && normalized.endsWith('”')) ||
        (normalized.startsWith('‘') && normalized.endsWith('’'))) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }
    return normalized;
  }

  String _filenameForMime(String mimeType) {
    switch (mimeType) {
      case 'audio/wav':
        return 'audio.wav';
      case 'audio/aiff':
        return 'audio.aiff';
      case 'audio/aac':
        return 'audio.aac';
      case 'audio/ogg':
        return 'audio.ogg';
      case 'audio/flac':
        return 'audio.flac';
      default:
        return 'audio.mp3';
    }
  }

  /// Save raw PCM 16-bit data (16kHz, mono) as a WAV file.
  Future<void> savePcmAsWav(String filePath, Uint8List pcmData) async {
    final file = File(filePath);
    final sink = file.openWrite();
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;
    final header = ByteData(44);
    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, 16000, Endian.little); // sample rate
    header.setUint32(28, 32000, Endian.little); // byte rate
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint32(34, 16, Endian.little); // bits per sample
    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);
    sink.add(header.buffer.asUint8List());
    sink.add(pcmData);
    await sink.close();
  }

  String _mimeTypeForPath(String audioPath) {
    switch (path.extension(audioPath).toLowerCase()) {
      case '.wav':
        return 'audio/wav';
      case '.mp3':
      case '.m4a':
        return 'audio/mp3';
      case '.aiff':
      case '.aif':
        return 'audio/aiff';
      case '.aac':
        return 'audio/aac';
      case '.ogg':
        return 'audio/ogg';
      case '.flac':
        return 'audio/flac';
      case '.wma':
        throw Exception('Audio format .wma is not supported.');
      default:
        return 'audio/mp3';
    }
  }

  List<int> _samplesToWavBytes(Float32List samples) {
    final pcm = Int16List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      final scaled = (samples[i] * 32767).round().clamp(-32768, 32767);
      pcm[i] = scaled;
    }

    final pcmBytes = pcm.buffer.asUint8List();
    final dataSize = pcmBytes.length;
    final fileSize = 36 + dataSize;
    final header = ByteData(44);

    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, 16000, Endian.little); // sample rate
    header.setUint32(28, 32000, Endian.little); // byte rate
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits per sample
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataSize, Endian.little);

    return [...header.buffer.asUint8List(), ...pcmBytes];
  }
}
