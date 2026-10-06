import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:json_rest_client/json_rest_client.dart';
import 'package:meta/meta.dart';

import 'codes/carrier.dart';
import 'codes/country.dart';
import 'config.dart';
import 'errors.dart';
import 'models/branch.dart';

part 'response.dart';

/// A client for the Balíkobot API v2.
///
/// The client validates its [Config] on construction, authenticates every
/// request with HTTP Basic credentials, and refuses redirects. It performs no
/// logging, caching, persistence or automatic retries.
class BalikobotClient {
  /// Validates [config] and creates a client.
  ///
  /// The user and the API key must not be empty, the base URL must be an
  /// absolute URL, and the `https` scheme is mandatory unless the host is a
  /// loopback address. An invalid configuration throws an [ArgumentError].
  BalikobotClient(Config config) {
    final user = config.user.trim();
    if (user.isEmpty || utf8.encode(user).length > _userLimit) {
      throw ArgumentError(_userMessage);
    }
    if (config.apiKey.isEmpty ||
        utf8.encode(config.apiKey).length > _apiKeyLimit) {
      throw ArgumentError(_apiKeyMessage);
    }
    if (config.timeout.isNegative) {
      throw ArgumentError(_timeoutMessage);
    }
    if (config.maxResponseBytes < 0 ||
        config.maxResponseBytes > _maxResponseBytesLimit) {
      throw ArgumentError(_responseLimitMessage);
    }
    final baseUrl = _validateBaseUrl(config.baseUrl);
    _validateLabelHosts(config.labelHosts);
    final timeout = config.timeout == Duration.zero
        ? _defaultTimeout
        : config.timeout;
    _ownsHttpClient = config.httpClient == null;
    _maxResponseBytes = config.maxResponseBytes == 0
        ? _defaultMaxResponseBytes
        : config.maxResponseBytes;
    _httpClient = _NoRedirectClient(
      config.httpClient ?? IOClient(HttpClient()),
      closeInner: _ownsHttpClient,
    );
    _rest = JsonRestClient(
      baseUrl: baseUrl,
      client: _httpClient,
      tokenStore: _EmptyTokenStore(),
      defaultHeaders: {
        'authorization':
            'Basic ${base64.encode(utf8.encode('$user:${config.apiKey}'))}',
      },
      userAgentProvider: () async => _userAgent,
      timeout: timeout,
    );
  }

  late final http.Client _httpClient;
  late final bool _ownsHttpClient;
  late final JsonRestClient _rest;
  late final int _maxResponseBytes;
  bool _closed = false;

  /// The wrapped HTTP client used for every request.
  ///
  /// Exposed for tests that verify transport behavior.
  @visibleForTesting
  http.Client get httpClient => _httpClient;

  /// Releases the resources held by this client.
  ///
  /// The HTTP client owned by this instance is closed; an injected
  /// [Config.httpClient] is never closed. Repeated calls are safe.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _rest.close();
    _httpClient.close();
  }

  /// Calls the BRANCHES method and returns the branches of one [carrier]
  /// service in one [country].
  ///
  /// The route depends on the carrier: the selected carriers use the combined
  /// service and country segments, Zásilkovna uses the country-only route, and
  /// the remaining carriers use the service-only route with a client-side
  /// country filter. An invalid [carrier], [service] or [country] throws a
  /// [BalikobotException] with [BalikobotError.invalidRequest] before any
  /// request is sent.
  Future<List<Branch>> branches(
    Carrier carrier,
    String service,
    Country country,
  ) async {
    if (!carrier.isValid ||
        !_servicePattern.hasMatch(service) ||
        !country.isValid) {
      throw _error(BalikobotError.invalidRequest);
    }
    final (path, filterCountry) = _branchesPath(carrier, service, country);
    final RestResponse response;
    try {
      response = await _sendRequest('GET', path);
    } on _TransportFailure {
      throw _error(BalikobotError.unavailable);
    } on ResponseLimitException {
      throw _error(BalikobotError.unavailable);
    }
    final statusCode = response.statusCode;
    if (statusCode == 429 || statusCode >= 500) {
      throw _transient(response);
    }
    if (statusCode != 200 || !_isJson(response)) {
      throw _error(BalikobotError.invalidResponse);
    }
    final ({int status, List<_BranchWire> branches}) payload;
    try {
      payload = _branchesResponse(_decode(response));
    } on FormatException {
      throw _error(BalikobotError.invalidResponse);
    }
    switch (payload.status) {
      case 200:
        break;
      case 426:
      case 503:
        throw _error(BalikobotError.unavailable);
      default:
        throw _error(BalikobotError.invalidResponse);
    }
    final branches = <Branch>[];
    for (final wire in payload.branches) {
      final branch = _sanitizeBranch(wire);
      if (branch == null) {
        continue;
      }
      if (filterCountry &&
          branch.country.value.isNotEmpty &&
          branch.country != country) {
        continue;
      }
      branches.add(branch);
    }
    return branches;
  }
}

(String, bool) _branchesPath(Carrier carrier, String service, Country country) {
  final path = '/${carrier.value}/branches/service/$service';
  switch (carrier.value) {
    case 'ppl':
    case 'dpd':
    case 'dpdcz':
    case 'dpdsk':
    case 'geis':
    case 'gls':
    case 'intime':
      return ('$path/country/${country.value}', false);
    case 'cp':
    case 'ceskaposta':
    case 'balikovna':
      return ('$path/country/${country.value}', true);
    case 'zasilkovna':
      return ('/zasilkovna/branches/country/${country.value}', false);
    default:
      return (path, true);
  }
}

String _validateBaseUrl(String raw) {
  var baseUrl = raw.trim();
  if (baseUrl.isEmpty) {
    baseUrl = _defaultBaseUrl;
  }
  if (baseUrl.endsWith('/')) {
    baseUrl = baseUrl.substring(0, baseUrl.length - 1);
  }
  final Uri parsed;
  try {
    parsed = Uri.parse(baseUrl);
  } on FormatException {
    throw ArgumentError(_baseUrlAbsoluteMessage);
  }
  if (parsed.host.isEmpty ||
      baseUrl.contains('@') ||
      parsed.query.isNotEmpty ||
      parsed.fragment.isNotEmpty ||
      (parsed.path.isNotEmpty && parsed.path != '/')) {
    throw ArgumentError(_baseUrlAbsoluteMessage);
  }
  final address = InternetAddress.tryParse(parsed.host);
  final loopback = address != null && address.isLoopback;
  switch (parsed.scheme) {
    case 'https':
      break;
    case 'http':
      if (!loopback) {
        throw ArgumentError(_baseUrlHttpsMessage);
      }
    default:
      throw ArgumentError(_baseUrlSchemeMessage);
  }
  return baseUrl;
}

void _validateLabelHosts(List<String> hosts) {
  for (final host in hosts) {
    final normalized = host.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized.contains('/') ||
        normalized.contains('\\') ||
        normalized.contains('@') ||
        normalized.contains('?') ||
        normalized.contains('#')) {
      throw ArgumentError(_labelHostMessage);
    }
  }
}

class _NoRedirectClient extends http.BaseClient {
  _NoRedirectClient(this._inner, {required this.closeInner});

  final http.Client _inner;
  final bool closeInner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.followRedirects = false;
    return _inner.send(request);
  }

  @override
  void close() {
    if (closeInner) {
      _inner.close();
    }
  }
}

class _EmptyTokenStore implements TokenStore {
  @override
  Future<String?> read(String key) async => null;
}

const String _defaultBaseUrl = 'https://apiv2.balikobot.cz';
const Duration _defaultTimeout = Duration(seconds: 30);
const int _defaultMaxResponseBytes = 8 << 20;
const String _userAgent = 'balikobot_dart/0.1.0';
const int _userLimit = 100;
const int _apiKeyLimit = 4096;
const int _maxResponseBytesLimit = 1 << 30;
const String _userMessage =
    'invalid configuration: user is required and limited to 100 bytes';
const String _apiKeyMessage =
    'invalid configuration: API key is required and limited to 4096 bytes';
const String _timeoutMessage =
    'invalid configuration: timeout must not be negative';
const String _responseLimitMessage =
    'invalid configuration: response limit must be between 0 and 1073741824 bytes';
const String _baseUrlAbsoluteMessage =
    'invalid configuration: base URL must be absolute without path, query or fragment';
const String _baseUrlHttpsMessage =
    'invalid configuration: base URL must use https unless the host is loopback';
const String _baseUrlSchemeMessage =
    'invalid configuration: base URL must use http or https';
const String _labelHostMessage =
    'invalid configuration: label hosts must be host names';
