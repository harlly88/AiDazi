/// 语音输入控制器（Web 占位实现）
///
/// Web 端录音走 MediaRecorder + Blob，暂不接入；
/// 长按麦克风按钮会提示平台不支持。
class VoiceInputController {
  bool get isRecording => false;

  Future<void> start() async {
    throw Exception('当前平台暂不支持语音输入');
  }

  Future<String?> stopAndTranscribe() async => null;

  Future<void> cancel() async {}

  Future<void> dispose() async {}
}
