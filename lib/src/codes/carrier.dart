/// A carrier code used in Balíkobot request paths.
///
/// A [Carrier] stays a plain string on the wire. Use the constants for common
/// carriers, or [fromString] for any other well-formed code.
class Carrier {
  /// Creates a carrier code with the given wire [value].
  const Carrier(this.value);

  /// The PPL carrier.
  static const Carrier ppl = Carrier('ppl');

  /// The DPD carrier.
  static const Carrier dpd = Carrier('dpd');

  /// The DPD Czech Republic carrier.
  static const Carrier dpdcz = Carrier('dpdcz');

  /// The DPD Slovakia carrier.
  static const Carrier dpdsk = Carrier('dpdsk');

  /// The Geis carrier.
  static const Carrier geis = Carrier('geis');

  /// The GLS carrier.
  static const Carrier gls = Carrier('gls');

  /// The InTime carrier.
  static const Carrier intime = Carrier('intime');

  /// The Česká pošta carrier.
  static const Carrier cp = Carrier('cp');

  /// The alternative Česká pošta carrier.
  static const Carrier ceskaposta = Carrier('ceskaposta');

  /// The Balíkovna carrier.
  static const Carrier balikovna = Carrier('balikovna');

  /// The Zásilkovna carrier.
  static const Carrier zasilkovna = Carrier('zasilkovna');

  /// The Slovenská pošta carrier.
  static const Carrier sp = Carrier('sp');

  /// The Uloženka carrier.
  static const Carrier ulozenka = Carrier('ulozenka');

  /// The wire value of the code.
  final String value;

  /// Normalizes [value] and returns it as a [Carrier].
  ///
  /// The value is trimmed and lowercased. A malformed value throws a
  /// [FormatException].
  static Carrier fromString(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_pattern.hasMatch(normalized)) {
      throw FormatException('carrier: "$value" is not a valid carrier code');
    }
    return Carrier(normalized);
  }

  /// Whether the wire value is a well-formed carrier code.
  bool get isValid => _pattern.hasMatch(value);

  /// Returns the wire value of the code.
  @override
  String toString() => value;

  /// Whether [other] is a carrier code with the same wire value.
  @override
  bool operator ==(Object other) => other is Carrier && other.value == value;

  /// The hash code of the wire value.
  @override
  int get hashCode => value.hashCode;
}

final RegExp _pattern = RegExp(r'^[a-z0-9]{2,32}$');
