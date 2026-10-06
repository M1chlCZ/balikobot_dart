import '../codes/country.dart';
import '../codes/currency.dart';

/// One package for the ADD method.
///
/// The external reference [eid] makes ADD idempotent: a repeated request with
/// an already stored EID returns the original record.
class AddPackageRequest {
  /// Creates an ADD package request.
  const AddPackageRequest({
    required this.eid,
    required this.serviceType,
    this.recName = '',
    this.recFirm = '',
    required this.recStreet,
    required this.recCity,
    required this.recZip,
    required this.recCountry,
    this.recPhone = '',
    this.recEmail = '',
    this.branchId = '',
    required this.weight,
    required this.length,
    required this.width,
    required this.height,
    required this.price,
    this.codPrice = 0,
    required this.codCurrency,
    this.vs,
  });

  /// The external package reference.
  ///
  /// It must contain 8 to 40 alphanumeric or dash characters.
  final String eid;

  /// The carrier service code, for example `1` or `VMCZ`.
  final String serviceType;

  /// The recipient name.
  ///
  /// [recName] or [recFirm] must be set.
  final String recName;

  /// The recipient company.
  ///
  /// [recName] or [recFirm] must be set.
  final String recFirm;

  /// The recipient street. It is required.
  final String recStreet;

  /// The recipient city. It is required.
  final String recCity;

  /// The recipient postal code. It is required.
  final String recZip;

  /// The ISO 3166-1 alpha-2 destination country. It is required.
  final Country recCountry;

  /// The recipient phone.
  ///
  /// [recPhone] or [recEmail] must be set.
  final String recPhone;

  /// The recipient email.
  ///
  /// [recPhone] or [recEmail] must be set.
  final String recEmail;

  /// The pickup branch reference for branch delivery.
  final String branchId;

  /// The package weight in kilograms.
  ///
  /// It must be positive and at most 10000.
  final double weight;

  /// The package length in centimeters.
  ///
  /// It must be positive and at most 1000.
  final double length;

  /// The package width in centimeters.
  ///
  /// It must be positive and at most 1000.
  final double width;

  /// The package height in centimeters.
  ///
  /// It must be positive and at most 1000.
  final double height;

  /// The declared value. It must not be negative and at most 100000000.
  final double price;

  /// The cash-on-delivery amount.
  ///
  /// It must not be negative and at most 100000000. A positive amount
  /// requires [vs].
  final double codPrice;

  /// The cash-on-delivery currency.
  ///
  /// Balíkobot carriers validate this field even without a COD amount, so
  /// `CZK` or `EUR` is required on every ADD.
  final Currency codCurrency;

  /// The cash-on-delivery variable symbol.
  ///
  /// It must be set exactly when [codPrice] is positive and must be below
  /// 10000000000.
  final int? vs;

  /// Returns the JSON body of this package.
  Map<String, Object?> toJson() => {
    'eid': eid,
    'service_type': serviceType,
    if (recName.isNotEmpty) 'rec_name': recName,
    if (recFirm.isNotEmpty) 'rec_firm': recFirm,
    'rec_street': recStreet,
    'rec_city': recCity,
    'rec_zip': recZip,
    'rec_country': recCountry.value,
    if (recPhone.isNotEmpty) 'rec_phone': recPhone,
    if (recEmail.isNotEmpty) 'rec_email': recEmail,
    if (branchId.isNotEmpty) 'branch_id': branchId,
    'weight': weight,
    'length': length,
    'width': width,
    'height': height,
    'price': price,
    if (codPrice != 0) 'cod_price': codPrice,
    if (codCurrency.value.isNotEmpty) 'cod_currency': codCurrency.value,
    if (vs != null) 'vs': vs,
  };
}

/// The accepted package record returned by ADD.
class AddPackageResult {
  /// Creates an ADD result.
  const AddPackageResult({
    required this.packageId,
    required this.carrierId,
    required this.labelUrl,
  });

  /// The Balíkobot package reference used by labels, ORDER and DROP.
  final String packageId;

  /// The carrier tracking number.
  final String carrierId;

  /// The provider label URL for this package.
  final String labelUrl;
}

/// One open package entry returned by OVERVIEW.
class OverviewPackage {
  /// Creates an overview package.
  const OverviewPackage({
    required this.eid,
    required this.packageId,
    required this.carrierId,
    required this.labelUrl,
  });

  /// The external package reference stored by the provider.
  final String eid;

  /// The Balíkobot package reference.
  final String packageId;

  /// The carrier tracking number.
  final String carrierId;

  /// The provider label URL for this package.
  final String labelUrl;
}
