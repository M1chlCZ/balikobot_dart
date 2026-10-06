/// An ISO 4217 currency code.
///
/// A [Currency] stays a plain string on the wire. Use the constants for common
/// currencies, or [fromString] for any other well-formed code.
class Currency {
  /// Creates a currency code with the given wire [value].
  const Currency(this.value);

  /// The Czech koruna.
  static const Currency czk = Currency('CZK');

  /// The euro.
  static const Currency eur = Currency('EUR');

  /// The United States dollar.
  static const Currency usd = Currency('USD');

  /// The pound sterling.
  static const Currency gbp = Currency('GBP');

  /// The Polish złoty.
  static const Currency pln = Currency('PLN');

  /// The Hungarian forint.
  static const Currency huf = Currency('HUF');

  /// The Romanian leu.
  static const Currency ron = Currency('RON');

  /// The Bulgarian lev.
  static const Currency bgn = Currency('BGN');

  /// The Croatian kuna.
  static const Currency hrk = Currency('HRK');

  /// The Swiss franc.
  static const Currency chf = Currency('CHF');

  /// The Norwegian krone.
  static const Currency nok = Currency('NOK');

  /// The Swedish krona.
  static const Currency sek = Currency('SEK');

  /// The Danish krone.
  static const Currency dkk = Currency('DKK');

  /// The wire value of the code.
  final String value;

  /// Normalizes [value] and returns it as a [Currency].
  ///
  /// The value is trimmed and uppercased. A malformed value throws a
  /// [FormatException].
  static Currency fromString(String value) {
    final normalized = value.trim().toUpperCase();
    if (!_pattern.hasMatch(normalized)) {
      throw FormatException('currency: "$value" is not a valid currency code');
    }
    return Currency(normalized);
  }

  /// Whether the wire value is a well-formed currency code.
  bool get isValid => _pattern.hasMatch(value);

  /// Returns the wire value of the code.
  @override
  String toString() => value;

  /// Whether [other] is a currency code with the same wire value.
  @override
  bool operator ==(Object other) => other is Currency && other.value == value;

  /// The hash code of the wire value.
  @override
  int get hashCode => value.hashCode;
}

final RegExp _pattern = RegExp(r'^[A-Z]{3}$');
