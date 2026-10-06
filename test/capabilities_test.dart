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

  group('whoAmI', () {
    test('returns the account information', () async {
      final client = buildClient(
        MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/info/whoami');
          return jsonResponse({
            'status': 200,
            'live_account': true,
            'account': {'email': 'private@example.test'},
            'carriers': [
              {'slug': 'ppl', 'name': 'PPL'},
              {'slug': 'gls'},
            ],
          });
        }),
      );
      addTearDown(client.close);

      final result = await client.whoAmI();

      expect(result.status, 200);
      expect(result.liveAccount, isTrue);
      expect(result.carriers, hasLength(2));
      expect(result.carriers.first.slug, Carrier.ppl);
      expect(result.carriers.first.name, 'PPL');
      expect(result.carriers.last.slug, Carrier.gls);
      expect(result.carriers.last.name, isEmpty);
    });
  });

  group('activatedServices', () {
    test('drops the services when parcel shipping is inactive', () async {
      final client = buildClient(
        MockClient(
          (request) async => jsonResponse({
            'status': 200,
            'active_parcel': false,
            'service_types': [
              {'service_type': '80', 'name': 'Balíkovna'},
            ],
          }),
        ),
      );
      addTearDown(client.close);

      final result = await client.activatedServices(Carrier.ppl);

      expect(result.activeParcel, isFalse);
      expect(result.services, isEmpty);
    });
  });

  group('countries', () {
    test('accepts the array shape', () async {
      final client = buildClient(
        MockClient(
          (request) async => jsonResponse({
            'status': 200,
            'service_types': [
              {
                'service_type': 'VMCZ',
                'countries': [' cz ', 'SK'],
              },
              {
                'service_type': 6830,
                'countries': ['AT'],
              },
            ],
          }),
        ),
      );
      addTearDown(client.close);

      final result = await client.countries(Carrier.zasilkovna);

      expect(result, hasLength(2));
      expect(result.first.serviceType, 'VMCZ');
      expect(result.first.countries, [Country.cz, Country.sk]);
      expect(result.last.serviceType, '6830');
      expect(result.last.countries, [Country.at]);
    });

    test('accepts the sparse object shape in lexical key order', () async {
      final client = buildClient(
        MockClient(
          (request) async => jsonResponse({
            'status': 200,
            'service_types': {
              '7': {
                'service_type': 4,
                'countries': ['CZ', 'RO', 'US'],
              },
              '2': {
                'service_type': 3,
                'countries': ['SK'],
              },
            },
          }),
        ),
      );
      addTearDown(client.close);

      final result = await client.countries(Carrier.zasilkovna);

      expect(result.map((entry) => entry.serviceType), ['3', '4']);
      expect(result.first.countries, [Country.sk]);
      expect(result.last.countries, [Country.cz, Country.ro, Country.us]);
    });
  });

  group('cod', () {
    test(
      'converts exact prices and rejects imprecise or quoted prices',
      () async {
        Future<void> expectInvalid(Object maxPrice) async {
          final rejecting = buildClient(
            MockClient(
              (request) async => jsonResponse({
                'status': 200,
                'service_types': [
                  {
                    'service_type': 'VMCZ',
                    'countries': [
                      {
                        'country': 'CZ',
                        'currency': 'CZK',
                        'max_price': maxPrice,
                      },
                    ],
                  },
                ],
              }),
            ),
          );
          addTearDown(rejecting.close);
          await expectLater(
            rejecting.cod(Carrier.ppl),
            throwsA(
              isA<BalikobotException>().having(
                (error) => error.code,
                'code',
                BalikobotError.invalidResponse,
              ),
            ),
          );
        }

        final client = buildClient(
          MockClient(
            (request) async => jsonResponse({
              'status': 200,
              'service_types': [
                {
                  'service_type': 'VMCZ',
                  'countries': [
                    {'country': 'CZ', 'currency': 'CZK', 'max_price': 1499.95},
                  ],
                },
              ],
            }),
          ),
        );
        addTearDown(client.close);

        final result = await client.cod(Carrier.ppl);

        expect(result.single.countries.single.maxAmountMinor, 149995);

        await expectInvalid(92233720368547758.07);
        await expectInvalid('5');
      },
    );

    test('treats an unsupported dictionary as empty', () async {
      final client = buildClient(
        MockClient((request) async => http.Response('', 501)),
      );
      addTearDown(client.close);

      final result = await client.cod(Carrier.ppl);

      expect(result, isEmpty);
    });
  });

  group('carrierCapabilities', () {
    test('aggregates services and keeps only EU countries', () async {
      final client = buildClient(
        MockClient((request) async {
          switch (request.url.path) {
            case '/info/whoami':
              return jsonResponse({
                'status': 200,
                'live_account': true,
                'carriers': [
                  {'slug': 'ppl', 'name': 'PPL'},
                ],
              });
            case '/ppl/activatedservices':
              return jsonResponse({
                'status': 200,
                'active_parcel': true,
                'service_types': [
                  {
                    'service_type': 'LONG_SERVICE_CODE_123456789',
                    'name': 'PPL Home',
                    'home_delivery': true,
                  },
                ],
              });
            case '/ppl/countries4service':
              return jsonResponse({
                'status': 200,
                'service_types': [
                  {
                    'service_type': 'LONG_SERVICE_CODE_123456789',
                    'countries': ['CZ', 'DE', 'US'],
                  },
                ],
              });
            default:
              fail('unexpected request ${request.url.path}');
          }
        }),
      );
      addTearDown(client.close);

      final List<ContractedCarrier> carriers = await client
          .carrierCapabilities();

      expect(carriers, hasLength(1));
      expect(carriers.single.carrierCode, Carrier.ppl);
      final service = carriers.single.services.single;
      expect(service.code, 'LONG_SERVICE_CODE_123456789');
      expect(service.name, 'PPL Home');
      expect(service.homeDelivery, isTrue);
      expect(service.countries, {Country.cz: true, Country.de: true});
      expect(service.cod, isEmpty);
    });
  });
}
