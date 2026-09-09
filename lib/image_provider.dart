import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'storage.dart';

/// 阿里云百炼 万相2.7 文生图客户端（同步调用）
///
/// - 端点：POST /api/v1/services/aigc/multimodal-generation/generation
/// - 模型：wan2.7-image / wan2.7-image-pro（模型名可在模型配置页修改）
/// - 文生图：content 仅含 text；图生图（参考图）：content 附带 image（Base64 data URI 直传，无需 OSS）
/// - 鉴权：Bearer API Key（与千问对话共用 getAliyunApiKey）
class WanxImageClient {
  final String apiKey;
  final String baseUrl;
  final http.Client _httpClient;

  WanxImageClient({
    required this.apiKey,
    this.baseUrl = 'https://dashscope.aliyuncs.com',
    http.Client? httpClient,
  })  : _httpClient = httpClient ?? http.Client(),
        assert(apiKey.isNotEmpty, 'API key cannot be empty');

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

  /// 生成图片，返回图片 URL（百炼临时 URL，24 小时有效，调用方需下载到本地）
  ///
  /// [prompt] 生图提示词（含角色外貌描述）
  /// [model] 模型名（从模型配置读取，默认 wan2.7-image）
  /// [size] 分辨率，如 1080*1920（9:16 竖版）
  /// [refImage] 参考图 data URI（Base64 直传，万相自动识别），为空则纯文生图
  Future<String> generateImage({
    required String prompt,
    String model = 'wan2.7-image',
    String size = '1080*1920',
    String? refImage,
  }) async {
    if (prompt.trim().isEmpty) {
      throw ArgumentError('生图提示词不能为空');
    }

    final content = <Map<String, String>>[
      {'text': prompt.trim()},
    ];
    if (refImage != null && refImage.trim().isNotEmpty) {
      content.add({'image': refImage.trim()});
    }

    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/api/v1/services/aigc/multimodal-generation/generation'),
          headers: _headers,
          body: json.encode({
            'model': model,
            'input': {
              'messages': [
                {
                  'role': 'user',
                  'content': content,
                }
              ],
            },
            'parameters': {
              'size': size,
              'n': 1,
              'watermark': false,
            },
          }),
        )
        .timeout(const Duration(minutes: 5));

    if (response.statusCode != 200) {
      throw _apiError(response, '文生图失败');
    }

    final data = _decodeObject(response.body);
    final choices = data['output']?['choices'];
    if (choices is List && choices.isNotEmpty) {
      final contents = choices[0]['message']?['content'];
      if (contents is List) {
        for (final item in contents) {
          if (item is Map<String, dynamic> && item['image'] != null) {
            final url = item['image'].toString();
            if (url.isNotEmpty) return url;
          }
        }
      }
    }
    throw Exception('百炼未返回图片 URL: ${response.body}');
  }

  static Map<String, dynamic> _decodeObject(String body) {
    final decoded = json.decode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('百炼返回了无效的 JSON 结构');
    }
    return decoded;
  }

  Exception _apiError(http.Response response, String fallback) {
    try {
      final data = _decodeObject(response.body);
      final code = data['code']?.toString() ?? '';
      final message = data['message']?.toString() ?? '';
      if (message.isNotEmpty) {
        return Exception('$fallback [$code]: $message');
      }
    } catch (_) {
      // 非 JSON 错误体，直接用 fallback
    }
    return Exception('$fallback: HTTP ${response.statusCode}');
  }
}

/// 参考图本地字节 → data URI（15.12 Base64 直传，替代 OSS 签名 URL）
///
/// 万相 image 参数原生支持 data:image/{png|jpeg|webp};base64,... 输入。
/// Base64 后体积 +33%，请求体上限 20MB → 原始字节按 15MB 校验。
String? encodeRefImageDataUri(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  if (bytes.length > 15 * 1024 * 1024) {
    throw Exception(
        '参考图过大（${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB），'
        'Base64 直传上限约 15MB，请压缩后重试');
  }
  String mime = 'image/png';
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    mime = 'image/png'; // PNG
  } else if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    mime = 'image/jpeg'; // JPEG
  } else if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    mime = 'image/webp'; // RIFF....WEBP
  }
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

/// 便捷入口：读取配置并生成图片
///
/// [refImageBytes] 本地参考图字节（Base64 直传，15.12 移除 OSS）；
/// 为空或读取失败时自动降级为纯文生图（prompt 中已含角色外貌描述）
Future<String> generateWanxImage({
  required String prompt,
  Uint8List? refImageBytes,
}) async {
  final apiKey = await getAliyunApiKey();
  if (apiKey == null || apiKey.isEmpty) {
    throw Exception('未配置阿里云百炼 API Key，请先在 设置 → 模型配置 中配置');
  }
  final (model, size) = await getWanImageConfig();

  final client = WanxImageClient(apiKey: apiKey);
  return client.generateImage(
    prompt: prompt,
    model: model,
    size: size,
    refImage: encodeRefImageDataUri(refImageBytes),
  );
}
