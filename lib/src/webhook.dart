part of 'client.dart';

/// One package status change delivered to a Balíkobot tracking webhook.
///
/// At least one of [packageId], [eid] and [carrierId] identifies the package.
/// [statusId] and [statusText] describe the new provider status.
class TrackingNotification {
  /// Creates a tracking notification.
  const TrackingNotification({
    required this.packageId,
    required this.eid,
    required this.carrierId,
    required this.statusId,
    required this.statusText,
  });

  /// The Balíkobot package reference. It is empty when the notification
  /// identifies the package another way.
  final String packageId;

  /// The external package reference. It is empty when the notification
  /// identifies the package another way.
  final String eid;

  /// The carrier tracking number. It is empty when the notification identifies
  /// the package another way.
  final String carrierId;

  /// The raw provider status code, for example `1`, `1.2` or `-1`. The
  /// detailed `status_id_v2` value wins when both are present.
  final String statusId;

  /// The provider status description.
  final String statusText;
}

/// Parses the JSON body of a Balíkobot tracking webhook.
///
/// The function returns one [TrackingNotification] per status change. The body
/// can be a single notification object or an array of objects; an empty array
/// returns an empty result. Every entry must identify the package through
/// `package_id`, `eid` or `carrier_id`. Every entry must also carry a decimal
/// `status_id` or `status_id_v2` and a status description in `name` or
/// `status_text`. A malformed [body], a missing required field or more than
/// 1000 entries throws a [BalikobotException] with
/// [BalikobotError.invalidResponse].
List<TrackingNotification> parseTrackingNotifications(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) {
    throw _error(BalikobotError.invalidResponse);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    throw _error(BalikobotError.invalidResponse);
  }
  final List<Object?> entries;
  if (decoded is Map<String, dynamic>) {
    entries = [decoded];
  } else if (decoded is List) {
    entries = decoded;
  } else {
    throw _error(BalikobotError.invalidResponse);
  }
  if (entries.length > _trackingBatchLimit) {
    throw _error(BalikobotError.invalidResponse);
  }
  return [for (final entry in entries) _trackingNotification(entry)];
}

TrackingNotification _trackingNotification(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw _error(BalikobotError.invalidResponse);
  }
  final packageId = _trackingIdentifier(raw, 'package_id');
  final eid = _trackingIdentifier(raw, 'eid');
  final carrierId = _trackingIdentifier(raw, 'carrier_id');
  if (packageId == null && eid == null && carrierId == null) {
    throw _error(BalikobotError.invalidResponse);
  }
  final status =
      _trackingStatus(raw, 'status_id_v2') ?? _trackingStatus(raw, 'status_id');
  if (status == null) {
    throw _error(BalikobotError.invalidResponse);
  }
  final name = _trackingText(raw['name']);
  final statusText = name.isNotEmpty ? name : _trackingText(raw['status_text']);
  if (statusText.isEmpty || !_validBranchField(statusText, _branchFieldLimit)) {
    throw _error(BalikobotError.invalidResponse);
  }
  return TrackingNotification(
    packageId: packageId ?? '',
    eid: eid ?? '',
    carrierId: carrierId ?? '',
    statusId: status,
    statusText: statusText,
  );
}

String? _trackingIdentifier(Map<String, dynamic> raw, String key) {
  if (!raw.containsKey(key)) {
    return null;
  }
  final value = raw[key];
  if (value == null) {
    return null;
  }
  final String text;
  if (value is String) {
    text = value;
  } else if (value is int) {
    text = value.toString();
  } else {
    throw _error(BalikobotError.invalidResponse);
  }
  if (text.isEmpty) {
    return null;
  }
  if (!_validBranchField(text, _identifierLimit)) {
    throw _error(BalikobotError.invalidResponse);
  }
  return text;
}

String? _trackingStatus(Map<String, dynamic> raw, String key) {
  if (!raw.containsKey(key)) {
    return null;
  }
  final value = raw[key];
  if (value is int || value is double) {
    final text = value.toString();
    if (_trackStatusPattern.hasMatch(text)) {
      return text;
    }
  }
  throw _error(BalikobotError.invalidResponse);
}

String _trackingText(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value;
  }
  throw _error(BalikobotError.invalidResponse);
}
