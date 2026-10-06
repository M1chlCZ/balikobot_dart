/// An ISO 3166-1 alpha-2 country code.
///
/// A [Country] stays a plain string on the wire. Use the constants for common
/// destinations, or [fromString] for any other well-formed code.
class Country {
  /// Creates a country code with the given wire [value].
  const Country(this.value);

  /// Austria.
  static const Country at = Country('AT');

  /// Belgium.
  static const Country be = Country('BE');

  /// Bulgaria.
  static const Country bg = Country('BG');

  /// Croatia.
  static const Country hr = Country('HR');

  /// Cyprus.
  static const Country cy = Country('CY');

  /// Czechia.
  static const Country cz = Country('CZ');

  /// Denmark.
  static const Country dk = Country('DK');

  /// Estonia.
  static const Country ee = Country('EE');

  /// Finland.
  static const Country fi = Country('FI');

  /// France.
  static const Country fr = Country('FR');

  /// Germany.
  static const Country de = Country('DE');

  /// Greece.
  static const Country gr = Country('GR');

  /// Hungary.
  static const Country hu = Country('HU');

  /// Ireland.
  static const Country ie = Country('IE');

  /// Italy.
  static const Country it = Country('IT');

  /// Latvia.
  static const Country lv = Country('LV');

  /// Lithuania.
  static const Country lt = Country('LT');

  /// Luxembourg.
  static const Country lu = Country('LU');

  /// Malta.
  static const Country mt = Country('MT');

  /// The Netherlands.
  static const Country nl = Country('NL');

  /// Poland.
  static const Country pl = Country('PL');

  /// Portugal.
  static const Country pt = Country('PT');

  /// Romania.
  static const Country ro = Country('RO');

  /// Slovakia.
  static const Country sk = Country('SK');

  /// Slovenia.
  static const Country si = Country('SI');

  /// Spain.
  static const Country es = Country('ES');

  /// Sweden.
  static const Country se = Country('SE');

  /// The United Kingdom.
  static const Country gb = Country('GB');

  /// Switzerland.
  static const Country ch = Country('CH');

  /// Norway.
  static const Country no = Country('NO');

  /// Iceland.
  static const Country isIceland = Country('IS');

  /// Liechtenstein.
  static const Country li = Country('LI');

  /// Ukraine.
  static const Country ua = Country('UA');

  /// Serbia.
  static const Country rs = Country('RS');

  /// Bosnia and Herzegovina.
  static const Country ba = Country('BA');

  /// Montenegro.
  static const Country me = Country('ME');

  /// North Macedonia.
  static const Country mk = Country('MK');

  /// Albania.
  static const Country al = Country('AL');

  /// Türkiye.
  static const Country tr = Country('TR');

  /// The United States.
  static const Country us = Country('US');

  /// Canada.
  static const Country ca = Country('CA');

  /// The wire value of the code.
  final String value;

  /// Normalizes [value] and returns it as a [Country].
  ///
  /// The value is trimmed and uppercased. A malformed value throws a
  /// [FormatException].
  static Country fromString(String value) {
    final normalized = value.trim().toUpperCase();
    if (!_pattern.hasMatch(normalized)) {
      throw FormatException('country: "$value" is not a valid country code');
    }
    return Country(normalized);
  }

  /// Whether the wire value is a well-formed country code.
  bool get isValid => _pattern.hasMatch(value);

  /// Returns the wire value of the code.
  @override
  String toString() => value;

  /// Whether [other] is a country code with the same wire value.
  @override
  bool operator ==(Object other) => other is Country && other.value == value;

  /// The hash code of the wire value.
  @override
  int get hashCode => value.hashCode;
}

final RegExp _pattern = RegExp(r'^[A-Z]{2}$');
