import 'package:balikobot_dart/balikobot_dart.dart';

/// Adds one package, prints its label URL, and prints the tracking status.
Future<void> main() async {
  final client = BalikobotClient(
    const Config(
      user: 'api-user',
      apiKey: 'api-key',
      timeout: Duration(seconds: 15),
    ),
  );
  try {
    final result = await client.addPackage(
      Carrier.ppl,
      const AddPackageRequest(
        eid: 'order-2026-000123-S1',
        serviceType: '1',
        recName: 'Example Recipient',
        recStreet: 'Example 1',
        recCity: 'Praha',
        recZip: '11000',
        recCountry: Country.cz,
        recPhone: '+420777000000',
        weight: 1.5,
        length: 30,
        width: 20,
        height: 10,
        price: 1000,
        codCurrency: Currency.czk,
      ),
    );

    final labelUrl = await client.labels(Carrier.ppl, result.packageId);
    print(labelUrl);

    final status = await client.trackStatus(Carrier.ppl, result.carrierId);
    print(status.statusText);
  } finally {
    client.close();
  }
}
