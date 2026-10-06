import 'package:balikobot_dart/balikobot_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Carrier', () {
    test('constant round-trips as the wire value', () {
      expect(Carrier.ppl.toString(), 'ppl');
    });

    test('fromString trims and lowercases a custom value', () {
      final carrier = Carrier.fromString(' MyCarrier99 ');
      expect(carrier, const Carrier('mycarrier99'));
      expect(carrier.hashCode, const Carrier('mycarrier99').hashCode);
      expect(carrier.toString(), 'mycarrier99');
    });

    test('fromString throws for a malformed value', () {
      expect(() => Carrier.fromString('p'), throwsFormatException);
    });

    test('isValid checks the wire value', () {
      expect(Carrier.ppl.isValid, isTrue);
      expect(const Carrier('PPL').isValid, isFalse);
    });
  });

  group('Currency', () {
    test('constant round-trips as the wire value', () {
      expect(Currency.czk.toString(), 'CZK');
    });

    test('fromString trims and uppercases a custom value', () {
      final currency = Currency.fromString(' eur ');
      expect(currency, const Currency('EUR'));
      expect(currency.hashCode, const Currency('EUR').hashCode);
      expect(currency.toString(), 'EUR');
    });

    test('fromString throws for a malformed value', () {
      expect(() => Currency.fromString('EU'), throwsFormatException);
    });

    test('isValid checks the wire value', () {
      expect(Currency.czk.isValid, isTrue);
      expect(const Currency('EU').isValid, isFalse);
    });
  });

  group('Country', () {
    test('constant round-trips as the wire value', () {
      expect(Country.cz.toString(), 'CZ');
    });

    test('fromString trims and uppercases a custom value', () {
      final country = Country.fromString(' de ');
      expect(country, const Country('DE'));
      expect(country.hashCode, const Country('DE').hashCode);
      expect(country.toString(), 'DE');
    });

    test('fromString throws for a malformed value', () {
      expect(() => Country.fromString('CZE'), throwsFormatException);
    });

    test('isValid checks the wire value', () {
      expect(Country.cz.isValid, isTrue);
      expect(const Country('CZE').isValid, isFalse);
    });
  });
}
