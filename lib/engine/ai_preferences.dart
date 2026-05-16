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
  'sukhoi',
};
const _canadianManufacturers = {'bombardier', 'de havilland canada'};
const _brazilianManufacturers = {'embraer'};
const _chineseManufacturers = {'comac'};

// Former Soviet / CIS states — strong preference for Russian-origin aircraft.
const _cisCountries = {
  'RU', 'AM', 'AZ', 'BY', 'GE', 'KZ', 'KG', 'MD', 'TJ', 'TM', 'UA', 'UZ',
};

// Eastern European countries not in the EU/CIS — mild Russian lean, but
// increasingly Western after market liberalisation.
const _easternEuropeNonEU = {'RS', 'BA', 'AL', 'ME', 'MK', 'XK'};

// Gulf states — large Airbus widebody fleets (A380/A350) but also heavy
// Boeing 777/787 customers; model them as Airbus-leaning.
const _gulfCountries = {'AE', 'QA', 'BH', 'KW', 'OM'};

// Historically nationalised or state-influenced carriers that leaned Boeing
// for prestige/reliability in sub-Saharan Africa.
const _africaBoeingCountries = {'ET', 'KE', 'TZ', 'UG', 'ZM', 'ZW', 'GH', 'SN'};

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

// Adds a small stable per-airline taste variation (±6%) so not every AI
// airline in the same region buys identical fleets.
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

  // ── Country-specific rules (highest specificity) ─────────────────────────

  if (homeCountry == 'US') {
    // US carriers strongly favour domestic manufacturers; mild discount on Airbus.
    if (_usManufacturers.contains(manufacturer)) {
      weight = 1.38;
    } else if (manufacturer == 'airbus') {
      weight = 0.88;
    } else if (_canadianManufacturers.contains(manufacturer)) {
      weight = 1.05; // Bombardier regionals common in US
    }
  } else if (homeCountry != null && _cisCountries.contains(homeCountry)) {
    // Ex-Soviet states: strong Russian preference; discount on Western types.
    if (_russianManufacturers.contains(manufacturer)) {
      weight = 1.45;
    } else if (_usManufacturers.contains(manufacturer) ||
        manufacturer == 'airbus') {
      weight = 0.82;
    }
  } else if (homeCountry == 'CN') {
    // China: strong COMAC preference; Airbus accepted, Boeing neutral.
    if (_chineseManufacturers.contains(manufacturer)) {
      weight = 1.42;
    } else if (manufacturer == 'airbus') {
      weight = 1.08;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 0.95;
    }
  } else if (homeCountry == 'JP') {
    // Japan: historically Boeing-heavy (ANA/JAL 787, 777, 737).
    if (_usManufacturers.contains(manufacturer)) {
      weight = 1.32;
    } else if (manufacturer == 'airbus') {
      weight = 0.90;
    }
  } else if (homeCountry == 'IN') {
    // India: Airbus-dominant (IndiGo is one of the world's largest A320 operators).
    if (manufacturer == 'airbus') {
      weight = 1.35;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 0.95;
    }
  } else if (homeCountry == 'CA') {
    // Canada: domestic regional + proximity to US market.
    if (_canadianManufacturers.contains(manufacturer)) {
      weight = 1.35;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 1.12;
    }
  } else if (homeCountry == 'BR') {
    // Brazil: Embraer is a point of national pride.
    if (_brazilianManufacturers.contains(manufacturer)) {
      weight = 1.38;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 1.00;
    }
  } else if (homeCountry == 'AU' || homeCountry == 'NZ') {
    // Oceania: Qantas/Air NZ operate mixed Boeing/Airbus widebody fleets;
    // slight Airbus lean for narrowbody (A320 family popular regionally).
    if (manufacturer == 'airbus') {
      weight = 1.12;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 1.08;
    }
  } else if (homeCountry == 'TR') {
    // Turkey: Turkish Airlines has a large Airbus narrowbody fleet.
    if (manufacturer == 'airbus') {
      weight = 1.20;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 1.00;
    }
  } else if (homeCountry == 'IR') {
    // Iran: historically Boeing (pre-sanctions), then Airbus ATR deliveries;
    // now effectively forced toward older Western or Russian types.
    if (manufacturer == 'airbus' || manufacturer == 'atr') {
      weight = 1.18;
    } else if (_russianManufacturers.contains(manufacturer)) {
      weight = 1.15;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 0.75; // sanctions effectively block new Boeing deliveries
    }
  } else if (homeCountry == 'SA') {
    // Saudi Arabia: Saudia leans Boeing for wide-body prestige routes.
    if (_usManufacturers.contains(manufacturer)) {
      weight = 1.22;
    } else if (manufacturer == 'airbus') {
      weight = 1.05;
    }
  } else if (homeCountry != null && _gulfCountries.contains(homeCountry)) {
    // Gulf carriers: Airbus widebody (A380/A350) + Boeing 777/787 — model as
    // slight Airbus lean since Emirates/Qatar are the world's largest A380 operators.
    if (manufacturer == 'airbus') {
      weight = 1.22;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 1.12;
    }
  } else if (homeCountry != null && _africaBoeingCountries.contains(homeCountry)) {
    // Select African carriers (Ethiopian, Kenya Airways) have strong Boeing ties.
    if (_usManufacturers.contains(manufacturer)) {
      weight = 1.22;
    } else if (manufacturer == 'airbus') {
      weight = 0.98;
    }
  } else if (homeCountry != null && _easternEuropeNonEU.contains(homeCountry)) {
    // Western Balkans etc.: mixed fleets, mild Eastern lean.
    if (_europeanManufacturers.contains(manufacturer)) {
      weight = 1.15;
    } else if (_russianManufacturers.contains(manufacturer)) {
      weight = 1.10;
    }
  }

  // ── Region fallbacks (when no country rule matched above) ─────────────────

  else if (homeRegion == AirportRegion.europe) {
    // European carriers strongly favour Airbus; mild discount on Boeing.
    if (_europeanManufacturers.contains(manufacturer)) {
      weight = 1.32;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 0.92;
    }
  } else if (homeRegion == AirportRegion.northAmerica) {
    // North American carriers outside US/CA lean Boeing.
    if (_usManufacturers.contains(manufacturer)) {
      weight = 1.22;
    } else if (_canadianManufacturers.contains(manufacturer)) {
      weight = 1.16;
    }
  } else if (homeRegion == AirportRegion.asiaPacific) {
    // Asia Pacific: Airbus narrowbody dominant (AirAsia, Lion Air A320s);
    // slight overall Airbus lean, Boeing competitive for widebody.
    if (manufacturer == 'airbus') {
      weight = 1.15;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 1.05;
    }
  } else if (homeRegion == AirportRegion.middleEast) {
    // Middle East: Airbus A380/A350 dominance for flag carriers.
    if (manufacturer == 'airbus') {
      weight = 1.20;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 1.10;
    }
  } else if (homeRegion == AirportRegion.latinAmerica) {
    // Latin America: Embraer well-represented for regional routes;
    // trunk routes split between Boeing and Airbus.
    if (_brazilianManufacturers.contains(manufacturer)) {
      weight = 1.22;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 1.08;
    } else if (manufacturer == 'airbus') {
      weight = 1.05;
    }
  } else if (homeRegion == AirportRegion.africa) {
    // Africa: slight Boeing lean overall, Airbus competitive.
    if (_usManufacturers.contains(manufacturer)) {
      weight = 1.12;
    } else if (manufacturer == 'airbus') {
      weight = 1.05;
    }
  } else if (homeRegion == AirportRegion.oceania) {
    // Oceania: balanced mixed fleets.
    if (manufacturer == 'airbus') {
      weight = 1.10;
    } else if (_usManufacturers.contains(manufacturer)) {
      weight = 1.08;
    }
  }

  return weight * stableManufacturerTaste(airline, aircraftType);
}
