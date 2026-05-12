enum AirportSize { small, medium, large, major }

enum AirportRegion {
  northAmerica,
  europe,
  asiaPacific,
  middleEast,
  africa,
  latinAmerica,
  oceania,
}

enum AircraftCategory { regional, narrowbody, widebody, sst }

class Airport {
  const Airport({
    required this.iata,
    this.icao,
    required this.name,
    required this.city,
    required this.country,
    required this.lat,
    required this.lon,
    this.longestRunwayM,
    required this.size,
    required this.region,
    required this.landingFee,
    this.isHub = false,
    this.hubTerminalLevel = 0,
    this.firstClassLoungeLevel = 0,
  });

  final String iata;
  final String? icao;
  final String name;
  final String city;
  final String country;
  final double lat;
  final double lon;
  final int? longestRunwayM;
  final AirportSize size;
  final AirportRegion region;
  final int landingFee;
  final bool isHub;
  final int hubTerminalLevel;
  final int firstClassLoungeLevel;

  Airport copyWith({
    bool? isHub,
    int? hubTerminalLevel,
    int? firstClassLoungeLevel,
  }) {
    return Airport(
      iata: iata,
      icao: icao,
      name: name,
      city: city,
      country: country,
      lat: lat,
      lon: lon,
      longestRunwayM: longestRunwayM,
      size: size,
      region: region,
      landingFee: landingFee,
      isHub: isHub ?? this.isHub,
      hubTerminalLevel: hubTerminalLevel ?? this.hubTerminalLevel,
      firstClassLoungeLevel:
          firstClassLoungeLevel ?? this.firstClassLoungeLevel,
    );
  }
}

class AircraftType {
  const AircraftType({
    required this.id,
    required this.manufacturer,
    required this.model,
    required this.familyName,
    required this.seatsEconomy,
    required this.seatsBusiness,
    required this.rangeKm,
    required this.minRunwayM,
    required this.cruiseSpeedKmh,
    required this.fuelBurnLPer100Km,
    required this.purchasePrice,
    required this.maintenanceCostPerHourUSD,
    required this.category,
    required this.yearIntroduced,
    required this.profileId,
  });

  final String id;
  final String manufacturer;
  final String model;
  final String familyName;
  final int seatsEconomy;
  final int seatsBusiness;
  final int rangeKm;
  final int minRunwayM;
  final int cruiseSpeedKmh;
  final int fuelBurnLPer100Km;
  final int purchasePrice;
  final int maintenanceCostPerHourUSD;
  final AircraftCategory category;
  final int yearIntroduced;
  final String profileId;

  String get displayName => '$manufacturer $model';
}

class CurrencyOption {
  const CurrencyOption({
    required this.code,
    required this.symbol,
    required this.name,
    required this.rateFromUsd,
  });

  final String code;
  final String symbol;
  final String name;
  final double rateFromUsd;
}
