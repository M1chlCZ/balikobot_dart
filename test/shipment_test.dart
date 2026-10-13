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

  group('downloadBatchLabels', () {
    test('returns a single PDF label', () async {
      final pdf = utf8.encode('%PDF-1.4 single label');
      final client = buildClient(
        MockClient((request) async {
          if (request.method == 'POST') {
            expect(request.url.path, '/ppl/labels');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['package_ids'], ['add-ppl-1']);
            return jsonResponse({
              'status': 200,
              'labels_url': 'https://pdf.balikobot.cz/labels.bin',
            });
          }
          expect(request.method, 'GET');
          expect(request.url.path, '/labels.bin');
          expect(request.headers['authorization'], isNull);
          return http.Response.bytes(
            pdf,
            200,
            headers: {'content-type': 'application/pdf'},
          );
        }),
      );
      addTearDown(client.close);

      final (bytes, mediaType) = await client.downloadBatchLabels(
        Carrier.ppl,
        const ['add-ppl-1'],
      );

      expect(bytes, pdf);
      expect(mediaType, 'application/pdf');
    });

    test('returns a ZIP archive for several packages', () async {
      final archive = utf8.encode('PK\x03\x04zip archive bytes');
      final client = buildClient(
        MockClient((request) async {
          if (request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['package_ids'], ['add-ppl-1', 'add-ppl-2']);
            return jsonResponse({
              'status': 200,
              'labels_url': 'https://pdf.balikobot.cz/labels.bin',
            });
          }
          return http.Response.bytes(
            archive,
            200,
            headers: {'content-type': 'application/zip'},
          );
        }),
      );
      addTearDown(client.close);

      final (bytes, mediaType) = await client.downloadBatchLabels(
        Carrier.ppl,
        const ['add-ppl-1', 'add-ppl-2'],
      );

      expect(bytes, archive);
      expect(mediaType, 'application/zip');
    });

    test('accepts ZPL for a single package', () async {
      final zpl = utf8.encode('^XA^FO50,50^FDLABEL^FS^XZ');
      final client = buildClient(
        MockClient((request) async {
          if (request.method == 'POST') {
            return jsonResponse({
              'status': 200,
              'labels_url': 'https://pdf.balikobot.cz/labels.bin',
            });
          }
          return http.Response.bytes(
            zpl,
            200,
            headers: {'content-type': 'application/zpl'},
          );
        }),
      );
      addTearDown(client.close);

      final (bytes, mediaType) = await client.downloadBatchLabels(
        Carrier.ppl,
        const ['add-ppl-1'],
      );

      expect(bytes, zpl);
      expect(mediaType, 'application/zpl');
    });

    test('rejects invalid input before the network', () async {
      var requests = 0;
      final client = buildClient(
        MockClient((request) async {
          requests++;
          return jsonResponse(<String, Object>{});
        }),
      );
      addTearDown(client.close);
      final tooMany = <String>[
        for (var index = 0; index <= 1000; index++) 'add-ppl-$index',
      ];
      final cases = <(String, Carrier, List<String>)>[
        ('missing ids', Carrier.ppl, const []),
        ('empty id', Carrier.ppl, const ['']),
        ('invalid id', Carrier.ppl, const ['bad\nid']),
        ('invalid carrier', const Carrier('PPL'), const ['add-ppl-1']),
        ('too many ids', Carrier.ppl, tooMany),
      ];
      for (final (name, carrier, packageIds) in cases) {
        await expectLater(
          client.downloadBatchLabels(carrier, packageIds),
          throwsA(
            isA<BalikobotException>().having(
              (error) => error.code,
              'code',
              BalikobotError.invalidRequest,
            ),
          ),
          reason: name,
        );
      }
      expect(requests, 0);
    });

    test('classifies the lookup response', () async {
      final cases =
          <
            ({
              String name,
              int statusCode,
              String? retryAfter,
              String contentType,
              String body,
              BalikobotError code,
              Duration? hint,
            })
          >[
            (
              name: 'http rate limit is transient with the Retry-After hint',
              statusCode: 429,
              retryAfter: '30',
              contentType: 'application/json',
              body: '{}',
              code: BalikobotError.unavailable,
              hint: const Duration(seconds: 30),
            ),
            (
              name: 'http server error is transient',
              statusCode: 500,
              retryAfter: null,
              contentType: 'application/json',
              body: '{}',
              code: BalikobotError.unavailable,
              hint: null,
            ),
            (
              name: 'http validation is rejected',
              statusCode: 400,
              retryAfter: null,
              contentType: 'application/json',
              body: '{}',
              code: BalikobotError.rejected,
              hint: null,
            ),
            (
              name: 'body 503 is transient',
              statusCode: 200,
              retryAfter: null,
              contentType: 'application/json',
              body: '{"status":503}',
              code: BalikobotError.unavailable,
              hint: null,
            ),
            (
              name: 'body 404 is rejected',
              statusCode: 200,
              retryAfter: null,
              contentType: 'application/json',
              body: '{"status":404}',
              code: BalikobotError.rejected,
              hint: null,
            ),
            (
              name: 'missing status is a protocol error',
              statusCode: 200,
              retryAfter: null,
              contentType: 'application/json',
              body: '{"labels_url":"https://pdf.balikobot.cz/labels.bin"}',
              code: BalikobotError.invalidResponse,
              hint: null,
            ),
            (
              name: 'non JSON body is a protocol error',
              statusCode: 200,
              retryAfter: null,
              contentType: 'text/html',
              body: '<html></html>',
              code: BalikobotError.invalidResponse,
              hint: null,
            ),
            (
              name: 'foreign label host is a protocol error',
              statusCode: 200,
              retryAfter: null,
              contentType: 'application/json',
              body: '{"status":200,"labels_url":"https://evil.example/labels.pdf"}',
              code: BalikobotError.invalidResponse,
              hint: null,
            ),
          ];
      for (final testCase in cases) {
        var requests = 0;
        final client = buildClient(
          MockClient((request) async {
            requests++;
            final headers = <String, String>{
              'content-type': testCase.contentType,
            };
            final retryAfter = testCase.retryAfter;
            if (retryAfter != null) {
              headers['retry-after'] = retryAfter;
            }
            return http.Response(
              testCase.body,
              testCase.statusCode,
              headers: headers,
            );
          }),
        );
        addTearDown(client.close);

        await expectLater(
          client.downloadBatchLabels(Carrier.ppl, const ['add-ppl-1']),
          throwsA(
            isA<BalikobotException>()
                .having((error) => error.code, 'code', testCase.code)
                .having(
                  (error) => error.retryAfter,
                  'retryAfter',
                  testCase.hint,
                ),
          ),
          reason: testCase.name,
        );
        expect(requests, 1, reason: testCase.name);
      }
    });

    test('validates the downloaded label', () async {
      final cases =
          <
            ({
              String name,
              List<String> ids,
              int statusCode,
              String contentType,
              String body,
              BalikobotError? code,
              String mediaType,
            })
          >[
            (
              name: 'single PDF',
              ids: ['add-ppl-1'],
              statusCode: 200,
              contentType: 'application/pdf',
              body: '%PDF-1.4 label',
              code: null,
              mediaType: 'application/pdf',
            ),
            (
              name: 'single ZPL',
              ids: ['add-ppl-1'],
              statusCode: 200,
              contentType: 'application/zpl',
              body: '^XA^XZ',
              code: null,
              mediaType: 'application/zpl',
            ),
            (
              name: 'several packages return ZIP',
              ids: ['add-ppl-1', 'add-ppl-2'],
              statusCode: 200,
              contentType: 'application/zip',
              body: 'PK\x03\x04archive',
              code: null,
              mediaType: 'application/zip',
            ),
            (
              name: 'single package rejects ZIP',
              ids: ['add-ppl-1'],
              statusCode: 200,
              contentType: 'application/zip',
              body: 'PK\x03\x04archive',
              code: BalikobotError.invalidResponse,
              mediaType: 'application/zip',
            ),
            (
              name: 'several packages reject PDF',
              ids: ['add-ppl-1', 'add-ppl-2'],
              statusCode: 200,
              contentType: 'application/pdf',
              body: '%PDF-1.4 label',
              code: BalikobotError.invalidResponse,
              mediaType: 'application/pdf',
            ),
            (
              name: 'several packages reject ZPL',
              ids: ['add-ppl-1', 'add-ppl-2'],
              statusCode: 200,
              contentType: 'application/zpl',
              body: '^XA^XZ',
              code: BalikobotError.invalidResponse,
              mediaType: 'application/zpl',
            ),
            (
              name: 'broken PDF',
              ids: ['add-ppl-1'],
              statusCode: 200,
              contentType: 'application/pdf',
              body: 'not a pdf',
              code: BalikobotError.invalidResponse,
              mediaType: 'application/pdf',
            ),
            (
              name: 'broken ZIP',
              ids: ['add-ppl-1', 'add-ppl-2'],
              statusCode: 200,
              contentType: 'application/zip',
              body: '%PDF-1.4 label',
              code: BalikobotError.invalidResponse,
              mediaType: 'application/zip',
            ),
            (
              name: 'empty body',
              ids: ['add-ppl-1'],
              statusCode: 200,
              contentType: 'application/pdf',
              body: '',
              code: BalikobotError.invalidResponse,
              mediaType: 'application/pdf',
            ),
            (
              name: 'unexpected content type',
              ids: ['add-ppl-1'],
              statusCode: 200,
              contentType: 'text/html',
              body: '<html></html>',
              code: BalikobotError.invalidResponse,
              mediaType: 'text/html',
            ),
            (
              name: 'http 404 is rejected',
              ids: ['add-ppl-1'],
              statusCode: 404,
              contentType: 'application/json',
              body: '{}',
              code: BalikobotError.rejected,
              mediaType: 'application/json',
            ),
            (
              name: 'http 500 is transient',
              ids: ['add-ppl-1'],
              statusCode: 500,
              contentType: 'application/json',
              body: '{}',
              code: BalikobotError.unavailable,
              mediaType: 'application/json',
            ),
          ];
      for (final testCase in cases) {
        final client = buildClient(
          MockClient((request) async {
            if (request.url.path == '/ppl/labels') {
              return jsonResponse({
                'status': 200,
                'labels_url': 'https://pdf.balikobot.cz/labels.bin',
              });
            }
            return http.Response.bytes(
              utf8.encode(testCase.body),
              testCase.statusCode,
              headers: {'content-type': testCase.contentType},
            );
          }),
        );
        addTearDown(client.close);

        if (testCase.code == null) {
          final (bytes, mediaType) = await client.downloadBatchLabels(
            Carrier.ppl,
            testCase.ids,
          );
          expect(mediaType, testCase.mediaType, reason: testCase.name);
          expect(bytes, utf8.encode(testCase.body), reason: testCase.name);
        } else {
          await expectLater(
            client.downloadBatchLabels(Carrier.ppl, testCase.ids),
            throwsA(
              isA<BalikobotException>().having(
                (error) => error.code,
                'code',
                testCase.code,
              ),
            ),
            reason: testCase.name,
          );
        }
      }
    });

    test('enforces the label byte limit', () async {
      final body = utf8.encode('%PDF-${'a' * (4 << 20)}');
      final client = buildClient(
        MockClient((request) async {
          if (request.url.path == '/ppl/labels') {
            return jsonResponse({
              'status': 200,
              'labels_url': 'https://pdf.balikobot.cz/labels.bin',
            });
          }
          return http.Response.bytes(
            body,
            200,
            headers: {'content-type': 'application/pdf'},
          );
        }),
      );
      addTearDown(client.close);

      await expectLater(
        client.downloadBatchLabels(Carrier.ppl, const ['add-ppl-1']),
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
      expect(resolveBranchId(Carrier.ppl, '1', 'KM123', ''), '123');
      expect(resolveBranchId(Carrier.ppl, '1', '456', ''), '456');
      expect(resolveBranchId(Carrier.cp, 'NP', 'ignored', '130 00'), '13000');
      expect(resolveBranchId(Carrier.sp, 'NP', 'ignored', '811 01'), '81101');
      expect(
        resolveBranchId(Carrier.ulozenka, 'CP_NP', 'ignored', '130 00'),
        '13000',
      );
      expect(resolveBranchId(Carrier.ulozenka, 'OTHER', 'x', '130 00'), 'x');
      expect(resolveBranchId(Carrier.intime, '1', '42', ''), '42');
      expect(resolveBranchId(Carrier.zasilkovna, '1', '123', ''), '123');
      expect(resolveBranchId(Carrier.dpd, '1', '99', ''), '99');
    });
  });
}
