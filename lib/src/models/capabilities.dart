import '../codes/carrier.dart' as codes;
import '../codes/country.dart';
import '../codes/currency.dart';

/// The account information returned by the WHOAMI method.
class WhoAmI {
  /// Creates account information.
  const WhoAmI({
    required this.status,
    this.liveAccount,
    this.carriers = const [],
  });

  /// The top-level provider status.
  final int status;

  /// Whether the credentials belong to a live account.
  ///
  /// It is null when the provider omits the flag.
  final bool? liveAccount;

  /// The carriers contracted by the account.
  final List<WhoAmICarrier> carriers;
}

/// One contracted carrier of the account.
class WhoAmICarrier {
  /// Creates a contracted carrier.
  const WhoAmICarrier({required this.slug, this.name = ''});

  /// The carrier code used in request paths.
  final codes.Carrier slug;

  /// The carrier display name. It can be empty.
  final String name;
}

/// The activated services of one contracted carrier.
class Carrier {
  /// Creates a carrier capability snapshot.
  const Carrier({required this.carrierCode, this.services = const []});

  /// The carrier code used in request paths.
  final codes.Carrier carrierCode;

  /// The activated services of the carrier.
  final List<Service> services;
}

/// Names the [Carrier] capability snapshot unambiguously.
///
/// The package also exports the carrier code class as `Carrier`, so this alias
/// is the public name of the aggregate type.
typedef CarrierCapabilities = Carrier;

/// One activated carrier service.
class Service {
  /// Creates an activated service.
  const Service({
    required this.code,
    required this.name,
    this.homeDelivery,
    this.boxDelivery,
    this.pickupPointsDelivery,
    this.countries = const {},
    this.cod = const [],
  });

  /// The provider service code.
  final String code;

  /// The provider service name.
  final String name;

  /// Whether the service supports home delivery.
  ///
  /// It is null when the provider did not declare the flag.
  final bool? homeDelivery;

  /// Whether the service supports box delivery.
  ///
  /// It is null when the provider did not declare the flag.
  final bool? boxDelivery;

  /// Whether the service supports pickup point delivery.
  ///
  /// It is null when the provider did not declare the flag.
  final bool? pickupPointsDelivery;

  /// The destination countries supported by the service.
  ///
  /// Carrier capabilities keep only EU destinations, matching the reference
  /// integration.
  final Map<Country, bool> countries;

  /// The supported cash-on-delivery destinations.
  ///
  /// The combined discovery leaves it empty because it does not request the
  /// optional COD dictionary.
  final List<CODCapability> cod;
}

/// One cash-on-delivery destination of a service.
class CODCapability {
  /// Creates a cash-on-delivery destination.
  const CODCapability({
    required this.country,
    required this.currency,
    required this.maxAmountMinor,
  });

  /// The ISO 3166-1 alpha-2 destination country.
  final Country country;

  /// The three-letter currency code.
  final Currency currency;

  /// The maximum cash-on-delivery amount in minor units, for example 149995
  /// for 1499.95 CZK.
  final int maxAmountMinor;

  /// Whether [other] is a destination with the same values.
  @override
  bool operator ==(Object other) =>
      other is CODCapability &&
      other.country == country &&
      other.currency == currency &&
      other.maxAmountMinor == maxAmountMinor;

  /// The hash code of the destination values.
  @override
  int get hashCode => Object.hash(country, currency, maxAmountMinor);
}

/// The ACTIVATEDSERVICES answer of one carrier.
class ActivatedServices {
  /// Creates an activated services answer.
  const ActivatedServices({this.activeParcel, this.services = const []});

  /// The provider flag that marks active parcel shipping.
  ///
  /// It is null when the provider omits the flag.
  final bool? activeParcel;

  /// The activated services.
  ///
  /// The countries and COD fields are empty; use carrier capabilities for the
  /// combined discovery.
  final List<Service> services;
}

/// One entry of the COUNTRIES4SERVICE answer.
class ServiceCountries {
  /// Creates a countries answer entry.
  const ServiceCountries({
    required this.serviceType,
    this.countries = const [],
  });

  /// The provider service code.
  final String serviceType;

  /// The destination country codes exactly as sent, with surrounding
  /// whitespace trimmed and letters upper-cased.
  final List<Country> countries;
}

/// One entry of the COD4SERVICES answer.
class ServiceCOD {
  /// Creates a cash-on-delivery answer entry.
  const ServiceCOD({required this.serviceType, this.countries = const []});

  /// The provider service code.
  final String serviceType;

  /// The normalized cash-on-delivery destinations.
  final List<CODCapability> countries;
}
