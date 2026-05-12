import 'dart:math' as math;

import '../core/geo.dart';
import '../models/models.dart';

const _baseDemandBySize = {
  AirportSize.small: 120.0,
  AirportSize.medium: 420.0,
  AirportSize.large: 1400.0,
  AirportSize.major: 4200.0,
};

const _sizeAffinity = {
  AirportSize.small: 0.55,
  AirportSize.medium: 0.82,
  AirportSize.large: 1.12,
  AirportSize.major: 1.38,
};

const _largeDomesticMarkets = {
  'US',
  'GB',
  'RU',
  'CN',
  'JP',
  'DE',
  'FR',
  'CA',
  'AU',
  'BR',
  'IN',
};

double destinationAffinity(Airport origin, Airport destination) {
  if (origin.iata == destination.iata) return 0;
  var affinity = 1.0;
  if (origin.country == destination.country) {
    affinity *= _largeDomesticMarkets.contains(origin.country) ? 1.9 : 1.45;
  } else if (origin.region == destination.region) {
    affinity *= 1.24;
  } else {
    affinity *= 0.72;
  }
  affinity *= _sizeAffinity[destination.size] ?? 1;
  final distance = haversineKm(
    origin.lat,
    origin.lon,
    destination.lat,
    destination.lon,
  );
  final distanceFactor = distance < 350
      ? 0.42
      : distance < 1200
      ? 1.18
      : distance < 4500
      ? 1.0
      : distance < 9000
      ? 0.74
      : 0.52;
  affinity *= distanceFactor;
  if (origin.isHub) affinity *= 1.1;
  if (destination.isHub) affinity *= 1.1;
  final loungeLevel = math
      .max(origin.firstClassLoungeLevel, destination.firstClassLoungeLevel)
      .clamp(0, 3);
  affinity *= [1.0, 1.06, 1.12, 1.2][loungeLevel];
  return affinity;
}

double baselineDailyPassengers(Airport origin, Airport destination) {
  final originBase = _baseDemandBySize[origin.size] ?? 300;
  final destinationBase = _baseDemandBySize[destination.size] ?? 300;
  return math.sqrt(originBase * destinationBase) *
      destinationAffinity(origin, destination) /
      8;
}
