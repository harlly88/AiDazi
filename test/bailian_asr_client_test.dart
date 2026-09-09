import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aidazi/asr_provider.dart';

void main() {
  // 生成临时录音文件（wav，任意字节即可测试格式）
  Future<File> createAudioFixture() async {
    final dir = await Directory.systemTemp.createTemp('aidazi_asr_test');
    final file = File('${dir.path}/voice.wav');
    await file.writeAsBytes(List.filled(128, 0));
    return file;
  }

  test('transcribes via chat/completions + input_audio base64', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? path;
    String? authorization;
    String? contentType;
    Map<String, dynamic>? parsedBody;

    final serverTask = () async {
      await for (final request in server) {
        path = request.uri.path;
        authorization =
            request.headers.value(HttpHeaders.authorizationHeader);
        contentType = request.headers.contentType?.toString();

        final raw = await utf8.decoder.bind(request).join();
        parsedBody = json.decode(raw) as Map<String, dynamic>;

        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '今天天气怎么样？',
              },
            },
          ],
        }));
        await request.response.close();
      }
    }();

    try {
      final audio = await createAudioFixture();
      final client = BailianAsrClient(
        apiKey: 'test-key',
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      final text = await client.transcribe(audioFile: audio);

      expect(text, '今天天气怎么样？');
      expect(path, '/chat/completions');
      expect(authorization, 'Bearer test-key');
      expect(contentType, contains('application/json'));

      // 验证请求体结构
      expect(parsedBody!['model'], 'qwen3-asr-flash');
      final messages = parsedBody!['messages'] as List;
      expect(messages, hasLength(1));
      final userMsg = messages.first as Map<String, dynamic>;
      expect(userMsg['role'], 'user');
      final content = userMsg['content'] as List;
      expect(content, hasLength(1));
      final audioPart = content.first as Map<String, dynamic>;
      expect(audioPart['type'], 'input_audio');
      final inputAudio = audioPart['input_audio'] as String;
      expect(inputAudio, startsWith('data:audio/wav;base64,'));
    } finally {
      await server.close(force: true);
      await serverTask;
    }
  });

  test('handles Bailian special response format (output.text)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    final serverTask = () async {
      await for (final request in server) {
        // 百炼特殊格式：顶层 output.text
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'output': {
            'text': '你好世界',
          },
        }));
        await request.response.close();
      }
    }();

    try {
      final audio = await createAudioFixture();
      final client = BailianAsrClient(
        apiKey: 'test-key',
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      final text = await client.transcribe(audioFile: audio);
      expect(text, '你好世界');
    } finally {
      await server.close(force: true);
      await serverTask;
    }
  });

  test('handles Bailian nested sentence.text format', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    final serverTask = () async {
      await for (final request in server) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'output': {
            'output': {
              'sentence': {
                'text': '嵌套格式也能识别',
              },
            },
          },
        }));
        await request.response.close();
      }
    }();

    try {
      final audio = await createAudioFixture();
      final client = BailianAsrClient(
        apiKey: 'test-key',
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      final text = await client.transcribe(audioFile: audio);
      expect(text, '嵌套格式也能识别');
    } finally {
      await server.close(force: true);
      await serverTask;
    }
  });

  test('surfaces DashScope error messages', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    final serverTask = () async {
      await for (final request in server) {
        await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'code': 'InvalidApiKey',
          'message': 'Invalid API-key provided.',
        }));
        await request.response.close();
      }
    }();

    try {
      final audio = await createAudioFixture();
      final client = BailianAsrClient(
        apiKey: 'bad-key',
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      await expectLater(
        client.transcribe(audioFile: audio),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Invalid API-key provided.'),
        )),
      );
    } finally {
      await server.close(force: true);
      await serverTask;
    }
  });

  test('rejects missing audio file', () async {
    final client = BailianAsrClient(apiKey: 'test-key');
    await expectLater(
      client.transcribe(
        audioFile: File('/nonexistent/voice.wav'),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
