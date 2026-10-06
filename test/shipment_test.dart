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

  AddPackageRequest addRequest() => const AddPackageRequest(
    eid: '018f00000000400080000000000000aa-S1',
    serviceType: '1',
    recName: 'Testovací Příjemce',
    recStreet: 'Psí 1',
    recCity: 'Praha',
    recZip: '11000',
    recCountry: Country.cz,
    recPhone: '+420777000000',
    recEmail: 'recipient@example.test',
    weight: 1.25,
    length: 30,
    width: 20,
    height: 10,
    price: 1990,
    codCurrency: Currency.czk,
  );

  group('addPackage', () {
    test('posts the package and returns the record', () async {
      final client = buildClient(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/ppl/add');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final packages = body['packages'] as List<dynamic>;
          expect(packages, hasLength(1));
          final package = packages.single as Map<String, dynamic>;
          expect(package['eid'], '018f00000000400080000000000000aa-S1');
          expect(package['service_type'], '1');
          expect(package['weight'], 1.25);
          expect(package['rec_name'], 'Testovací Příjemce');
          expect(package.containsKey('cod_price'), isFalse);
          expect(package.containsKey('vs'), isFalse);
          return jsonResponse({
            'status': 200,
            'packages': [
              {
                'eid': '018f00000000400080000000000000aa-S1',
                'status': 200,
                'package_id': 'add-ppl-1',
                'carrier_id': 'DR1536622512M',
                'label_url': 'https://pdf.balikobot.cz/label.pdf',
              },
            ],
          });
        }),
      );
      addTearDown(client.close);

      final result = await client.addPackage(Carrier.ppl, addRequest());

      expect(result.packageId, 'add-ppl-1');
      expect(result.carrierId, 'DR1536622512M');
      expect(result.labelUrl, 'https://pdf.balikobot.cz/label.pdf');
    });

    test('returns the original record for a duplicate EID', () async {
      final client = buildClient(
        MockClient(
          (request) async => jsonResponse({
            'status': 200,
            'packages': [
              {
                'eid': '018f00000000400080000000000000aa-S1',
                'status': 208,
                'package_id': 'add-ppl-original',
                'carrier_id': 'ORIGINAL-CARRIER',
                'label_url': 'https://pdf.balikobot.cz/label.pdf',
              },
            ],
          }),
        ),
      );
      addTearDown(client.close);

      final result = await client.addPackage(Carrier.ppl, addRequest());

      expect(result.packageId, 'add-ppl-original');
      expect(result.carrierId, 'ORIGINAL-CARRIER');
    });

    test('rejects an invalid request before the network', () async {
      var requested = false;
      final client = buildClient(
        MockClient((request) async {
          requested = true;
          return jsonResponse(<String, Object>{});
        }),
      );
      addTearDown(client.close);
      const invalid = AddPackageRequest(
        eid: '018f00000000400080000000000000aa-S1',
        serviceType: '1',
        recStreet: 'Psí 1',
        recCity: 'Praha',
        recZip: '11000',
        recCountry: Country.cz,
        recPhone: '+420777000000',
        weight: 1.25,
        length: 30,
        width: 20,
        height: 10,
        price: 1990,
        codCurrency: Currency.czk,
      );

      await expectLater(
        client.addPackage(Carrier.ppl, invalid),
        throwsA(
          isA<BalikobotException>().having(
            (error) => error.code,
            'code',
            BalikobotError.invalidRequest,
          ),
        ),
      );
      expect(requested, isFalse);
    });

    test('maps a 4xx to rejected', () async {
      final client = buildClient(
        MockClient(
          (request) async => http.Response(
            '{"status":400}',
            400,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.addPackage(Carrier.ppl, addRequest()),
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

  group('overview', () {
    test('returns valid entries and accepts an integer package id', () async {
      final client = buildClient(
        MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/ppl/overview');
          return jsonResponse({
            'status': 200,
            'packages': [
              {
                'eid': 'eid-1',
                'package_id': 'add-ppl-1',
                'carrier_id': 'C1',
                'label_url': 'https://pdf.balikobot.cz/a.pdf',
              },
              {
                'eid': 'legacy-eid',
                'package_id': 42,
                'carrier_id': 'C2',
                'label_url': 'https://pdf.balikobot.cz/b.pdf',
              },
            ],
          });
        }),
      );
      addTearDown(client.close);

      final packages = await client.overview(Carrier.ppl, 'eid-1');

      expect(packages, hasLength(2));
      expect(packages[0].eid, 'eid-1');
      expect(packages[0].packageId, 'add-ppl-1');
      expect(packages[1].eid, 'legacy-eid');
      expect(packages[1].packageId, '42');
    });

    test('skips an unrelated malformed entry', () async {
      final client = buildClient(
        MockClient(
          (request) async => jsonResponse({
            'status': 200,
            'packages': [
              {
                'eid': 'other',
                'package_id': 'p0',
                'carrier_id': 'C0',
                'label_url': 'https://evil.example/x.pdf',
              },
              {
                'eid': 'eid-1',
                'package_id': 'p1',
                'carrier_id': 'C1',
                'label_url': 'https://pdf.balikobot.cz/a.pdf',
              },
            ],
          }),
        ),
      );
      addTearDown(client.close);

      final packages = await client.overview(Carrier.ppl, 'eid-1');

      expect(packages, hasLength(1));
      expect(packages.single.packageId, 'p1');
    });

    test('fails on a malformed matching entry', () async {
      final client = buildClient(
        MockClient(
          (request) async => jsonResponse({
            'status': 200,
            'packages': [
              {
                'eid': 'eid-1',
                'package_id': 'p1',
                'carrier_id': 'C1',
                'label_url': 'https://evil.example/x.pdf',
              },
            ],
          }),
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.overview(Carrier.ppl, 'eid-1'),
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

  group('labels', () {
    test('returns the labels URL', () async {
      final client = buildClient(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/ppl/labels');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['package_ids'], ['add-ppl-1']);
          return jsonResponse({
            'status': 200,
            'labels_url': 'https://pdf.balikobot.cz/redownload.pdf',
          });
        }),
      );
      addTearDown(client.close);

      expect(
        await client.labels(Carrier.ppl, 'add-ppl-1'),
        'https://pdf.balikobot.cz/redownload.pdf',
      );
    });

    test('rejects a foreign label URL', () async {
      final client = buildClient(
        MockClient(
          (request) async => jsonResponse({
            'status': 200,
            'labels_url': 'https://evil.example/redownload.pdf',
          }),
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.labels(Carrier.ppl, 'add-ppl-1'),
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

  group('orderViewLabels', () {
    test('returns the order label URL', () async {
      final client = buildClient(
        MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/ppl/orderview/order-ppl-1');
          return jsonResponse({
            'status': 200,
            'order_id': 'order-ppl-1',
            'package_ids': ['add-ppl-other', 'add-ppl-1'],
            'labels_url': 'https://pdf.balikobot.cz/ordered.pdf',
          });
        }),
      );
      addTearDown(client.close);

      expect(
        await client.orderViewLabels(Carrier.ppl, 'order-ppl-1', 'add-ppl-1'),
        'https://pdf.balikobot.cz/ordered.pdf',
      );
    });

    test('rejects a package that is not a member', () async {
      final client = buildClient(
        MockClient(
          (request) async => jsonResponse({
            'status': 200,
            'order_id': 'order-ppl-1',
            'package_ids': ['add-ppl-other'],
            'labels_url': 'https://pdf.balikobot.cz/ordered.pdf',
          }),
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.orderViewLabels(Carrier.ppl, 'order-ppl-1', 'add-ppl-1'),
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

  group('downloadLabel', () {
    test('returns PDF bytes', () async {
      final pdf = utf8.encode('%PDF-1.4 fake label');
      final client = buildClient(
        MockClient((request) async {
          expect(request.headers['authorization'], isNull);
          expect(request.headers['accept'], isNull);
          return http.Response.bytes(
            pdf,
            200,
            headers: {'content-type': 'application/pdf'},
          );
        }),
      );
      addTearDown(client.close);

      final (bytes, mediaType) = await client.downloadLabel(
        'https://pdf.balikobot.cz/label.pdf',
      );

      expect(bytes, pdf);
      expect(mediaType, 'application/pdf');
    });

    test('rejects a wrong media type', () async {
      final client = buildClient(
        MockClient(
          (request) async => http.Response.bytes(
            utf8.encode('<html></html>'),
            200,
            headers: {'content-type': 'text/html'},
          ),
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.downloadLabel('https://pdf.balikobot.cz/label.pdf'),
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

  group('resolveBranchId', () {
    test('derives the carrier branch ids', () {
      expect(resolveBranchId(Carrier.cp, 'NP', 'ignored', '130 00'), '13000');
      expect(
        resolveBranchId(Carrier.ulozenka, 'CP_NP', 'ignored', '130 00'),
        '13000',
      );
      expect(resolveBranchId(Carrier.ppl, '1', 'KM123', ''), '123');
    });
  });
}
