import '../codes/country.dart';

/// One carrier branch or pickup point.
class Branch {
  /// Creates a branch.
  const Branch({
    required this.id,
    this.type = '',
    this.name = '',
    this.street = '',
    this.city = '',
    this.zip = '',
    this.country = const Country(''),
    this.latitude,
    this.longitude,
  });

  /// The branch identifier used by the carrier.
  final String id;

  /// The provider branch type, for example `branch` or `box`.
  final String type;

  /// The display name.
  ///
  /// It falls back to [zip] when the provider sends no name.
  final String name;

  /// The street part of the address.
  final String street;

  /// The city part of the address.
  final String city;

  /// The postal code.
  final String zip;

  /// The ISO 3166-1 alpha-2 country code.
  ///
  /// It can be empty when the provider omits it for a domestic branch.
  final Country country;

  /// The GPS latitude when the provider sent a valid pair.
  final double? latitude;

  /// The GPS longitude when the provider sent a valid pair.
  final double? longitude;
}
