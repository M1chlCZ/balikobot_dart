import 'package:http/http.dart' as http;

/// Configures a [BalikobotClient].
class Config {
  /// Creates a configuration.
  ///
  /// [user] and [apiKey] are required and are sent as the HTTP Basic
  /// credentials. [baseUrl] defaults to the production Balíkobot API v2
  /// endpoint. [timeout] defaults to 30 seconds and [maxResponseBytes] to
  /// 8 MiB.
  const Config({
    this.baseUrl = 'https://apiv2.balikobot.cz',
    required this.user,
    required this.apiKey,
    this.httpClient,
    this.timeout = const Duration(seconds: 30),
    this.maxResponseBytes = 8 << 20,
    this.labelHosts = const [],
    this.liveAccount,
  });

  /// The API root, for example `https://apiv2.balikobot.cz`.
  ///
  /// Only the loopback host of a local test server may use the `http` scheme.
  final String baseUrl;

  /// The API user, sent as the HTTP Basic user name.
  final String user;

  /// The API key, sent as the HTTP Basic password.
  final String apiKey;

  /// An optional caller-owned HTTP client.
  ///
  /// When omitted, the client owns an HTTP client and closes it in
  /// [BalikobotClient.close]. An injected client is never closed.
  final http.Client? httpClient;

  /// The whole-request timeout. A zero duration selects 30 seconds.
  final Duration timeout;

  /// The hard byte limit for a JSON response body.
  ///
  /// Zero selects 8 MiB. The value must not exceed 1 GiB.
  final int maxResponseBytes;

  /// Optionally restricts label downloads to these hosts.
  ///
  /// A leading dot selects a suffix match, so `.balikobot.cz` covers every
  /// subdomain while `pdf.balikobot.cz` matches one host. When empty, the
  /// client allows the Balíkobot label hosts.
  final List<String> labelHosts;

  /// Optionally enables account-mode verification before mutating calls.
  ///
  /// When set, the client requires the provider `live_account` flag to equal
  /// this value. When `null`, no account-mode check is performed.
  final bool? liveAccount;
}
