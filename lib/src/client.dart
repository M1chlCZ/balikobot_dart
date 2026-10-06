import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:json_rest_client/json_rest_client.dart';
import 'package:meta/meta.dart';

import 'codes/carrier.dart';
import 'codes/country.dart';
import 'codes/currency.dart';
import 'config.dart';
import 'errors.dart';
import 'models/branch.dart';
import 'models/capabilities.dart' as capabilities;
import 'models/pickup.dart';
import 'models/shipment.dart';
import 'models/tracking.dart';

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
    final (baseUrl, origin, loopback) = _validateBaseUrl(config.baseUrl);
    _labelHosts = _normalizeLabelHosts(config.labelHosts);
    _liveAccount = config.liveAccount;
    _origin = origin;
    _loopback = loopback;
    final timeout = config.timeout == Duration.zero
        ? _defaultTimeout
        : config.timeout;
    _timeout = timeout;
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
  late final Duration _timeout;
  late final List<String> _labelHosts;
  late final String _origin;
  late final bool _loopback;
  late final bool? _liveAccount;
  DateTime? _accountVerifiedAt;
  Future<_WhoAmIWire>? _accountCheckInFlight;
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
  /// request is sent. [timeout] overrides the configured request timeout for
  /// this call.
  Future<List<Branch>> branches(
    Carrier carrier,
    String service,
    Country country, {
    Duration? timeout,
  }) async {
    if (!carrier.isValid ||
        !_servicePattern.hasMatch(service) ||
        !country.isValid) {
      throw _error(BalikobotError.invalidRequest);
    }
    final (path, filterCountry) = _branchesPath(carrier, service, country);
    final RestResponse response;
    try {
      response = await _sendRequest('GET', path, timeout: timeout);
    } on _TransportFailure {
      throw _error(BalikobotError.unavailable);
    } on ResponseLimitException {
      throw _error(BalikobotError.unavailable);
    }
    final statusCode = response.statusCode;
    if (statusCode == 429 || statusCode >= 500) {
      throw _error(BalikobotError.unavailable);
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

  /// Calls the ADD method with one package.
  ///
  /// ADD is idempotent on [AddPackageRequest.eid]: a repeated request with an
  /// already stored EID returns status 208 together with the original record,
  /// which maps to a successful result. An invalid [carrier] or [request]
  /// throws a [BalikobotException] with [BalikobotError.invalidRequest] before
  /// any request is sent. [timeout] overrides the configured request timeout
  /// for this call.
  Future<AddPackageResult> addPackage(
    Carrier carrier,
    AddPackageRequest request, {
    Duration? timeout,
  }) async {
    if (!carrier.isValid || !_validAddPackage(request)) {
      throw _error(BalikobotError.invalidRequest);
    }
    final RestResponse response;
    try {
      response = await _sendRequest(
        'POST',
        '/${carrier.value}/add',
        body: {
          'packages': [request.toJson()],
        },
        timeout: timeout,
      );
    } on _TransportFailure catch (failure) {
      throw _dispatchFailure(failure);
    } on ResponseLimitException {
      throw _error(BalikobotError.ambiguous);
    }
    final statusCode = response.statusCode;
    if (statusCode == 429) {
      throw _transient(response);
    }
    if (statusCode >= 500) {
      throw _error(BalikobotError.unavailable);
    }
    if (statusCode != 200) {
      if (statusCode >= 200 && statusCode < 300) {
        throw _error(BalikobotError.ambiguous);
      }
      if (statusCode >= 400 && statusCode < 500) {
        throw _error(BalikobotError.rejected);
      }
      throw _error(BalikobotError.invalidResponse);
    }
    if (!_isJson(response)) {
      throw _error(BalikobotError.ambiguous);
    }
    final _AddResponse payload;
    try {
      payload = _addResponse(_decode(response));
    } on FormatException {
      throw _error(BalikobotError.ambiguous);
    }
    if (payload.status == null) {
      throw _error(BalikobotError.ambiguous);
    }
    final statusError = _topLevelStatusError(payload.status);
    if (statusError != null) {
      if (statusError.code == BalikobotError.invalidResponse) {
        throw _error(BalikobotError.ambiguous);
      }
      throw statusError;
    }
    if (payload.packages.length != 1 ||
        payload.packages.first.eid != request.eid) {
      throw _error(BalikobotError.ambiguous);
    }
    final entry = payload.packages.first;
    switch (entry.status) {
      case 200:
      case 208:
        if (entry.packageId == null ||
            entry.carrierId.isEmpty ||
            !_validBranchField(entry.carrierId, _identifierLimit) ||
            !_validLabelUrl(entry.labelUrl)) {
          throw _error(BalikobotError.ambiguous);
        }
        return AddPackageResult(
          packageId: entry.packageId!,
          carrierId: entry.carrierId,
          labelUrl: entry.labelUrl,
        );
      case 426:
      case 503:
        throw _error(BalikobotError.unavailable);
      case 400:
      case 403:
      case 404:
      case 405:
      case 406:
      case 409:
      case 413:
      case 423:
      case 501:
        throw _error(BalikobotError.rejected);
      default:
        throw _error(BalikobotError.ambiguous);
    }
  }

  /// Calls the OVERVIEW method, which lists the packages of a [carrier] that
  /// have not been closed by ORDER yet.
  ///
  /// [matchEid] names the single entry whose integrity is required for
  /// reconciliation: a malformed entry with a different EID is skipped, while
  /// a malformed matching entry fails the call. An invalid [carrier] throws a
  /// [BalikobotException] with [BalikobotError.invalidRequest] before any
  /// request is sent. [timeout] overrides the configured request timeout for
  /// this call.
  Future<List<OverviewPackage>> overview(
    Carrier carrier,
    String matchEid, {
    Duration? timeout,
  }) async {
    if (!carrier.isValid) {
      throw _error(BalikobotError.invalidRequest);
    }
    final RestResponse response;
    try {
      response = await _sendRequest(
        'GET',
        '/${carrier.value}/overview',
        timeout: timeout,
      );
    } on _TransportFailure catch (failure) {
      throw _dispatchFailure(failure);
    } on ResponseLimitException {
      throw _error(BalikobotError.ambiguous);
    }
    final statusCode = response.statusCode;
    if (statusCode == 429) {
      throw _transient(response);
    }
    if (statusCode >= 500) {
      throw _error(BalikobotError.unavailable);
    }
    if (statusCode != 200 || !_isJson(response)) {
      if (statusCode >= 400 && statusCode < 500) {
        throw _error(BalikobotError.rejected);
      }
      throw _error(BalikobotError.invalidResponse);
    }
    final _OverviewResponse payload;
    try {
      payload = _overviewResponse(_decode(response));
    } on FormatException {
      throw _error(BalikobotError.invalidResponse);
    }
    final statusError = _topLevelStatusError(payload.status);
    if (statusError != null) {
      throw statusError;
    }
    final packages = <OverviewPackage>[];
    for (final entry in payload.packages) {
      final valid =
          entry.eid.isNotEmpty &&
          entry.packageId != null &&
          entry.carrierId.isNotEmpty &&
          _validBranchField(entry.carrierId, _identifierLimit) &&
          _validLabelUrl(entry.labelUrl);
      if (!valid) {
        if (entry.eid == matchEid) {
          throw _error(BalikobotError.invalidResponse);
        }
        continue;
      }
      packages.add(
        OverviewPackage(
          eid: entry.eid,
          packageId: entry.packageId!,
          carrierId: entry.carrierId,
          labelUrl: entry.labelUrl,
        ),
      );
    }
    return packages;
  }

  /// Asks for a fresh aggregate label URL of one package that has not entered
  /// ORDER yet.
  ///
  /// An invalid [carrier] or [packageId] throws a [BalikobotException] with
  /// [BalikobotError.invalidRequest] before any request is sent. [timeout]
  /// overrides the configured request timeout for this call.
  Future<String> labels(
    Carrier carrier,
    String packageId, {
    Duration? timeout,
  }) async {
    if (!carrier.isValid || !_validPackageId(packageId)) {
      throw _error(BalikobotError.invalidRequest);
    }
    final RestResponse response;
    try {
      response = await _sendRequest(
        'POST',
        '/${carrier.value}/labels',
        body: {
          'package_ids': [packageId],
        },
        timeout: timeout,
      );
    } on _TransportFailure {
      throw _error(BalikobotError.unavailable);
    } on ResponseLimitException {
      throw _error(BalikobotError.unavailable);
    }
    final lookupError = _labelLookupStatus(response);
    if (lookupError != null) {
      throw lookupError;
    }
    final _LabelsResponse payload;
    try {
      payload = _labelsResponse(_decode(response));
    } on FormatException {
      throw _error(BalikobotError.invalidResponse);
    }
    if (payload.status == null) {
      throw _error(BalikobotError.invalidResponse);
    }
    final statusError = _topLevelStatusError(payload.status);
    if (statusError != null) {
      throw statusError;
    }
    if (!_validLabelUrl(payload.labelsUrl)) {
      throw _error(BalikobotError.invalidResponse);
    }
    return payload.labelsUrl;
  }

  /// Retrieves the label URL of an already closed ORDER.
  ///
  /// The returned URL is accepted only when the response confirms both the
  /// requested [orderId] and the membership of the requested [packageId]. An
  /// invalid [carrier], [orderId] or [packageId] throws a
  /// [BalikobotException] with [BalikobotError.invalidRequest] before any
  /// request is sent. [timeout] overrides the configured request timeout for
  /// this call.
  Future<String> orderViewLabels(
    Carrier carrier,
    String orderId,
    String packageId, {
    Duration? timeout,
  }) async {
    if (!carrier.isValid ||
        !_validPackageId(orderId) ||
        !_validPackageId(packageId)) {
      throw _error(BalikobotError.invalidRequest);
    }
    final RestResponse response;
    try {
      response = await _sendRequest(
        'GET',
        '/${carrier.value}/orderview/${Uri.encodeComponent(orderId)}',
        timeout: timeout,
      );
    } on _TransportFailure {
      throw _error(BalikobotError.unavailable);
    } on ResponseLimitException {
      throw _error(BalikobotError.unavailable);
    }
    final lookupError = _labelLookupStatus(response);
    if (lookupError != null) {
      throw lookupError;
    }
    final _OrderViewResponse payload;
    try {
      payload = _orderViewResponse(_decode(response));
    } on FormatException {
      throw _error(BalikobotError.invalidResponse);
    }
    final statusError = _topLevelStatusError(payload.status);
    if (statusError != null) {
      throw statusError;
    }
    if (payload.orderId != orderId ||
        !payload.packageIds.contains(packageId) ||
        !_validLabelUrl(payload.labelsUrl)) {
      throw _error(BalikobotError.invalidResponse);
    }
    return payload.labelsUrl;
  }

  /// Fetches a provider label URL server-to-server.
  ///
  /// The body is read once with a hard 4 MiB limit and validated against the
  /// declared media type and the configured label host rules. The returned
  /// bytes and media type are owned by the caller. An invalid [labelUrl]
  /// throws a [BalikobotException] with [BalikobotError.invalidRequest] before
  /// any request is sent. [timeout] overrides the configured request timeout
  /// for this call.
  Future<(Uint8List, String)> downloadLabel(
    String labelUrl, {
    Duration? timeout,
  }) async {
    if (!_validLabelUrl(labelUrl)) {
      throw _error(BalikobotError.invalidRequest);
    }
    final request = http.Request('GET', Uri.parse(labelUrl));
    final http.StreamedResponse response;
    try {
      response = await _httpClient.send(request).timeout(timeout ?? _timeout);
    } on TimeoutException {
      throw _error(BalikobotError.unavailable);
    } on IOException {
      throw _error(BalikobotError.unavailable);
    } on http.ClientException {
      throw _error(BalikobotError.unavailable);
    }
    final statusCode = response.statusCode;
    if (statusCode == 429 || statusCode >= 500) {
      throw _error(BalikobotError.unavailable);
    }
    if (statusCode != 200) {
      if (statusCode >= 400 && statusCode < 500) {
        throw _error(BalikobotError.rejected);
      }
      throw _error(BalikobotError.invalidResponse);
    }
    final mediaType = _labelMediaType(response.headers['content-type']);
    if (mediaType != _pdfMediaType && mediaType != _zplMediaType) {
      throw _error(BalikobotError.invalidResponse);
    }
    final Uint8List bytes;
    try {
      bytes = await _readLimited(
        response,
        _labelResponseLimit,
      ).timeout(timeout ?? _timeout);
    } on ResponseLimitException {
      throw _error(BalikobotError.invalidResponse);
    } on TimeoutException {
      throw _error(BalikobotError.unavailable);
    } on IOException {
      throw _error(BalikobotError.unavailable);
    } on http.ClientException {
      throw _error(BalikobotError.unavailable);
    }
    if (bytes.isEmpty) {
      throw _error(BalikobotError.invalidResponse);
    }
    if (mediaType == _pdfMediaType && !_hasPrefix(bytes, _pdfMagicPrefix)) {
      throw _error(BalikobotError.invalidResponse);
    }
    if (mediaType == _zplMediaType && !_hasPrefix(bytes, _zplMagicPrefix)) {
      throw _error(BalikobotError.invalidResponse);
    }
    return (bytes, mediaType!);
  }

  /// Calls the TRACKSTATUS method for one carrier tracking number.
  ///
  /// [carrierId] is the carrier tracking number from ADD. A carrier answer or
  /// HTTP status 404 means that the carrier has no tracking data yet and
  /// throws a [BalikobotException] with [BalikobotError.notFound]. An invalid
  /// [carrier] or [carrierId] throws a [BalikobotException] with
  /// [BalikobotError.invalidRequest] before any request is sent. The call is
  /// read-only, so transport failures are safe to retry. [timeout] overrides
  /// the configured request timeout for this call.
  Future<TrackStatusResult> trackStatus(
    Carrier carrier,
    String carrierId, {
    Duration? timeout,
  }) async {
    if (!carrier.isValid || !_validPackageId(carrierId)) {
      throw _error(BalikobotError.invalidRequest);
    }
    final RestResponse response;
    try {
      response = await _sendRequest(
        'POST',
        '/${carrier.value}/trackstatus',
        body: {
          'carrier_ids': [carrierId],
        },
        timeout: timeout,
      );
    } on _TransportFailure {
      throw _error(BalikobotError.unavailable);
    } on ResponseLimitException {
      throw _error(BalikobotError.unavailable);
    }
    final httpError = _trackHttpStatus(response);
    if (httpError != null) {
      throw httpError;
    }
    final _TrackStatusResponse payload;
    try {
      payload = _trackStatusResponse(_decode(response));
    } on FormatException {
      throw _error(BalikobotError.invalidResponse);
    }
    final topStatus = payload.status;
    if (topStatus != null) {
      switch (topStatus) {
        case 200:
          break;
        case 426:
        case 503:
          throw _error(BalikobotError.unavailable);
        case 404:
          throw _error(BalikobotError.notFound);
        default:
          throw _error(BalikobotError.invalidResponse);
      }
    }
    if (payload.packages.length != 1 ||
        payload.packages.first.carrierId != carrierId) {
      throw _error(BalikobotError.invalidResponse);
    }
    final entry = payload.packages.first;
    if (entry.status == null && (topStatus == null || entry.name.isEmpty)) {
      throw _error(BalikobotError.invalidResponse);
    }
    final status = entry.status ?? topStatus;
    switch (status) {
      case 200:
        final id = entry.statusIdV2 ?? entry.statusId;
        final description = entry.name.isNotEmpty
            ? entry.name
            : entry.statusText;
        if (id == null ||
            description.isEmpty ||
            !_validBranchField(description, _branchFieldLimit)) {
          throw _error(BalikobotError.invalidResponse);
        }
        return TrackStatusResult(statusId: id, statusText: description);
      case 404:
        throw _error(BalikobotError.notFound);
      case 426:
      case 503:
        throw _error(BalikobotError.unavailable);
      case 400:
      case 403:
      case 405:
      case 406:
      case 409:
      case 413:
      case 423:
        throw _error(BalikobotError.rejected);
      default:
        throw _error(BalikobotError.invalidResponse);
    }
  }

  /// Calls the ORDER method, which hands one package over to the carrier
  /// batch.
  ///
  /// ORDER is idempotent on [packageId]: a repeated closure returns body
  /// status 208 with the original order id. An invalid [carrier] or
  /// [packageId] throws a [BalikobotException] with
  /// [BalikobotError.invalidRequest] before any request is sent. [timeout]
  /// overrides the configured request timeout for this call.
  Future<OrderResult> orderBatch(
    Carrier carrier,
    String packageId, {
    Duration? timeout,
  }) async {
    if (!carrier.isValid || !_validPackageId(packageId)) {
      throw _error(BalikobotError.invalidRequest);
    }
    final RestResponse response;
    try {
      response = await _sendRequest(
        'POST',
        '/${carrier.value}/order',
        body: {
          'package_ids': [packageId],
        },
        timeout: timeout,
      );
    } on _TransportFailure catch (failure) {
      throw _dispatchFailure(failure);
    } on ResponseLimitException {
      throw _error(BalikobotError.ambiguous);
    }
    final statusCode = response.statusCode;
    if (statusCode == 429) {
      throw _transient(response);
    }
    if (statusCode >= 500) {
      throw _error(BalikobotError.unavailable);
    }
    if (statusCode != 200 || !_isJson(response)) {
      if (statusCode >= 200 && statusCode < 300) {
        throw _error(BalikobotError.ambiguous);
      }
      if (statusCode >= 400 && statusCode < 500) {
        throw _error(BalikobotError.rejected);
      }
      throw _error(BalikobotError.invalidResponse);
    }
    final _OrderResponse payload;
    try {
      payload = _orderResponse(_decode(response));
    } on FormatException {
      throw _error(BalikobotError.ambiguous);
    }
    final status = payload.status;
    if (status == null) {
      throw _error(BalikobotError.ambiguous);
    }
    switch (status) {
      case 200:
      case 208:
        if (payload.orderId.isEmpty ||
            !_validBranchField(payload.orderId, _identifierLimit)) {
          throw _error(BalikobotError.ambiguous);
        }
        return OrderResult(orderId: payload.orderId);
      case 426:
      case 503:
        throw _error(BalikobotError.unavailable);
      case 400:
      case 402:
      case 403:
      case 404:
      case 405:
      case 406:
      case 409:
      case 413:
      case 423:
        throw _error(BalikobotError.rejected);
      default:
        throw _error(BalikobotError.ambiguous);
    }
  }

  /// Calls the DROP method for one package that has not entered ORDER.
  ///
  /// A body status 404 means that the package is already gone and the call
  /// succeeds. A body status 405 marks a package that was already handed to
  /// the batch and throws a [BalikobotException] with
  /// [BalikobotError.rejected]. An invalid [carrier] or [packageId] throws a
  /// [BalikobotException] with [BalikobotError.invalidRequest] before any
  /// request is sent. [timeout] overrides the configured request timeout for
  /// this call.
  Future<void> dropPackage(
    Carrier carrier,
    String packageId, {
    Duration? timeout,
  }) async {
    if (!carrier.isValid || !_validPackageId(packageId)) {
      throw _error(BalikobotError.invalidRequest);
    }
    final RestResponse response;
    try {
      response = await _sendRequest(
        'POST',
        '/${carrier.value}/drop',
        body: {
          'package_ids': [packageId],
        },
        timeout: timeout,
      );
    } on _TransportFailure catch (failure) {
      throw _dispatchFailure(failure);
    } on ResponseLimitException {
      throw _error(BalikobotError.ambiguous);
    }
    final statusCode = response.statusCode;
    if (statusCode == 429) {
      throw _transient(response);
    }
    if (statusCode >= 500) {
      throw _error(BalikobotError.unavailable);
    }
    if (statusCode != 200 || !_isJson(response)) {
      if (statusCode >= 200 && statusCode < 300) {
        throw _error(BalikobotError.ambiguous);
      }
      if (statusCode >= 400 && statusCode < 500) {
        throw _error(BalikobotError.rejected);
      }
      throw _error(BalikobotError.invalidResponse);
    }
    final _DropResponse payload;
    try {
      payload = _dropResponse(_decode(response));
    } on FormatException {
      throw _error(BalikobotError.ambiguous);
    }
    final status = payload.status;
    if (status == null) {
      throw _error(BalikobotError.ambiguous);
    }
    switch (status) {
      case 200:
      case 404:
        return;
      case 426:
      case 503:
        throw _error(BalikobotError.unavailable);
      case 400:
      case 402:
      case 403:
      case 405:
      case 406:
      case 409:
      case 413:
      case 423:
        throw _error(BalikobotError.rejected);
      default:
        throw _error(BalikobotError.ambiguous);
    }
  }

  /// Calls the ORDERPICKUP method and books one physical collection.
  ///
  /// The supported [carrier] values are DPD, DPDCZ and PPL. DPD and DPDCZ take
  /// the collection address from the carrier configuration and always report
  /// a confirmed booking; PPL additionally requires a provider confirmation
  /// and pickup reference. An invalid [request] or an unsupported [carrier]
  /// throws a [BalikobotException] with [BalikobotError.rejected] before any
  /// request is sent. [timeout] overrides the configured request timeout for
  /// this call.
  Future<PickupResult> orderPickup(
    Carrier carrier,
    PickupRequest request, {
    Duration? timeout,
  }) async {
    if (!_validPickupRequest(carrier, request)) {
      throw _error(BalikobotError.rejected);
    }
    final RestResponse response;
    try {
      response = await _sendRequest(
        'POST',
        '/${carrier.value}/orderpickup',
        body: _pickupBody(carrier, request),
        timeout: timeout,
      );
    } on _AccountUnverified {
      throw _error(BalikobotError.rejected);
    } on _TransportFailure {
      throw _error(BalikobotError.ambiguous);
    } on ResponseLimitException {
      throw _error(BalikobotError.ambiguous);
    }
    if (response.statusCode != 200) {
      throw _pickupStatusError(response.statusCode);
    }
    if (!_isJson(response)) {
      throw _error(BalikobotError.ambiguous);
    }
    final _PickupResponse payload;
    try {
      payload = _pickupResponse(_decode(response));
    } on FormatException {
      throw _error(BalikobotError.ambiguous);
    }
    final status = payload.status;
    if (status == null) {
      throw _error(BalikobotError.ambiguous);
    }
    if (status != 200) {
      throw _pickupStatusError(status);
    }
    if (carrier != Carrier.ppl) {
      return const PickupResult(confirmed: true);
    }
    final providerId = payload.providerId;
    final confirmed = payload.confirmed;
    if (confirmed == null ||
        providerId.isEmpty ||
        !_validBranchField(providerId, _identifierLimit)) {
      throw _error(BalikobotError.ambiguous);
    }
    return PickupResult(providerId: providerId, confirmed: confirmed);
  }

  /// Calls the WHOAMI method and returns the account information.
  ///
  /// The returned carrier list contains every carrier contracted by the
  /// account. [timeout] overrides the configured request timeout for this
  /// call.
  Future<capabilities.WhoAmI> whoAmI({Duration? timeout}) async {
    final wire = _WhoAmIWire();
    await _capabilityGET('/info/whoami', wire, false, timeout: timeout);
    return capabilities.WhoAmI(
      status: wire.status!,
      liveAccount: wire.liveAccount,
      carriers: [
        for (final entry in wire.carriers)
          capabilities.WhoAmICarrier(
            slug: Carrier(entry.slug),
            name: entry.name,
          ),
      ],
    );
  }

  /// Calls the ACTIVATEDSERVICES method of [carrier] and returns the
  /// normalized activated services.
  ///
  /// When the provider reports that parcel shipping is inactive, the service
  /// list is empty. An invalid [carrier] throws a [BalikobotException] with
  /// [BalikobotError.invalidRequest] before any request is sent. [timeout]
  /// overrides the configured request timeout for this call.
  Future<capabilities.ActivatedServices> activatedServices(
    Carrier carrier, {
    Duration? timeout,
  }) async {
    if (!carrier.isValid) {
      throw _error(BalikobotError.invalidRequest);
    }
    final wire = _ActivatedServicesCapabilityResponse();
    await _capabilityGET(
      '/${carrier.value}/activatedservices',
      wire,
      false,
      timeout: timeout,
    );
    try {
      final (services, _) = _normalizeActivatedServices(wire);
      return capabilities.ActivatedServices(
        activeParcel: wire.activeParcel,
        services: services,
      );
    } on FormatException {
      throw _error(BalikobotError.invalidResponse);
    }
  }

  /// Calls the COUNTRIES4SERVICE method of [carrier] and returns the supported
  /// destination countries per service.
  ///
  /// Every country sent by the provider is kept, with surrounding whitespace
  /// trimmed and letters upper-cased. An invalid [carrier] throws a
  /// [BalikobotException] with [BalikobotError.invalidRequest] before any
  /// request is sent. [timeout] overrides the configured request timeout for
  /// this call.
  Future<List<capabilities.ServiceCountries>> countries(
    Carrier carrier, {
    Duration? timeout,
  }) async {
    if (!carrier.isValid) {
      throw _error(BalikobotError.invalidRequest);
    }
    final wire = _CountriesCapabilityResponse();
    await _capabilityGET(
      '/${carrier.value}/countries4service',
      wire,
      false,
      timeout: timeout,
    );
    if (wire.serviceTypes.length > _capabilityServiceLimit) {
      throw _error(BalikobotError.invalidResponse);
    }
    final result = <capabilities.ServiceCountries>[];
    for (final entry in wire.serviceTypes) {
      final code = entry.code;
      if (code == null) {
        throw _error(BalikobotError.invalidResponse);
      }
      final serviceType = code.trim();
      if (!_validCapabilityServiceCode(serviceType) ||
          entry.countries.length > _capabilityServiceLimit) {
        throw _error(BalikobotError.invalidResponse);
      }
      result.add(
        capabilities.ServiceCountries(
          serviceType: serviceType,
          countries: [
            for (final rawCountry in entry.countries)
              Country(rawCountry.trim().toUpperCase()),
          ],
        ),
      );
    }
    return result;
  }

  /// Calls the COD4SERVICES method of [carrier] and returns the normalized
  /// cash-on-delivery destinations per service.
  ///
  /// A carrier without the optional dictionary returns an empty list. An
  /// invalid [carrier] throws a [BalikobotException] with
  /// [BalikobotError.invalidRequest] before any request is sent. [timeout]
  /// overrides the configured request timeout for this call.
  Future<List<capabilities.ServiceCOD>> cod(
    Carrier carrier, {
    Duration? timeout,
  }) async {
    if (!carrier.isValid) {
      throw _error(BalikobotError.invalidRequest);
    }
    final wire = _CodCapabilityResponse();
    await _capabilityGET(
      '/${carrier.value}/cod4services',
      wire,
      true,
      timeout: timeout,
    );
    if (wire.serviceTypes.length > _capabilityServiceLimit) {
      throw _error(BalikobotError.invalidResponse);
    }
    final result = <capabilities.ServiceCOD>[];
    for (final entry in wire.serviceTypes) {
      final code = entry.code;
      if (code == null) {
        throw _error(BalikobotError.invalidResponse);
      }
      final serviceType = code.trim();
      if (!_validCapabilityServiceCode(serviceType) ||
          entry.countries.length > _capabilityServiceLimit) {
        throw _error(BalikobotError.invalidResponse);
      }
      try {
        result.add(
          capabilities.ServiceCOD(
            serviceType: serviceType,
            countries: _normalizeCODCountries(entry.countries),
          ),
        );
      } on FormatException {
        throw _error(BalikobotError.invalidResponse);
      }
    }
    return result;
  }

  /// Discovers the contracted carriers and their activated services in one
  /// run.
  ///
  /// Without [scope] the call discovers every carrier of the account; an
  /// explicit empty scope discovers none. Every requested carrier must belong
  /// to the account, otherwise the call throws a [BalikobotException] with
  /// [BalikobotError.invalidResponse]. The returned destinations are
  /// restricted to EU countries, matching the reference integration. [timeout]
  /// overrides the configured request timeout for this call.
  Future<List<capabilities.Carrier>> carrierCapabilities({
    List<Carrier>? scope,
    Duration? timeout,
  }) async {
    final whoami = await _verifiedWhoAmI(allowCached: false);
    final List<capabilities.Carrier> carriers;
    try {
      carriers = _scopedCapabilityCarriers(whoami.carriers, scope);
    } on FormatException {
      throw _error(BalikobotError.invalidResponse);
    }
    final result = <capabilities.Carrier>[];
    for (final carrier in carriers) {
      final carrierCode = carrier.carrierCode;
      final activated = _ActivatedServicesCapabilityResponse();
      final countries = _CountriesCapabilityResponse();
      await _capabilityGET(
        '/${carrierCode.value}/activatedservices',
        activated,
        false,
        timeout: timeout,
      );
      await _capabilityGET(
        '/${carrierCode.value}/countries4service',
        countries,
        false,
        timeout: timeout,
      );
      try {
        result.add(
          capabilities.Carrier(
            carrierCode: carrierCode,
            services: _normalizeCapabilities(
              activated,
              countries,
              _CodCapabilityResponse(),
            ),
          ),
        );
      } on FormatException {
        throw _error(BalikobotError.invalidResponse);
      }
    }
    return result;
  }

  Future<void> _capabilityGET(
    String path,
    _CapabilityStatusResponse target,
    bool allowUnsupported, {
    Duration? timeout,
  }) async {
    final RestResponse response;
    try {
      response = await _sendRequest('GET', path, timeout: timeout);
    } on _TransportFailure {
      throw _error(BalikobotError.unavailable);
    } on ResponseLimitException {
      throw _error(BalikobotError.unavailable);
    }
    final statusCode = response.statusCode;
    if (allowUnsupported && statusCode == 501) {
      return;
    }
    if (statusCode == 429 || statusCode >= 500) {
      throw _error(BalikobotError.unavailable);
    }
    if (statusCode != 200 || !_isJson(response)) {
      throw _error(BalikobotError.invalidResponse);
    }
    try {
      target.decodeFrom(_decode(response));
    } on FormatException {
      throw _error(BalikobotError.invalidResponse);
    }
    final status = target.status;
    if (status == 200 || (allowUnsupported && status == 501)) {
      return;
    }
    throw _error(BalikobotError.invalidResponse);
  }

  bool get _accountIsFresh {
    final verifiedAt = _accountVerifiedAt;
    if (verifiedAt == null) {
      return false;
    }
    final age = DateTime.now().difference(verifiedAt);
    return !age.isNegative && age < _accountModeTtl;
  }

  Future<void> _verifyWriteAllowed() async {
    try {
      await _verifiedWhoAmI(allowCached: true);
    } catch (_) {
      throw const _AccountUnverified();
    }
  }

  Future<_WhoAmIWire> _verifiedWhoAmI({required bool allowCached}) async {
    if (allowCached && _liveAccount == null) {
      return _WhoAmIWire();
    }
    if (allowCached && _accountIsFresh) {
      return _WhoAmIWire();
    }
    final inFlight = _accountCheckInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final check = _runAccountCheck();
    _accountCheckInFlight = check;
    try {
      return await check;
    } finally {
      _accountCheckInFlight = null;
    }
  }

  Future<_WhoAmIWire> _runAccountCheck() async {
    _accountVerifiedAt = null;
    final wire = _WhoAmIWire();
    await _capabilityGET('/info/whoami', wire, false);
    final expected = _liveAccount;
    if (expected != null) {
      final live = wire.liveAccount;
      if (live == null || live != expected) {
        throw _error(BalikobotError.invalidResponse);
      }
      _accountVerifiedAt = DateTime.now();
    }
    return wire;
  }
}

/// Derives the branch id that ADD expects from a stored branch of a carrier.
///
/// Česká pošta and Slovenská pošta use the branch ZIP without spaces, the
/// Uloženka `CP_NP` service does the same, PPL strips the `KM` prefix, and
/// every other carrier uses the stored branch id unchanged.
String resolveBranchId(
  Carrier carrier,
  String service,
  String branchId,
  String branchZip,
) {
  switch (carrier.value) {
    case 'cp':
    case 'sp':
      return branchZip.replaceAll(' ', '');
    case 'ulozenka':
      if (service == 'CP_NP') {
        return branchZip.replaceAll(' ', '');
      }
      return branchId;
    case 'ppl':
      return branchId.startsWith('KM') ? branchId.substring(2) : branchId;
    default:
      return branchId;
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

(String, String, bool) _validateBaseUrl(String raw) {
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
  return (baseUrl, '${parsed.scheme}://${parsed.authority}', loopback);
}

List<String> _normalizeLabelHosts(List<String> hosts) {
  final normalized = <String>[];
  for (final host in hosts) {
    final value = host.trim().toLowerCase();
    if (value.isEmpty ||
        value.contains('/') ||
        value.contains('\\') ||
        value.contains('@') ||
        value.contains('?') ||
        value.contains('#')) {
      throw ArgumentError(_labelHostMessage);
    }
    normalized.add(value);
  }
  return normalized;
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
const Duration _accountModeTtl = Duration(minutes: 5);
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
