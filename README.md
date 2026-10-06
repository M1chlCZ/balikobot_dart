# balikobot_dart

A Dart client for the Balíkobot shipping API v2: packages, labels, tracking,
pickups, and carrier capabilities. The client authenticates with HTTP Basic
credentials, validates every answer, and maps every failure to one sentinel
error. The package uses the `http` and `json_rest_client` libraries.

## Install

```sh
dart pub add balikobot_dart
```

Dart 3.13 or later is required. Only a loopback test server may use the `http`
scheme. Every other base URL must use `https`.

## Quick start

Create a client with your API user and API key. The client sends the
credentials as HTTP Basic authentication. Then add a package, get a label URL,
and read the tracking status.

```dart
import 'package:balikobot_dart/balikobot_dart.dart';

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
```

The `example/main.dart` file holds the same code.

## Methods

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `branches` | `GET /{carrier}/branches/...` | Lists the branches of a service and country |
| `addPackage` | `POST /{carrier}/add` | Creates one package. ADD is idempotent on `eid` |
| `overview` | `GET /{carrier}/overview` | Lists the packages that ORDER has not closed |
| `labels` | `POST /{carrier}/labels` | Gets a fresh label URL for one package |
| `orderViewLabels` | `GET /{carrier}/orderview/{order_id}` | Gets the label URL of a closed order |
| `downloadLabel` | `GET` the label URL | Downloads the label body |
| `trackStatus` | `POST /{carrier}/trackstatus` | Reads the tracking status of one package |
| `orderBatch` | `POST /{carrier}/order` | Hands one package to the carrier batch |
| `dropPackage` | `POST /{carrier}/drop` | Removes one package before ORDER |
| `orderPickup` | `POST /{carrier}/orderpickup` | Books one physical collection |
| `whoAmI` | `GET /info/whoami` | Reads the account and carrier data |
| `activatedServices` | `GET /{carrier}/activatedservices` | Lists the activated services |
| `countries` | `GET /{carrier}/countries4service` | Lists the destination countries |
| `cod` | `GET /{carrier}/cod4services` | Lists the cash-on-delivery destinations |
| `carrierCapabilities` | `GET` the discovery endpoints | Discovers the contracted carriers and services |
| `resolveBranchId` | none | Chooses the branch id or the branch zip for an ADD request |

## Codes

Carrier, currency, and country values are typed, not plain strings.

| Type | Format | Common constants |
| --- | --- | --- |
| `Carrier` | `^[a-z0-9]{2,32}$` | `ppl`, `dpd`, `dpdcz`, `dpdsk`, `geis`, `gls`, `intime`, `cp`, `ceskaposta`, `balikovna`, `zasilkovna`, `sp`, `ulozenka` |
| `Currency` | ISO 4217 `^[A-Z]{3}$` | `czk`, `eur`, `usd`, `gbp`, `pln`, `huf`, `ron`, `bgn`, `hrk`, `chf`, `nok`, `sek`, `dkk` |
| `Country` | ISO 3166-1 alpha-2 `^[A-Z]{2}$` | EU member states plus `gb`, `ch`, `no`, `isIceland`, `li`, `ua`, `rs`, `ba`, `me`, `mk`, `al`, `tr`, `us`, `ca` |

Every type has a `fromString` function and an `isValid` getter. `fromString`
trims the value, normalizes the case, and accepts any well-formed code. A
malformed value throws a `FormatException`. Use `fromString` for a value that
has no constant, so custom carriers, currencies, and countries work:

```dart
final custom = Carrier.fromString('MyCarrier99');
final result = await client.addPackage(custom, request);
```

The types keep the wire values compile-time safe: a function that expects a
`Carrier` rejects a bare string, and a mistyped constant fails the build. The
JSON form stays a plain string, so the wire contract does not change.

ADD accepts only `Currency.czk` and `Currency.eur` as `codCurrency`, because
the carriers require one of those two values. The client rejects every other
well-formed currency code before the request.

## Errors

The client reports every failure with a `BalikobotException`. The `code` field
holds one of six `BalikobotError` values.

| Error | Meaning | Action |
| --- | --- | --- |
| `BalikobotError.invalidRequest` | The arguments are not valid. The client sent no request. | Correct the input. Do not retry. |
| `BalikobotError.rejected` | The provider refused the data permanently. | Correct the data. Do not retry. |
| `BalikobotError.unavailable` | The provider is unavailable, or the request never left the client. | Retry later. |
| `BalikobotError.notFound` | The carrier has no tracking data yet. | Poll again later. |
| `BalikobotError.ambiguous` | A mutating call can have reached the provider. | Reconcile with `overview`. Then retry. |
| `BalikobotError.invalidResponse` | The answer violates the protocol. | Inspect the provider. Do not retry blindly. |

When a JSON answer carries a `Retry-After` header, the exception of a
`BalikobotError.unavailable` failure carries the `retryAfter` field. Read the
field and wait before the next call:

```dart
try {
  await client.orderBatch(Carrier.ppl, packageId);
} on BalikobotException catch (error) {
  final retryAfter = error.retryAfter;
  if (retryAfter != null) {
    await Future<void>.delayed(retryAfter);
  }
}
```

`orderPickup` maps HTTP 429 to `rejected`. The branch, label download, and
capability calls return `unavailable` without a hint.

The client sends no automatic retry. You control the retry policy.

## Response limits

The client reads every JSON body with a hard limit of 8 MiB. Set
`Config.maxResponseBytes` to change the limit. Label downloads use a fixed
limit of 4 MiB. The client refuses redirects. It compares the response
`Content-Type` with the expected media type before it decodes the body.

## Account mode

Set `Config.liveAccount` to `true` or `false` to verify the account before each
mutating call. The client calls WHOAMI and compares the `live_account` flag. A
mismatch blocks the write before the client sends it. A successful result stays
valid for five minutes. If `Config.liveAccount` is null, the client skips this
check.

## Label hosts

The client accepts label URLs only from the Balíkobot label hosts
(`pdf.balikobot.cz` and the `*.balikobot.cz` subdomains), or from the base URL
origin for a loopback test server. Set `Config.labelHosts` to replace the
default allowlist with other hosts. A leading dot selects a subdomain suffix
match; it does not match the bare domain.

## Development

Run the checks from the package root:

```sh
dart analyze --fatal-infos
dart test
```

The tests use mocked HTTP clients. They use no real credentials and no external
network.

## License

MIT. See [LICENSE](LICENSE).
