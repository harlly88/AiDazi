import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'image_provider.dart' show encodeRefImageDataUri;
import 'storage.dart';

/// 阿里云百炼 万相2.7 视频生成客户端（异步：创建任务 → 轮询获取）
///
/// - 创建任务：POST /api/v1/services/aigc/video-generation/video-synthesis
///   请求头必须带 X-DashScope-Async: enable
/// - 轮询任务：GET /api/v1/tasks/{task_id}
///   task_status: PENDING / RUNNING / SUCCEEDED / FAILED
/// - 鉴权：Bearer API Key（与千问对话共用 getAliyunApiKey）
/// - 轮询策略：初始 2s，指数退避至 30s 封顶，单任务最长 15 分钟（带取消）
/// - 模型名从模型配置读取（15.16，默认 wan2.7-t2v，可改 wan2.7-i2v 等）
/// - 参考图/首帧图 Base64 直传（15.12 移除 OSS）：传入 [refImage] 时走图生视频
class WanxVideoClient {
  final String apiKey;
  final String baseUrl;
  final http.Client _httpClient;

  WanxVideoClient({
    required this.apiKey,
    this.baseUrl = 'https://dashscope.aliyuncs.com',
    http.Client? httpClient,
  })  : _httpClient = httpClient ?? http.Client(),
        assert(apiKey.isNotEmpty, 'API key cannot be empty');

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

  /// 生成视频，阻塞轮询直至完成，返回视频 URL（24 小时有效，调用方需下载到本地）
  ///
  /// [prompt] 视频提示词（中英文均可）
  /// [model] 模型名（从模型配置读取，默认 wan2.7-t2v）
  /// [refImage] 首帧图 data URI（Base64 直传，15.12）：非空时自动切 i2v 模型
  /// [resolution] 720P / 1080P
  /// [ratio] 画面比例：16:9 / 9:16 / 1:1 / 4:3 / 3:4
  /// [duration] 时长（秒），2-15 的整数，按秒计费
  Future<String> generateVideo({
    required String prompt,
    String model = 'wan2.7-t2v',
    String? refImage,
    String resolution = '720P',
    String ratio = '9:16',
    int duration = 5,
    Duration timeout = const Duration(minutes: 15),
  }) async {
    if (prompt.trim().isEmpty) {
      throw ArgumentError('视频提示词不能为空');
    }
    // 图生视频：t2v 模型名按命名约定切换为 i2v（wan2.7-t2v → wan2.7-i2v）
    String actualModel = model;
    if (refImage != null && refImage.trim().isNotEmpty) {
      actualModel = model.endsWith('-t2v')
          ? '${model.substring(0, model.length - 4)}-i2v'
          : model;
    }
    final taskId = await _createTask(
      prompt: prompt,
      model: actualModel,
      refImage: refImage,
      resolution: resolution,
      ratio: ratio,
      duration: duration,
    );
    return _waitForVideo(taskId, timeout: timeout);
  }

  Future<String> _createTask({
    required String prompt,
    required String model,
    required String resolution,
    required String ratio,
    required int duration,
    String? refImage,
  }) async {
    final hasRefImage = refImage != null && refImage.trim().isNotEmpty;
    final input = <String, dynamic>{
      'prompt': prompt.trim(),
    };
    if (hasRefImage) {
      input['img_url'] = refImage.trim(); // data URI，万相自动识别
    }
    final parameters = <String, dynamic>{
      'resolution': resolution,
      'duration': duration,
      'prompt_extend': true,
    };
    if (!hasRefImage) {
      parameters['ratio'] = ratio; // i2v 画面比例跟随首帧图
    }
    final response = await _httpClient
        .post(
          Uri.parse(
              '$baseUrl/api/v1/services/aigc/video-generation/video-synthesis'),
          headers: {..._headers, 'X-DashScope-Async': 'enable'},
          body: json.encode({
            'model': model,
            'input': input,
            'parameters': parameters,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw _apiError(response, '视频任务创建失败');
    }

    final data = _decodeObject(response.body);
    final taskId = data['output']?['task_id']?.toString();
    if (taskId == null || taskId.isEmpty) {
      throw Exception('百炼未返回 task_id: ${response.body}');
    }
    return taskId;
  }

  /// 查询单次任务状态，返回 (task_status, video_url)
  Future<(String, String?)> queryTask(String taskId) async {
    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/api/v1/tasks/$taskId'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw _apiError(response, '视频任务查询失败');
    }
    final data = _decodeObject(response.body);
    final status = data['output']?['task_status']?.toString() ?? '';
    final videoUrl = data['output']?['video_url']?.toString();
    return (status, videoUrl);
  }

  Future<String> _waitForVideo(
    String taskId, {
    required Duration timeout,
  }) async {
    final startedAt = DateTime.now();
    var delay = const Duration(seconds: 2);
    while (DateTime.now().difference(startedAt) < timeout) {
      final (status, videoUrl) = await queryTask(taskId);
      if (status == 'SUCCEEDED') {
        if (videoUrl != null && videoUrl.isNotEmpty) return videoUrl;
        throw Exception('视频任务成功但未返回 URL（task_id: $taskId）');
      }
      if (status == 'FAILED' || status == 'CANCELED' || status == 'UNKNOWN') {
        throw Exception('视频生成失败（task_id: $taskId, status: $status）');
      }
      await Future.delayed(delay);
      // 指数退避，30s 封顶
      delay = delay * 2;
      if (delay > const Duration(seconds: 30)) {
        delay = const Duration(seconds: 30);
      }
    }
    throw TimeoutException('视频生成超时（task_id: $taskId）');
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

/// 便捷入口：读取配置并生成视频
///
/// [refImageBytes] 首帧图本地字节（15.12 Base64 直传，替代 OSS）：
/// 非空时走图生视频（i2v），为空则纯文生视频（t2v）
Future<String> generateWanxVideo({
  required String prompt,
  Uint8List? refImageBytes,
}) async {
  final apiKey = await getAliyunApiKey();
  if (apiKey == null || apiKey.isEmpty) {
    throw Exception('未配置阿里云百炼 API Key，请先在 设置 → 模型配置 中配置');
  }
  final model = await getVideoModel(); // 15.16：模型名可编辑，默认 wan2.7-t2v
  final (resolution, ratio, duration) = await getWanVideoConfig();
  final client = WanxVideoClient(apiKey: apiKey);
  return client.generateVideo(
    prompt: prompt,
    model: model,
    refImage: encodeRefImageDataUri(refImageBytes),
    resolution: resolution,
    ratio: ratio,
    duration: duration,
  );
}
