/// One physical collection booking for ORDERPICKUP.
class PickupRequest {
  /// Creates a pickup request.
  const PickupRequest({
    required this.date,
    required this.weightKg,
    required this.packageCount,
    this.note = '',
  });

  /// The collection date in the canonical `YYYY-MM-DD` format.
  final String date;

  /// The total collection weight in kilograms.
  ///
  /// It must be positive and at most 100000. DPD and DPDCZ send it; PPL takes
  /// the weight from its carrier configuration.
  final double weightKg;

  /// The number of packages.
  ///
  /// It must be positive and at most 10000. DPD and DPDCZ send it; PPL takes
  /// it from its carrier configuration.
  final int packageCount;

  /// The optional collection note.
  ///
  /// It must contain at most 255 valid characters without line breaks. DPD and
  /// DPDCZ send it as `message`; PPL sends it as `note`.
  final String note;
}

/// The confirmed collection booking.
class PickupResult {
  /// Creates a pickup result.
  const PickupResult({this.providerId = '', required this.confirmed});

  /// The provider pickup reference. PPL returns it; DPD and DPDCZ leave it
  /// empty.
  final String providerId;

  /// Whether the provider confirmed the booking.
  ///
  /// DPD and DPDCZ always confirm on success.
  final bool confirmed;
}
