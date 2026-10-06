import 'dart:convert';

import 'package:balikobot_dart/balikobot_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  BalikobotClient buildClient(MockClient httpClient) => BalikobotClient(
    Config(user: 'user', apiKey: 'key', httpClient: httpClient),
  );

  http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  group('branches', () {
    test('returns branches from an array payload', () async {
      final client = buildClient(
        MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/ppl/branches/service/1/country/CZ');
          expect(request.headers['accept'], 'application/json');
          return jsonResponse({
            'status': 200,
            'branches': [
              {
                'branch_id': '123',
                'type': 'branch',
                'name': 'PPL Pickup Praha',
                'street': 'Psí 1',
                'city': 'Praha',
                'zip': '11000',
                'country': 'CZ',
                'lat': 50.0755,
                'lng': 14.4378,
              },
              {
                'id': 456,
                'name': 'PPL Pickup Brno',
                'street': 'Veterinární 2',
                'city': 'Brno',
                'zip': '60200',
              },
            ],
          });
        }),
      );
      addTearDown(client.close);

      final branches = await client.branches(Carrier.ppl, '1', Country.cz);

      expect(branches, hasLength(2));
      expect(branches[0].id, '123');
      expect(branches[0].type, 'branch');
      expect(branches[0].name, 'PPL Pickup Praha');
      expect(branches[0].street, 'Psí 1');
      expect(branches[0].city, 'Praha');
      expect(branches[0].zip, '11000');
      expect(branches[0].country, Country.cz);
      expect(branches[0].latitude, 50.0755);
      expect(branches[0].longitude, 14.4378);
      expect(branches[1].id, '456');
      expect(branches[1].country.value, isEmpty);
      expect(branches[1].latitude, isNull);
      expect(branches[1].longitude, isNull);
    });

    test('returns an object payload in numeric key order', () async {
      final client = buildClient(
        MockClient(
          (request) async => jsonResponse({
            'status': '200',
            'branches': {
              '1a': {
                'id': 'non-numeric',
                'name': 'Pobočka C',
                'zip': '13000',
                'country': 'CZ',
              },
              '10': {
                'id': 'ten',
                'name': 'Pobočka B',
                'zip': '12000',
                'country': 'CZ',
              },
              '2': {
                'id': 'two',
                'name': 'Pobočka A',
                'zip': '11000',
                'country': 'CZ',
              },
            },
          }),
        ),
      );
      addTearDown(client.close);

      final branches = await client.branches(Carrier.ppl, '1', Country.cz);

      expect(branches.map((branch) => branch.id), [
        'two',
        'ten',
        'non-numeric',
      ]);
    });

    test('falls back to the zip and drops a different country', () async {
      final client = buildClient(
        MockClient((request) async {
          expect(request.url.path, '/cp/branches/service/NP/country/CZ');
          return jsonResponse({
            'status': 200,
            'branches': [
              {
                'id': '1',
                'street': 'Psí 1',
                'city': 'Praha',
                'zip': '11000',
                'country': 'CZ',
              },
              {
                'id': '2',
                'name': 'Balíkovna Bratislava',
                'street': 'Psí 2',
                'city': 'Bratislava',
                'zip': '81101',
                'country': 'SK',
              },
            ],
          });
        }),
      );
      addTearDown(client.close);

      final branches = await client.branches(Carrier.cp, 'NP', Country.cz);

      expect(branches, hasLength(1));
      expect(branches.first.id, '1');
      expect(branches.first.name, '11000');
    });

    test('maps a server error to unavailable', () async {
      final client = buildClient(
        MockClient((request) async => http.Response('', 500)),
      );
      addTearDown(client.close);

      await expectLater(
        client.branches(Carrier.ppl, '1', Country.cz),
        throwsA(
          isA<BalikobotException>().having(
            (error) => error.code,
            'code',
            BalikobotError.unavailable,
          ),
        ),
      );
    });

    test('maps an oversized response to unavailable', () async {
      final client = BalikobotClient(
        Config(
          user: 'user',
          apiKey: 'key',
          httpClient: MockClient(
            (request) async => http.Response(
              'x' * 300,
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
          maxResponseBytes: 256,
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.branches(Carrier.ppl, '1', Country.cz),
        throwsA(
          isA<BalikobotException>().having(
            (error) => error.code,
            'code',
            BalikobotError.unavailable,
          ),
        ),
      );
    });

    test('maps a malformed status to invalidResponse', () async {
      final client = buildClient(
        MockClient(
          (request) async =>
              jsonResponse({'status': 'OK', 'branches': <Object>[]}),
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.branches(Carrier.ppl, '1', Country.cz),
        throwsA(
          isA<BalikobotException>().having(
            (error) => error.code,
            'code',
            BalikobotError.invalidResponse,
          ),
        ),
      );
    });
  });
}
