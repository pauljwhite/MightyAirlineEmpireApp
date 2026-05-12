import 'package:flutter_test/flutter_test.dart';
import 'package:mighty_airline_empire_app/core/airport_search.dart';
import 'package:mighty_airline_empire_app/core/format.dart';
import 'package:mighty_airline_empire_app/core/geo.dart';
import 'package:mighty_airline_empire_app/data/aircraft_types.dart';
import 'package:mighty_airline_empire_app/data/airports.dart';
import 'package:mighty_airline_empire_app/engine/ai_preferences.dart';
import 'package:mighty_airline_empire_app/engine/demand_model.dart';
import 'package:mighty_airline_empire_app/models/models.dart';

void main() {
  test('imports core web data into native Dart fixtures', () {
    expect(airports.length, greaterThan(100));
    expect(aircraftTypes.length, greaterThan(20));
    expect(airportsByIata['LHR']?.city, 'London');
    expect(aircraftTypesById['concorde']?.category, AircraftCategory.sst);
  });

  test('airport search prioritises exact airport codes', () {
    expect(searchAirports('jfk', airports).first.iata, 'JFK');
  });

  test('geo distance is plausible for London to New York', () {
    final lhr = airportsByIata['LHR']!;
    final jfk = airportsByIata['JFK']!;
    expect(haversineKm(lhr.lat, lhr.lon, jfk.lat, jfk.lon), closeTo(5540, 140));
  });

  test(
    'demand model favours domestic major routes over isolated small demand',
    () {
      final jfk = airportsByIata['JFK']!;
      final lax = airportsByIata['LAX']!;
      final small = airports.firstWhere(
        (a) => a.size == AirportSize.small && a.country != jfk.country,
      );
      expect(
        baselineDailyPassengers(jfk, lax),
        greaterThan(baselineDailyPassengers(jfk, small)),
      );
    },
  );

  test('currency formatter honours selected currency', () {
    final gbp = currencyOptions.firstWhere((c) => c.code == 'GBP');
    expect(money(1000000, gbp), startsWith('£'));
  });

  test('AI manufacturer preference follows home-market bias', () {
    const airline = Airline(
      id: 'preference-test',
      name: 'Preference Test',
      iataPrefix: 'PT',
      isPlayer: false,
      color: '#ffffff',
      logoEmoji: 'PT',
      cashUSD: 100000000,
      hubIatas: ['SVO'],
      foundedGameDay: 0,
    );
    final svo = airportsByIata['SVO']!;
    final jfk = airportsByIata['JFK']!;
    final gru = airportsByIata['GRU']!;
    final pek = airportsByIata['PEK']!;
    final tupolev = aircraftTypes.firstWhere(
      (t) => t.manufacturer == 'Tupolev',
    );
    final boeing = aircraftTypes.firstWhere((t) => t.manufacturer == 'Boeing');
    final embraer = aircraftTypes.firstWhere(
      (t) => t.manufacturer == 'Embraer',
    );
    final comac = aircraftTypes.firstWhere((t) => t.manufacturer == 'COMAC');

    expect(
      aiManufacturerPreferenceWeight(airline, tupolev, svo),
      greaterThan(aiManufacturerPreferenceWeight(airline, boeing, svo)),
    );
    expect(
      aiManufacturerPreferenceWeight(airline, boeing, jfk),
      greaterThan(aiManufacturerPreferenceWeight(airline, tupolev, jfk)),
    );
    expect(
      aiManufacturerPreferenceWeight(airline, embraer, gru),
      greaterThan(aiManufacturerPreferenceWeight(airline, boeing, gru)),
    );
    expect(
      aiManufacturerPreferenceWeight(airline, comac, pek),
      greaterThan(aiManufacturerPreferenceWeight(airline, boeing, pek)),
    );
  });
}
