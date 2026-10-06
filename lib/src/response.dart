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
    } on RequestTimeoutException {
      throw const _TransportFailure();
    } on NetworkException {
      throw const _TransportFailure();
    } on IOException {
      throw const _TransportFailure();
    }
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

BalikobotException _error(
  BalikobotError code, [
  String message = '',
  Duration? retryAfter,
]) => BalikobotException(code, message, retryAfter);

class _TransportFailure implements Exception {
  const _TransportFailure();
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
    value.runes.length <= maximum &&
    !value.contains('\r') &&
    !value.contains('\n') &&
    !value.contains('\x00');

const int _branchFieldLimit = 200;
const int _zipLimit = 16;
final RegExp _servicePattern = RegExp(r'^[A-Za-z0-9]{1,16}$');
final RegExp _branchIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');
final RegExp _statusPattern = RegExp(r'^[0-9]{1,3}$');
