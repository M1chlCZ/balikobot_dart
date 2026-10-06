/// The latest provider tracking status of one package.
class TrackStatusResult {
  /// Creates a tracking status result.
  const TrackStatusResult({required this.statusId, required this.statusText});

  /// The raw provider status code, for example `1`, `1.2` or `-1`.
  final String statusId;

  /// The provider status description.
  final String statusText;
}

/// The batch reference returned by ORDER.
class OrderResult {
  /// Creates an order result.
  const OrderResult({required this.orderId});

  /// The provider batch identifier.
  final String orderId;
}
