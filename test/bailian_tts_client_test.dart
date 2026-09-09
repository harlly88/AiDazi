import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aidazi/tts_provider.dart';

void main() {
  test('queries a voice registration status', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? submittedBody;
    String? path;
    String? authorization;

    final serverTask = () async {
      await for (final request in server) {
        authorization ??= request.headers.value(HttpHeaders.authorizationHeader);
        path = request.uri.path;
        submittedBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'request_id': 'req-query',
          'output': {
            'voice_id': 'cosyvoice-v3-flash-aidazi-abc123',
            'status': 'OK',
          },
        }));
        await request.response.close();
      }
    }();

    try {
      final client = BailianTtsClient(
        apiKey: 'test-key',
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      final status = await client
          .queryVoice('cosyvoice-v3-flash-aidazi-abc123');

      expect(status, 'OK');
      expect(authorization, 'Bearer test-key');
      expect(path, '/api/v1/services/audio/tts/customization');
      expect(submittedBody!['model'], 'voice-enrollment');
      final input = submittedBody!['input'] as Map<String, dynamic>;
      expect(input['action'], 'query_voice');
      expect(input['voice_id'], 'cosyvoice-v3-flash-aidazi-abc123');
    } finally {
      await server.close(force: true);
      await serverTask;
    }
  });

  test('synthesizes speech and returns the audio url', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? submittedBody;
    String? path;

    final serverTask = () async {
      await for (final request in server) {
        path = request.uri.path;
        submittedBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'request_id': 'req-synth',
          'output': {
            'audio': {'url': 'https://example.com/result.mp3'},
          },
        }));
        await request.response.close();
      }
    }();

    try {
      final client = BailianTtsClient(
        apiKey: 'test-key',
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      final url = await client.synthesize(
        voiceId: 'cosyvoice-v3-flash-aidazi-abc123',
        text: '今天天气怎么样？',
      );

      expect(url, 'https://example.com/result.mp3');
      expect(path, '/api/v1/services/audio/tts/SpeechSynthesizer');
      expect(submittedBody!['model'], 'cosyvoice-v3-flash');
      final input = submittedBody!['input'] as Map<String, dynamic>;
      expect(input['text'], '今天天气怎么样？');
      expect(input['voice'], 'cosyvoice-v3-flash-aidazi-abc123');
    } finally {
      await server.close(force: true);
      await serverTask;
    }
  });

  test('surfaces FAILED status from queryVoice', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    final serverTask = () async {
      await for (final request in server) {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'output': {
            'voice_id': 'cosyvoice-v3-flash-aidazi-bad',
            'status': 'FAILED',
          },
        }));
        await request.response.close();
      }
    }();

    try {
      final client = BailianTtsClient(
        apiKey: 'test-key',
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      final status = await client.queryVoice('cosyvoice-v3-flash-aidazi-bad');
      expect(status, 'FAILED');
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
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'code': 'InvalidApiKey',
          'message': 'Invalid API-key provided.',
        }));
        await request.response.close();
      }
    }();

    try {
      final client = BailianTtsClient(
        apiKey: 'bad-key',
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      await expectLater(
        client.synthesize(voiceId: 'v', text: 'hi'),
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
}
