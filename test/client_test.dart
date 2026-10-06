import 'package:balikobot_dart/balikobot_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  http.Client fakeHttpClient() =>
      MockClient((request) async => http.Response('', 200));

  BalikobotClient buildClient({
    String user = 'user',
    String apiKey = 'key',
    String baseUrl = 'https://apiv2.balikobot.cz',
    Duration timeout = const Duration(seconds: 30),
    int maxResponseBytes = 8 << 20,
    List<String> labelHosts = const [],
  }) {
    return BalikobotClient(
      Config(
        baseUrl: baseUrl,
        user: user,
        apiKey: apiKey,
        httpClient: fakeHttpClient(),
        timeout: timeout,
        maxResponseBytes: maxResponseBytes,
        labelHosts: labelHosts,
      ),
    );
  }

  group('BalikobotClient', () {
    test('builds from a valid config', () {
      final client = buildClient();
      expect(client, isA<BalikobotClient>());
      client.close();
    });

    test('accepts a loopback http base URL', () {
      final client = buildClient(baseUrl: 'http://127.0.0.1:8080');
      expect(client, isA<BalikobotClient>());
      client.close();
    });

    test('close is safe to call twice', () {
      final client = buildClient();
      client.close();
      client.close();
    });

    test('throws ArgumentError for an empty user', () {
      expect(() => buildClient(user: '  '), throwsArgumentError);
    });

    test('throws ArgumentError for a user over 100 bytes', () {
      expect(() => buildClient(user: 'a' * 101), throwsArgumentError);
    });

    test('throws ArgumentError for an empty API key', () {
      expect(() => buildClient(apiKey: ''), throwsArgumentError);
    });

    test('throws ArgumentError for an API key over 4096 bytes', () {
      expect(() => buildClient(apiKey: 'k' * 4097), throwsArgumentError);
    });

    test('throws ArgumentError for a negative timeout', () {
      expect(
        () => buildClient(timeout: const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for a negative response limit', () {
      expect(() => buildClient(maxResponseBytes: -1), throwsArgumentError);
    });

    test('throws ArgumentError for a response limit over 1 GiB', () {
      expect(
        () => buildClient(maxResponseBytes: (1 << 30) + 1),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for a relative base URL', () {
      expect(
        () => buildClient(baseUrl: 'apiv2.balikobot.cz'),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for an http non-loopback base URL', () {
      expect(
        () => buildClient(baseUrl: 'http://example.com'),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for a bad label host', () {
      expect(
        () => buildClient(labelHosts: const ['pdf.balikobot.cz/labels']),
        throwsArgumentError,
      );
    });
  });
}
