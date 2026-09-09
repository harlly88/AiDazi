import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'i18n.dart';
import 'storage.dart';
import 'asr_provider.dart';

/// 语音输入控制器（移动/桌面端实现）
///
/// 长按麦克风开始录音，松开后：
/// 停止录音 → 百炼 qwen3-asr 识别 → 返回文本（由调用方直接发送，无需确认）
class VoiceInputController {
  /// 16.3：qwen3-asr-flash 上限 60 秒，55 秒时提前自动封口，防止超限识别失败
  static const _maxDuration = Duration(seconds: 55);

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  DateTime? _startedAt;
  Timer? _maxTimer;

  /// 16.3：达到 55 秒上限后录音器已提前停止，这里缓存已完成的音频文件，
  /// 松手时 stopAndTranscribe 直接识别它（不丢音频、仍走正常发送流程）
  String? _maxStoppedPath;

  bool get isRecording => _isRecording;

  /// 开始录音（自动请求麦克风权限）
  Future<void> start() async {
    if (_isRecording) return;
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw Exception(I18n.t('mic_permission_denied'));
    }
    final dir = await getTemporaryDirectory();
    // 16.3：输出 wav（百炼 /audio/transcriptions 支持 WAV；aac/m4a 不在支持列表，
    // 与 asr_provider 的 filename 'audio.wav' / contentType audio/wav 保持一致）
    final path =
        '${dir.path}/aidazi_asr_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    _startedAt = DateTime.now();
    _maxStoppedPath = null;
    _isRecording = true;
    _maxTimer?.cancel();
    _maxTimer = Timer(_maxDuration, _stopAtMaxDuration);
  }

  /// 55 秒上限到达：提前停止录音器封口文件，保持 _isRecording 不变，
  /// 松手后照常走 stopAndTranscribe（提示由调用方显示，见 i18n record_max_duration）
  Future<void> _stopAtMaxDuration() async {
    if (!_isRecording) return;
    try {
      final path = await _recorder.stop();
      _maxStoppedPath = path;
      debugPrint('voice_input: ${I18n.t('record_max_duration')}');
    } catch (e) {
      debugPrint('voice_input: auto stop at max duration failed: $e');
    }
  }

  /// 停止录音并识别；取消或时长过短（<600ms）返回 null
  Future<String?> stopAndTranscribe() async {
    if (!_isRecording) return null;
    _isRecording = false;
    _maxTimer?.cancel();
    _maxTimer = null;
    // 16.3：55 秒已自动封口则直接用缓存文件，避免二次 stop 抛错/丢音频
    final path = _maxStoppedPath ?? await _recorder.stop();
    _maxStoppedPath = null;
    if (path == null) return null;

    try {
      if (_startedAt != null &&
          DateTime.now().difference(_startedAt!) <
              const Duration(milliseconds: 600)) {
        return null; // 误触：太短，直接丢弃
      }

      final apiKey = await getAliyunApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception(
            '未配置阿里云百炼 API Key，请先在 设置 → 模型配置 中选择千问模板并填入 API Key');
      }

      // 15.16：ASR 模型名从配置读取（默认 qwen3-asr-flash，可编辑）
      final asrModel = await getAsrModel();
      final client = BailianAsrClient(apiKey: apiKey, model: asrModel);
      return await client.transcribe(audioFile: File(path));
    } finally {
      await _deleteQuietly(path);
    }
  }

  /// 取消录音（丢弃音频，不识别）
  Future<void> cancel() async {
    if (!_isRecording) return;
    _isRecording = false;
    _maxTimer?.cancel();
    _maxTimer = null;
    final cached = _maxStoppedPath;
    _maxStoppedPath = null;
    try {
      final path = await _recorder.stop();
      if (path != null) await _deleteQuietly(path);
    } catch (_) {
      // 取消路径上的错误无需上报
    }
    if (cached != null) await _deleteQuietly(cached);
  }

  Future<void> dispose() async {
    _isRecording = false;
    _maxTimer?.cancel();
    _maxTimer = null;
    _maxStoppedPath = null;
    try {
      await _recorder.dispose();
    } catch (_) {
      // 释放失败可忽略
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 临时文件清理失败可忽略
    }
  }
}
