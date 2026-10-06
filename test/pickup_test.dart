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

  PickupRequest pickupRequest() => const PickupRequest(
    date: '2026-09-14',
    weightKg: 12.5,
    packageCount: 3,
    note: 'Zazvoňte u skladu.',
  );

  group('orderPickup', () {
    test('books a DPD collection without a confirmation field', () async {
      final client = buildClient(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/dpdcz/orderpickup');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body, {
            'date': '2026-09-14',
            'weight': 12.5,
            'package_count': 3,
            'message': 'Zazvoňte u skladu.',
          });
          return jsonResponse({'status': '200'});
        }),
      );
      addTearDown(client.close);

      final result = await client.orderPickup(Carrier.dpdcz, pickupRequest());

      expect(result.confirmed, isTrue);
      expect(result.providerId, isEmpty);
    });

    test('preserves the PPL confirmation', () async {
      final client = buildClient(
        MockClient((request) async {
          expect(request.url.path, '/ppl/orderpickup');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body, {'date': '2026-09-14', 'note': 'Zazvoňte u skladu.'});
          return jsonResponse({
            'status': 200,
            'pickup_order_id': 'BB12345600152024001',
            'confirmed': true,
          });
        }),
      );
      addTearDown(client.close);

      final result = await client.orderPickup(Carrier.ppl, pickupRequest());

      expect(result.confirmed, isTrue);
      expect(result.providerId, 'BB12345600152024001');
    });

    test('rejects an unsupported carrier before the network', () async {
      var requested = false;
      final client = buildClient(
        MockClient((request) async {
          requested = true;
          return jsonResponse({'status': 200});
        }),
      );
      addTearDown(client.close);

      await expectLater(
        client.orderPickup(Carrier.gls, pickupRequest()),
        throwsA(
          isA<BalikobotException>().having(
            (error) => error.code,
            'code',
            BalikobotError.rejected,
          ),
        ),
      );
      expect(requested, isFalse);
    });

    test('maps a PPL response without confirmation to ambiguous', () async {
      final client = buildClient(
        MockClient(
          (request) async =>
              jsonResponse({'status': 200, 'pickup_order_id': 'BB123'}),
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.orderPickup(Carrier.ppl, pickupRequest()),
        throwsA(
          isA<BalikobotException>().having(
            (error) => error.code,
            'code',
            BalikobotError.ambiguous,
          ),
        ),
      );
    });
  });
}
