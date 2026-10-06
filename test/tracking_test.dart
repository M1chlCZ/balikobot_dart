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

  group('trackStatus', () {
    test('returns the latest provider status', () async {
      final client = buildClient(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/ppl/trackstatus');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['carrier_ids'], ['TRACK-1']);
          return jsonResponse({
            'status': 200,
            'packages': [
              {
                'carrier_id': 'TRACK-1',
                'status_id': 1,
                'status_id_v2': 1.2,
                'name': 'Zásilka byla doručena příjemci.',
              },
            ],
          });
        }),
      );
      addTearDown(client.close);

      final result = await client.trackStatus(Carrier.ppl, 'TRACK-1');

      expect(result.statusId, '1.2');
      expect(result.statusText, 'Zásilka byla doručena příjemci.');
    });

    test('maps an http 404 to notFound', () async {
      final client = buildClient(
        MockClient((request) async => http.Response('{}', 404)),
      );
      addTearDown(client.close);

      await expectLater(
        client.trackStatus(Carrier.ppl, 'TRACK-1'),
        throwsA(
          isA<BalikobotException>().having(
            (error) => error.code,
            'code',
            BalikobotError.notFound,
          ),
        ),
      );
    });

    test('rejects an entry with a foreign carrier id', () async {
      final client = buildClient(
        MockClient(
          (request) async => jsonResponse({
            'status': 200,
            'packages': [
              {
                'carrier_id': 'OTHER',
                'status_id': 1,
                'name': 'Delivered',
                'status': 200,
              },
            ],
          }),
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.trackStatus(Carrier.ppl, 'TRACK-1'),
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

  group('orderBatch', () {
    test('returns the provider order id', () async {
      final client = buildClient(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/ppl/order');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['package_ids'], ['add-ppl-1']);
          return jsonResponse({'status': 200, 'order_id': 'order-ppl-2274514'});
        }),
      );
      addTearDown(client.close);

      final result = await client.orderBatch(Carrier.ppl, 'add-ppl-1');

      expect(result.orderId, 'order-ppl-2274514');
    });

    test('returns the original order id for a 208 replay', () async {
      final client = buildClient(
        MockClient(
          (request) async =>
              jsonResponse({'status': 208, 'order_id': 'order-ppl-2274514'}),
        ),
      );
      addTearDown(client.close);

      final result = await client.orderBatch(Carrier.ppl, 'add-ppl-1');

      expect(result.orderId, 'order-ppl-2274514');
    });

    test('maps a body status 400 to rejected', () async {
      final client = buildClient(
        MockClient((request) async => jsonResponse({'status': 400})),
      );
      addTearDown(client.close);

      await expectLater(
        client.orderBatch(Carrier.ppl, 'add-ppl-1'),
        throwsA(
          isA<BalikobotException>().having(
            (error) => error.code,
            'code',
            BalikobotError.rejected,
          ),
        ),
      );
    });
  });

  group('dropPackage', () {
    test('treats a body status 404 as success', () async {
      final client = buildClient(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/ppl/drop');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['package_ids'], ['add-ppl-1']);
          return jsonResponse({'status': 404});
        }),
      );
      addTearDown(client.close);

      await client.dropPackage(Carrier.ppl, 'add-ppl-1');
    });

    test('maps a body status 405 to rejected', () async {
      final client = buildClient(
        MockClient((request) async => jsonResponse({'status': 405})),
      );
      addTearDown(client.close);

      await expectLater(
        client.dropPackage(Carrier.ppl, 'add-ppl-1'),
        throwsA(
          isA<BalikobotException>().having(
            (error) => error.code,
            'code',
            BalikobotError.rejected,
          ),
        ),
      );
    });
  });
}
