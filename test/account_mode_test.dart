import 'dart:convert';

import 'package:balikobot_dart/balikobot_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
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

  http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  BalikobotClient accountClient(MockClient httpClient) => BalikobotClient(
    Config(
      user: 'user',
      apiKey: 'key',
      liveAccount: true,
      httpClient: httpClient,
    ),
  );

  test('blocks a write when the live flag differs', () async {
    var requests = 0;
    final client = accountClient(
      MockClient((request) async {
        requests++;
        return jsonResponse({
          'status': 200,
          'live_account': false,
          'carriers': [],
        });
      }),
    );
    addTearDown(client.close);

    await expectLater(
      client.addPackage(Carrier.ppl, addRequest()),
      throwsA(
        isA<BalikobotException>().having(
          (error) => error.code,
          'code',
          BalikobotError.unavailable,
        ),
      ),
    );
    expect(requests, 1);
  });

  test('allows writes while the verified account is fresh', () async {
    var whoamiCalls = 0;
    var addCalls = 0;
    final client = accountClient(
      MockClient((request) async {
        if (request.url.path == '/info/whoami') {
          whoamiCalls++;
          return jsonResponse({
            'status': 200,
            'live_account': true,
            'carriers': [],
          });
        }
        addCalls++;
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

    await client.addPackage(Carrier.ppl, addRequest());
    await client.addPackage(Carrier.ppl, addRequest());

    expect(whoamiCalls, 1);
    expect(addCalls, 2);
  });

  test('orderPickup rejects an unverified account', () async {
    var requests = 0;
    final client = accountClient(
      MockClient((request) async {
        requests++;
        return jsonResponse({
          'status': 200,
          'live_account': false,
          'carriers': [],
        });
      }),
    );
    addTearDown(client.close);

    await expectLater(
      client.orderPickup(
        Carrier.dpdcz,
        const PickupRequest(date: '2026-09-20', weightKg: 1, packageCount: 1),
      ),
      throwsA(
        isA<BalikobotException>().having(
          (error) => error.code,
          'code',
          BalikobotError.rejected,
        ),
      ),
    );
    expect(requests, 1);
  });
}
