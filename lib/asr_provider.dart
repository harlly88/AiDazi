import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// 阿里云百炼 ASR 客户端（qwen3-asr-flash 模型，OpenAI 兼容 chat/completions 端点）
///
/// 17.1 彻底重写：原实现用 multipart /audio/transcriptions（OpenAI Whisper 端点）
/// 百炼不支持该端点，永远 404。正确方式是 chat/completions + messages 多模态消息，
/// content 里放 type=input_audio，input_audio 为 base64（带 data:audio/wav;base64, 前缀）。
///
/// - 模型：qwen3-asr-flash（支持中英日韩等多语言，5 分钟 / 10MB 上限）
/// - 鉴权：Bearer API Key（与千问对话共用）
/// - 输入：本地录音 WAV 文件（16kHz 单声道，由 record 包输出）
/// - 输出：识别文本，由调用方直接发送
class BailianAsrClient {
  final String apiKey;
  final String baseUrl;
  final String model;
  final http.Client _httpClient;

  BailianAsrClient({
    required this.apiKey,
    this.baseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    this.model = 'qwen3-asr-flash',
    http.Client? httpClient,
  })  : _httpClient = httpClient ?? http.Client(),
        assert(apiKey.isNotEmpty, 'API key cannot be empty');

  /// 识别本地录音文件，返回文本
  ///
  /// 流程：
  /// 1. 读本地音频文件 → base64 编码 → 拼 data URI
  /// 2. POST chat/completions，messages 里放 input_audio
  /// 3. 兼容两种响应格式：choices[0].message.content（标准 OpenAI）
  ///    和 output.text / output.output.sentence.text（百炼特殊格式）
  Future<String> transcribe({
    required File audioFile,
    String? languageHint,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (!await audioFile.exists()) {
      throw ArgumentError('录音文件不存在: ${audioFile.path}');
    }

    final bytes = await audioFile.readAsBytes();
    if (bytes.isEmpty) {
      throw ArgumentError('录音文件为空');
    }
    // qwen3-asr-flash 限制 10MB
    if (bytes.length > 10 * 1024 * 1024) {
      throw ArgumentError('录音文件过大（${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB），上限 10MB');
    }

    final base64Audio = base64Encode(bytes);
    // 根据文件扩展名推断 mime type，默认 audio/wav
    final ext = audioFile.path.toLowerCase().split('.').last;
    final mime = switch (ext) {
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'flac' => 'audio/flac',
      'm4a' => 'audio/mp4',
      _ => 'audio/wav',
    };
    final dataUri = 'data:$mime;base64,$base64Audio';

    final body = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_audio',
              'input_audio': dataUri,
            },
          ],
        },
      ],
    };

    final uri = Uri.parse('$baseUrl/chat/completions');
    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);

    final streamed = await _httpClient.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      debugPrint('BailianAsr HTTP ${response.statusCode}: ${response.body}');
      throw _apiError(response, '语音识别失败');
    }

    final data = _decodeJson(response.body);
    final text = _extractText(data).trim();
    if (text.isEmpty) {
      throw Exception('未识别到语音内容');
    }
    return text;
  }

  /// 从响应 JSON 中提取识别文本
  ///
  /// 百炼 ASR 有两种响应格式：
  /// A. 标准 OpenAI chat completion：choices[0].message.content
  /// B. 百炼特殊格式（multimodal-generation 风格）：
  ///    output.text 或 output.output.sentence.text
  String _extractText(Map<String, dynamic> data) {
    // A. 标准 OpenAI 格式
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final message = first['message'];
        if (message is Map<String, dynamic>) {
          final content = message['content'];
          if (content is String && content.isNotEmpty) return content;
          // content 也可能是数组（多模态返回）
          if (content is List) {
            for (final part in content) {
              if (part is Map<String, dynamic>) {
                final text = part['text'];
                if (text is String && text.isNotEmpty) return text;
                final audioText = part['audio'];
                // 某些情况 content 是 audio 类型，跳过
              }
            }
          }
        }
        // 某些 OpenAI 兼容 ASR 会直接把 text 放 message 同级
        final textAlt = first['text'];
        if (textAlt is String && textAlt.isNotEmpty) return textAlt;
      }
    }

    // B. 百炼特殊格式：output.text 或 output.output.sentence.text
    final output = data['output'];
    if (output is Map<String, dynamic>) {
      final text = output['text'];
      if (text is String && text.isNotEmpty) return text;
      final inner = output['output'];
      if (inner is Map<String, dynamic>) {
        final sentence = inner['sentence'];
        if (sentence is Map<String, dynamic>) {
          final st = sentence['text'];
          if (st is String && st.isNotEmpty) return st;
        }
        final innerText = inner['text'];
        if (innerText is String && innerText.isNotEmpty) return innerText;
      }
    }

    // 直接顶层 text（最小可能性）
    final text = data['text'];
    if (text is String && text.isNotEmpty) return text;

    // 找不到任何文本，把整个 response 打出来方便调试
    debugPrint('ASR 响应解析失败，完整响应: ${const JsonEncoder.withIndent('  ').convert(data)}');
    return '';
  }

  Map<String, dynamic> _decodeJson(String body) {
    final decoded = json.decode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('百炼返回了无效的 JSON 结构');
    }
    return decoded;
  }

  Exception _apiError(http.Response response, String fallback) {
    try {
      final data = _decodeJson(response.body);
      // 兼容 OpenAI 风格 {"error":{"code","message"}} 和顶层 {"code","message"}
      final err = data['error'];
      final map = err is Map<String, dynamic> ? err : data;
      final code = map['code']?.toString() ?? '';
      final message = map['message']?.toString() ?? '';
      if (message.isNotEmpty) {
        return Exception('$fallback [$code]: $message');
      }
    } catch (_) {
      // 非 JSON 错误体
    }
    return Exception('$fallback: HTTP ${response.statusCode} ${response.body}');
  }
}
