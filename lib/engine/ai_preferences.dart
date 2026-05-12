import '../models/models.dart';

const _usManufacturers = {
  'boeing',
  'douglas',
  'mcdonnell douglas',
  'lockheed',
  'cessna',
  'piper',
};
const _europeanManufacturers = {
  'airbus',
  'atr',
  'fokker',
  'bac',
  'bae',
  'avro',
  'sud aviation',
  'aerospatiale/bac',
  'saab',
  'dassault',
};
const _russianManufacturers = {
  'tupolev',
  'ilyushin',
  'yakovlev',
  'antonov',
  'irkut',
};
const _canadianManufacturers = {'bombardier', 'de havilland canada'};
const _brazilianManufacturers = {'embraer'};
const _chineseManufacturers = {'comac'};
const _cisCountries = {
  'RU',
  'AM',
  'AZ',
  'BY',
  'GE',
  'KZ',
  'KG',
  'MD',
  'TJ',
  'TM',
  'UA',
  'UZ',
};

String normaliseManufacturer(String manufacturer) => manufacturer
    .toLowerCase()
    .replaceAll('é', 'e')
    .replaceAll('è', 'e')
    .replaceAll('ê', 'e')
    .replaceAll('ë', 'e')
    .replaceAll('á', 'a')
    .replaceAll('à', 'a')
    .replaceAll('â', 'a')
    .replaceAll('ä', 'a')
    .replaceAll('ó', 'o')
    .replaceAll('ò', 'o')
    .replaceAll('ô', 'o')
    .replaceAll('ö', 'o')
    .replaceAll('í', 'i')
    .replaceAll('ì', 'i')
    .replaceAll('î', 'i')
    .replaceAll('ï', 'i')
    .replaceAll('ú', 'u')
    .replaceAll('ù', 'u')
    .replaceAll('û', 'u')
    .replaceAll('ü', 'u')
    .trim();

int stableHash(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = ((hash << 5) - hash + unit) & 0x7fffffff;
  }
  return hash;
}

double stableManufacturerTaste(Airline airline, AircraftType aircraftType) {
  final hash = stableHash('${airline.id}:${aircraftType.manufacturer}');
  return 0.94 + (hash % 13) / 100;
}

double aiManufacturerPreferenceWeight(
  Airline airline,
  AircraftType aircraftType,
  Airport? homeAirport,
) {
  final homeCountry = homeAirport?.country;
  final homeRegion = homeAirport?.region;
  final manufacturer = normaliseManufacturer(aircraftType.manufacturer);
  var weight = 1.0;

  if (homeCountry == 'US') {
    if (_usManufacturers.contains(manufacturer)) {
      weight = 1.32;
    } else if (manufacturer == 'airbus') {
      weight = 0.96;
    }
  } else if (homeCountry != null && _cisCountries.contains(homeCountry)) {
    if (_russianManufacturers.contains(manufacturer)) {
      weight = 1.42;
    } else if (_usManufacturers.contains(manufacturer) ||
        manufacturer == 'airbus') {
      weight = 0.88;
    }
  } else if (homeCountry == 'CA') {
    if (_canadianManufacturers.contains(manufacturer)) {
      weight = 1.30;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 1.08;
    }
  } else if (homeCountry == 'BR') {
    if (_brazilianManufacturers.contains(manufacturer)) weight = 1.34;
  } else if (homeCountry == 'CN') {
    if (_chineseManufacturers.contains(manufacturer)) {
      weight = 1.35;
    } else if (manufacturer == 'airbus' ||
        _usManufacturers.contains(manufacturer)) {
      weight = 1.02;
    }
  } else if (homeRegion == AirportRegion.europe) {
    if (_europeanManufacturers.contains(manufacturer)) {
      weight = 1.30;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 0.96;
    }
  } else if (homeRegion == AirportRegion.northAmerica) {
    if (_usManufacturers.contains(manufacturer)) {
      weight = 1.22;
    } else if (_canadianManufacturers.contains(manufacturer)) {
      weight = 1.16;
    }
  }

  return weight * stableManufacturerTaste(airline, aircraftType);
}
