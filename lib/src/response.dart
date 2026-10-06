part of 'client.dart';

extension on BalikobotClient {
  Future<RestResponse> _sendRequest(
    String method,
    String path, {
    Object? body,
    Duration? timeout,
  }) async {
    try {
      return await _rest.sendRaw(
        method,
        path: path,
        body: body,
        headers: const {'accept': 'application/json'},
        timeout: timeout,
        maxResponseBytes: _maxResponseBytes,
      );
    } on RequestTimeoutException catch (error) {
      throw _TransportFailure(error);
    } on NetworkException catch (error) {
      throw _TransportFailure(error);
    } on IOException catch (error) {
      throw _TransportFailure(error);
    }
  }

  bool _validLabelUrl(String raw) {
    final Uri parsed;
    try {
      parsed = Uri.parse(raw);
    } on FormatException {
      return false;
    }
    if (parsed.userInfo.isNotEmpty ||
        parsed.fragment.isNotEmpty ||
        parsed.path.isEmpty) {
      return false;
    }
    if (parsed.query.isNotEmpty && parsed.query != 'zpl=1') {
      return false;
    }
    if (_labelHosts.isNotEmpty) {
      return _labelHostAllowed(parsed);
    }
    if (_loopback) {
      return '${parsed.scheme}://${parsed.authority}' == _origin;
    }
    return parsed.scheme == 'https' &&
        (parsed.authority == 'pdf.balikobot.cz' ||
            parsed.authority.endsWith('.balikobot.cz'));
  }

  bool _labelHostAllowed(Uri parsed) {
    if (!_labelSchemeAllowed(parsed)) {
      return false;
    }
    final host = parsed.authority.toLowerCase();
    final hostname = parsed.host.toLowerCase();
    for (final allowed in _labelHosts) {
      final matches = allowed.startsWith('.')
          ? hostname.endsWith(allowed)
          : host == allowed;
      if (matches) {
        return true;
      }
    }
    return false;
  }

  bool _labelSchemeAllowed(Uri parsed) {
    if (parsed.scheme == 'https') {
      return true;
    }
    if (parsed.scheme != 'http') {
      return false;
    }
    final address = InternetAddress.tryParse(parsed.host);
    return address != null && address.isLoopback;
  }
}

bool _isJson(RestResponse response) {
  final header = response.headers['content-type'];
  if (header == null) {
    return false;
  }
  final parts = header.split(';');
  if (parts.first.trim().toLowerCase() != 'application/json') {
    return false;
  }
  for (final parameter in parts.skip(1)) {
    final trimmed = parameter.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (trimmed.indexOf('=') <= 0) {
      return false;
    }
  }
  return true;
}

Object? _decode(RestResponse response) => jsonDecode(response.body);

Duration? _retryAfter(RestResponse response) {
  final header = response.headers['retry-after'];
  if (header == null) {
    return null;
  }
  final seconds = int.tryParse(header.trim());
  if (seconds == null || seconds < 1) {
    return null;
  }
  return Duration(seconds: seconds > 3600 ? 3600 : seconds);
}

BalikobotException _error(
  BalikobotError code, [
  String message = '',
  Duration? retryAfter,
]) => BalikobotException(code, message, retryAfter);

BalikobotException _transient(RestResponse response) =>
    _error(BalikobotError.unavailable, '', _retryAfter(response));

BalikobotException _dispatchFailure(_TransportFailure failure) {
  final cause = failure.cause;
  if (cause is RequestTimeoutException) {
    return _error(BalikobotError.ambiguous);
  }
  if (cause is NetworkException) {
    final message = cause.message;
    if (message.contains('Connection refused') ||
        message.contains('Failed host lookup')) {
      return _error(BalikobotError.unavailable);
    }
  }
  return _error(BalikobotError.ambiguous);
}

class _TransportFailure implements Exception {
  const _TransportFailure(this.cause);

  final Object cause;
}

bool _validAddPackage(AddPackageRequest request) {
  if (!_eidPattern.hasMatch(request.eid) ||
      !_servicePattern.hasMatch(request.serviceType) ||
      (request.recName.isEmpty && request.recFirm.isEmpty) ||
      (request.recPhone.isEmpty && request.recEmail.isEmpty) ||
      (request.codCurrency != Currency.czk &&
          request.codCurrency != Currency.eur) ||
      (request.codPrice > 0 && request.vs == null) ||
      (request.codPrice == 0 && request.vs != null)) {
    return false;
  }
  for (final field in [
    request.recName,
    request.recFirm,
    request.recStreet,
    request.recCity,
    request.recZip,
    request.recPhone,
    request.recEmail,
  ]) {
    if (!_validBranchField(field, _addFieldLimit)) {
      return false;
    }
  }
  if (request.recStreet.isEmpty ||
      request.recCity.isEmpty ||
      request.recZip.isEmpty ||
      !request.recCountry.isValid) {
    return false;
  }
  if (request.branchId.isNotEmpty &&
      !_branchIdPattern.hasMatch(request.branchId)) {
    return false;
  }
  if (request.weight <= 0 ||
      request.weight > 10000 ||
      request.length <= 0 ||
      request.length > 1000 ||
      request.width <= 0 ||
      request.width > 1000 ||
      request.height <= 0 ||
      request.height > 1000) {
    return false;
  }
  if (request.price < 0 ||
      request.price > 100000000 ||
      request.codPrice < 0 ||
      request.codPrice > 100000000) {
    return false;
  }
  final vs = request.vs;
  if (vs != null && (vs < 0 || vs >= _trackReferenceModulus)) {
    return false;
  }
  return true;
}

bool _validPackageId(String value) =>
    value.isNotEmpty && _validBranchField(value, _identifierLimit);

String _packageId(Object? raw) {
  final String text;
  if (raw is String) {
    text = raw;
  } else if (raw is int) {
    text = raw.toString();
  } else {
    throw const FormatException('invalid Balíkobot package id');
  }
  if (!_validPackageId(text)) {
    throw const FormatException('invalid Balíkobot package id');
  }
  return text;
}

bool _validPickupRequest(Carrier carrier, PickupRequest request) {
  if (carrier != Carrier.dpdcz &&
      carrier != Carrier.dpd &&
      carrier != Carrier.ppl) {
    return false;
  }
  final match = _pickupDatePattern.firstMatch(request.date);
  if (match == null) {
    return false;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return false;
  }
  return request.packageCount >= 1 &&
      request.packageCount <= _pickupPackageLimit &&
      request.weightKg > 0 &&
      request.weightKg <= _pickupWeightLimit &&
      !request.weightKg.isNaN &&
      _validBranchField(request.note, _pickupNoteLimit);
}

Map<String, Object> _pickupBody(Carrier carrier, PickupRequest request) {
  final body = <String, Object>{'date': request.date};
  var noteField = 'note';
  if (carrier != Carrier.ppl) {
    body['weight'] = request.weightKg;
    body['package_count'] = request.packageCount;
    noteField = 'message';
  }
  if (request.note.isNotEmpty) {
    body[noteField] = request.note;
  }
  return body;
}

BalikobotException _pickupStatusError(int status) {
  switch (status) {
    case 400:
    case 401:
    case 403:
    case 404:
    case 405:
    case 413:
    case 415:
    case 422:
    case 429:
      return _error(BalikobotError.rejected);
    default:
      return _error(BalikobotError.ambiguous);
  }
}

class _AddPackageStatus {
  const _AddPackageStatus({
    required this.eid,
    required this.status,
    required this.packageId,
    required this.carrierId,
    required this.labelUrl,
  });

  final String eid;
  final int? status;
  final String? packageId;
  final String carrierId;
  final String labelUrl;
}

class _AddResponse {
  const _AddResponse({required this.status, required this.packages});

  final int? status;
  final List<_AddPackageStatus> packages;
}

class _OverviewPackageStatus {
  const _OverviewPackageStatus({
    required this.eid,
    required this.packageId,
    required this.carrierId,
    required this.labelUrl,
  });

  final String eid;
  final String? packageId;
  final String carrierId;
  final String labelUrl;
}

class _OverviewResponse {
  const _OverviewResponse({required this.status, required this.packages});

  final int? status;
  final List<_OverviewPackageStatus> packages;
}

class _LabelsResponse {
  const _LabelsResponse({required this.status, required this.labelsUrl});

  final int? status;
  final String labelsUrl;
}

class _OrderViewResponse {
  const _OrderViewResponse({
    required this.status,
    required this.orderId,
    required this.packageIds,
    required this.labelsUrl,
  });

  final int? status;
  final String orderId;
  final List<String> packageIds;
  final String labelsUrl;
}

class _TrackStatusResponse {
  const _TrackStatusResponse({required this.status, required this.packages});

  final int? status;
  final List<_TrackStatusPackage> packages;
}

class _TrackStatusPackage {
  const _TrackStatusPackage({
    required this.carrierId,
    required this.statusId,
    required this.statusIdV2,
    required this.name,
    required this.statusText,
    required this.status,
  });

  final String carrierId;
  final String? statusId;
  final String? statusIdV2;
  final String name;
  final String statusText;
  final int? status;
}

class _OrderResponse {
  const _OrderResponse({required this.status, required this.orderId});

  final int? status;
  final String orderId;
}

class _DropResponse {
  const _DropResponse({required this.status});

  final int? status;
}

class _PickupResponse {
  const _PickupResponse({
    required this.status,
    required this.providerId,
    required this.confirmed,
  });

  final int? status;
  final String providerId;
  final bool? confirmed;
}

_AddResponse _addResponse(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('invalid Balíkobot add response');
  }
  return _AddResponse(
    status: _wireStatus(raw),
    packages: _addPackageStatuses(raw['packages']),
  );
}

_AddPackageStatus _addPackageStatus(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('invalid Balíkobot add package');
  }
  return _AddPackageStatus(
    eid: _wireString(raw['eid']),
    status: _wireStatus(raw),
    packageId: raw.containsKey('package_id')
        ? _packageId(raw['package_id'])
        : null,
    carrierId: _wireString(raw['carrier_id']),
    labelUrl: _wireString(raw['label_url']),
  );
}

List<_AddPackageStatus> _addPackageStatuses(Object? raw) {
  if (raw == null) {
    return const [];
  }
  if (raw is! List) {
    throw const FormatException('invalid Balíkobot add packages');
  }
  return [for (final entry in raw) _addPackageStatus(entry)];
}

_OverviewResponse _overviewResponse(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('invalid Balíkobot overview response');
  }
  return _OverviewResponse(
    status: _wireStatus(raw),
    packages: _overviewPackageStatuses(raw['packages']),
  );
}

_OverviewPackageStatus _overviewPackageStatus(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('invalid Balíkobot overview package');
  }
  return _OverviewPackageStatus(
    eid: _wireString(raw['eid']),
    packageId: raw.containsKey('package_id')
        ? _packageId(raw['package_id'])
        : null,
    carrierId: _wireString(raw['carrier_id']),
    labelUrl: _wireString(raw['label_url']),
  );
}

List<_OverviewPackageStatus> _overviewPackageStatuses(Object? raw) {
  if (raw == null) {
    return const [];
  }
  if (raw is! List) {
    throw const FormatException('invalid Balíkobot overview packages');
  }
  return [for (final entry in raw) _overviewPackageStatus(entry)];
}

_LabelsResponse _labelsResponse(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('invalid Balíkobot labels response');
  }
  return _LabelsResponse(
    status: _wireStatus(raw),
    labelsUrl: _wireString(raw['labels_url']),
  );
}

_OrderViewResponse _orderViewResponse(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('invalid Balíkobot order view response');
  }
  return _OrderViewResponse(
    status: _wireStatus(raw),
    orderId: _wireString(raw['order_id']),
    packageIds: _packageIdList(raw['package_ids']),
    labelsUrl: _wireString(raw['labels_url']),
  );
}

List<String> _packageIdList(Object? raw) {
  if (raw == null) {
    return const [];
  }
  if (raw is! List) {
    throw const FormatException('invalid Balíkobot package ids');
  }
  return [for (final entry in raw) _packageId(entry)];
}

_TrackStatusResponse _trackStatusResponse(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('invalid Balíkobot track status response');
  }
  return _TrackStatusResponse(
    status: _wireStatus(raw),
    packages: _trackStatusPackages(raw['packages']),
  );
}

_TrackStatusPackage _trackStatusPackage(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('invalid Balíkobot track status package');
  }
  return _TrackStatusPackage(
    carrierId: _wireString(raw['carrier_id']),
    statusId: raw.containsKey('status_id')
        ? _trackStatusId(raw['status_id'])
        : null,
    statusIdV2: raw.containsKey('status_id_v2')
        ? _trackStatusId(raw['status_id_v2'])
        : null,
    name: _wireString(raw['name']),
    statusText: _wireString(raw['status_text']),
    status: _wireStatus(raw),
  );
}

List<_TrackStatusPackage> _trackStatusPackages(Object? raw) {
  if (raw == null) {
    return const [];
  }
  if (raw is! List) {
    throw const FormatException('invalid Balíkobot track status packages');
  }
  return [for (final entry in raw) _trackStatusPackage(entry)];
}

String _trackStatusId(Object? raw) {
  final String text;
  if (raw is int) {
    text = raw.toString();
  } else if (raw is double) {
    text = raw.toString();
  } else {
    throw const FormatException('invalid Balíkobot track status id');
  }
  if (!_trackStatusPattern.hasMatch(text)) {
    throw const FormatException('invalid Balíkobot track status id');
  }
  return text;
}

_OrderResponse _orderResponse(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('invalid Balíkobot order response');
  }
  return _OrderResponse(
    status: _wireStatus(raw),
    orderId: _wireString(raw['order_id']),
  );
}

_DropResponse _dropResponse(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('invalid Balíkobot drop response');
  }
  return _DropResponse(status: _wireStatus(raw));
}

_PickupResponse _pickupResponse(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('invalid Balíkobot pickup response');
  }
  return _PickupResponse(
    status: _wireStatus(raw),
    providerId: _wireString(raw['pickup_order_id']),
    confirmed: _wireBool(raw['confirmed']),
  );
}

int? _wireStatus(Map<String, dynamic> raw) =>
    raw.containsKey('status') ? _responseStatus(raw['status']) : null;

BalikobotException? _topLevelStatusError(int? status) {
  if (status == null) {
    return null;
  }
  switch (status) {
    case 200:
    case 208:
      return null;
    case 426:
    case 503:
      return _error(BalikobotError.unavailable);
    case 400:
    case 402:
    case 403:
    case 404:
    case 405:
    case 406:
    case 409:
    case 413:
    case 423:
    case 501:
      return _error(BalikobotError.rejected);
    default:
      return _error(BalikobotError.invalidResponse);
  }
}

BalikobotException? _labelLookupStatus(RestResponse response) {
  final statusCode = response.statusCode;
  if (statusCode == 429) {
    return _transient(response);
  }
  if (statusCode >= 500) {
    return _error(BalikobotError.unavailable);
  }
  if (statusCode != 200 || !_isJson(response)) {
    if (statusCode >= 400 && statusCode < 500) {
      return _error(BalikobotError.rejected);
    }
    return _error(BalikobotError.invalidResponse);
  }
  return null;
}

BalikobotException? _trackHttpStatus(RestResponse response) {
  final statusCode = response.statusCode;
  if (statusCode == 429) {
    return _transient(response);
  }
  if (statusCode >= 500) {
    return _error(BalikobotError.unavailable);
  }
  if (statusCode == 404) {
    return _error(BalikobotError.notFound);
  }
  if (statusCode != 200 || !_isJson(response)) {
    if (statusCode >= 400 && statusCode < 500) {
      return _error(BalikobotError.unavailable);
    }
    return _error(BalikobotError.invalidResponse);
  }
  return null;
}

Future<Uint8List> _readLimited(
  http.StreamedResponse response,
  int limit,
) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in response.stream) {
    builder.add(chunk);
    if (builder.length > limit) {
      throw ResponseLimitException(
        'Balíkobot response exceeds $limit bytes',
        statusCode: response.statusCode,
        headers: response.headers,
      );
    }
  }
  return builder.takeBytes();
}

String? _labelMediaType(String? header) {
  if (header == null) {
    return null;
  }
  final parts = header.split(';');
  final mediaType = parts.first.trim().toLowerCase();
  for (final parameter in parts.skip(1)) {
    final trimmed = parameter.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (trimmed.indexOf('=') <= 0) {
      return null;
    }
  }
  return mediaType;
}

bool _hasPrefix(Uint8List bytes, String prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix.codeUnitAt(index)) {
      return false;
    }
  }
  return true;
}

class _BranchWire {
  const _BranchWire({
    required this.type,
    required this.branchId,
    required this.id,
    required this.name,
    required this.street,
    required this.city,
    required this.zip,
    required this.country,
    required this.lat,
    required this.lng,
    required this.latitude,
    required this.longitude,
  });

  const _BranchWire.empty()
    : type = '',
      branchId = null,
      id = null,
      name = '',
      street = '',
      city = '',
      zip = '',
      country = '',
      lat = null,
      lng = null,
      latitude = null,
      longitude = null;

  final String type;
  final String? branchId;
  final String? id;
  final String name;
  final String street;
  final String city;
  final String zip;
  final String country;
  final double? lat;
  final double? lng;
  final double? latitude;
  final double? longitude;
}

({int status, List<_BranchWire> branches}) _branchesResponse(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('invalid Balíkobot branches response');
  }
  return (
    status: _responseStatus(raw['status']),
    branches: _branchList(raw['branches']),
  );
}

int _responseStatus(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is String && _statusPattern.hasMatch(raw)) {
    return int.parse(raw);
  }
  throw const FormatException('invalid Balíkobot response status');
}

List<_BranchWire> _branchList(Object? raw) {
  if (raw == null) {
    return const [];
  }
  if (raw is List) {
    return [for (final entry in raw) _branchWire(entry)];
  }
  if (raw is Map<String, dynamic>) {
    final keys = raw.keys.toList()..sort(_compareBranchKeys);
    return [for (final key in keys) _branchWire(raw[key])];
  }
  throw const FormatException('invalid Balíkobot branches list');
}

int _compareBranchKeys(String left, String right) {
  final leftNumber = int.tryParse(left);
  final rightNumber = int.tryParse(right);
  if (leftNumber != null && rightNumber != null) {
    return leftNumber.compareTo(rightNumber);
  }
  if (leftNumber != null) {
    return -1;
  }
  if (rightNumber != null) {
    return 1;
  }
  return left.compareTo(right);
}

_BranchWire _branchWire(Object? raw) {
  if (raw == null) {
    return const _BranchWire.empty();
  }
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('invalid Balíkobot branch');
  }
  return _BranchWire(
    type: _wireString(raw['type']),
    branchId: _branchId(raw['branch_id']),
    id: _branchId(raw['id']),
    name: _wireString(raw['name']),
    street: _wireString(raw['street']),
    city: _wireString(raw['city']),
    zip: _wireString(raw['zip']),
    country: _wireString(raw['country']),
    lat: _coordinate(raw['lat']),
    lng: _coordinate(raw['lng']),
    latitude: _coordinate(raw['latitude']),
    longitude: _coordinate(raw['longitude']),
  );
}

String _wireString(Object? raw) {
  if (raw == null) {
    return '';
  }
  if (raw is String) {
    return raw;
  }
  throw const FormatException('invalid Balíkobot branch field');
}

bool? _wireBool(Object? raw) {
  if (raw == null) {
    return null;
  }
  if (raw is bool) {
    return raw;
  }
  throw const FormatException('invalid Balíkobot boolean field');
}

String? _branchId(Object? raw) {
  if (raw == null) {
    return null;
  }
  final String text;
  if (raw is String) {
    text = raw;
  } else if (raw is int) {
    text = raw.toString();
  } else {
    throw const FormatException('invalid Balíkobot branch id');
  }
  return _branchIdPattern.hasMatch(text) ? text : null;
}

double? _coordinate(Object? raw) {
  if (raw is num) {
    return raw.toDouble();
  }
  if (raw is String) {
    return double.tryParse(raw.trim());
  }
  return null;
}

Branch? _sanitizeBranch(_BranchWire wire) {
  final id = wire.branchId ?? wire.id;
  if (id == null) {
    return null;
  }
  if (!_validBranchField(wire.name, _branchFieldLimit) ||
      !_validBranchField(wire.street, _branchFieldLimit) ||
      !_validBranchField(wire.city, _branchFieldLimit) ||
      !_validBranchField(wire.zip, _zipLimit)) {
    return null;
  }
  var name = wire.name;
  if (name.isEmpty) {
    name = wire.zip;
  }
  if (name.isEmpty) {
    return null;
  }
  final country = Country(wire.country);
  if (wire.country.isNotEmpty && !country.isValid) {
    return null;
  }
  final coordinates = _branchCoordinates(wire);
  return Branch(
    id: id,
    type: wire.type,
    name: name,
    street: wire.street,
    city: wire.city,
    zip: wire.zip,
    country: country,
    latitude: coordinates.latitude,
    longitude: coordinates.longitude,
  );
}

({double? latitude, double? longitude}) _branchCoordinates(_BranchWire wire) {
  final pairs = [(wire.lat, wire.lng), (wire.latitude, wire.longitude)];
  for (final (latitude, longitude) in pairs) {
    if (latitude != null &&
        longitude != null &&
        _validCoordinates(latitude, longitude)) {
      return (latitude: latitude, longitude: longitude);
    }
  }
  return (latitude: null, longitude: null);
}

bool _validCoordinates(double latitude, double longitude) =>
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180 &&
    (latitude != 0 || longitude != 0);

bool _validBranchField(String value, int maximum) =>
    _validUtf8(value) &&
    value.runes.length <= maximum &&
    !value.contains('\r') &&
    !value.contains('\n') &&
    !value.contains('\x00');

bool _validUtf8(String value) {
  for (var index = 0; index < value.length; index++) {
    final code = value.codeUnitAt(index);
    if (code >= 0xd800 && code <= 0xdbff) {
      if (index + 1 >= value.length) {
        return false;
      }
      final next = value.codeUnitAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) {
        return false;
      }
      index++;
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      return false;
    }
  }
  return true;
}

const int _branchFieldLimit = 200;
const int _zipLimit = 16;
const int _addFieldLimit = 255;
const int _identifierLimit = 100;
const int _labelResponseLimit = 4 << 20;
const int _trackReferenceModulus = 10000000000;
const int _pickupPackageLimit = 10000;
const int _pickupWeightLimit = 100000;
const int _pickupNoteLimit = 255;
const String _pdfMediaType = 'application/pdf';
const String _zplMediaType = 'application/zpl';
const String _pdfMagicPrefix = '%PDF-';
const String _zplMagicPrefix = '^X';
final RegExp _servicePattern = RegExp(r'^[A-Za-z0-9]{1,16}$');
final RegExp _branchIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');
final RegExp _eidPattern = RegExp(r'^[A-Za-z0-9-]{8,40}$');
final RegExp _statusPattern = RegExp(r'^[0-9]{1,3}$');
final RegExp _trackStatusPattern = RegExp(r'^-?[0-9]{1,3}(\.[0-9]{1,2})?$');
final RegExp _pickupDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
