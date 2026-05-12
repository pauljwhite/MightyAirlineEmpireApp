import 'dart:math' as math;

import '../core/constants.dart';
import '../core/geo.dart';
import '../models/models.dart';

const maxReasonableFareMultiplier = 3.0;
const _sizeMultiplier = {
  AirportSize.small: 0.3,
  AirportSize.medium: 1.0,
  AirportSize.large: 2.5,
  AirportSize.major: 5.0,
};
const _internationalReach = {
  AirportSize.small: 0.14,
  AirportSize.medium: 0.28,
  AirportSize.large: 0.68,
  AirportSize.major: 1.0,
};
const _majorMarketCountries = {
  'US',
  'CN',
  'GB',
  'DE',
  'FR',
  'ES',
  'IT',
  'JP',
  'IN',
  'BR',
  'CA',
  'AU',
  'RU',
  'MX',
  'TR',
  'AE',
  'SG',
  'KR',
  'NL',
  'TH',
  'ID',
  'SA',
  'ZA',
};
const _countryAffinity = {
  'GB': ['IE', 'US', 'CA', 'AU', 'IN', 'ES', 'FR', 'DE', 'NL', 'AE'],
  'IE': ['GB', 'US', 'CA', 'ES', 'FR'],
  'RU': ['KZ', 'UZ', 'AM', 'GE', 'AZ', 'CN', 'TR', 'AE', 'DE'],
  'US': ['CA', 'MX', 'GB', 'JP', 'DE', 'FR', 'CN', 'BR'],
  'CA': ['US', 'GB', 'FR', 'MX'],
  'AU': ['NZ', 'GB', 'US', 'SG', 'ID', 'CN', 'JP'],
  'NZ': ['AU', 'US', 'GB'],
  'CN': ['HK', 'MO', 'TW', 'JP', 'KR', 'TH', 'SG', 'US', 'RU'],
  'JP': ['KR', 'CN', 'TW', 'US', 'TH'],
  'KR': ['JP', 'CN', 'US', 'VN'],
  'IN': ['GB', 'AE', 'SG', 'TH', 'US', 'CA', 'MY'],
  'AE': ['IN', 'GB', 'SA', 'PK', 'EG', 'US', 'RU'],
  'FR': ['GB', 'DE', 'ES', 'IT', 'BE', 'CH', 'US', 'DZ', 'MA'],
  'DE': ['GB', 'FR', 'IT', 'ES', 'AT', 'CH', 'TR', 'US'],
  'ES': ['GB', 'FR', 'DE', 'IT', 'PT', 'MA'],
  'IT': ['FR', 'DE', 'ES', 'GB', 'CH'],
  'TR': ['DE', 'RU', 'GB', 'NL', 'AE'],
  'BR': ['AR', 'US', 'PT', 'CL', 'UY'],
};

bool _isLargeCountry(String country) =>
    {'US', 'CN', 'RU', 'CA', 'AU', 'BR', 'IN'}.contains(country);

double _hash01(String value) {
  var hash = 2166136261;
  for (var i = 0; i < value.length; i += 1) {
    hash ^= value.codeUnitAt(i);
    hash = (hash * 16777619) & 0xffffffff;
  }
  return (hash % 10000) / 10000;
}

double _pairAffinity(Airport origin, Airport dest) {
  final pair = _hash01(origin.iata + ':' + dest.iata);
  final originPreference = _hash01(
    origin.iata + ':' + dest.country + ':' + dest.region.name,
  );
  return 0.78 + pair * 0.3 + originPreference * 0.22;
}

double destinationAffinity(Airport origin, Airport dest, double distanceKm) {
  var affinity = 1.0;
  final domestic = origin.country == dest.country;
  final originReach = _internationalReach[origin.size] ?? 0.3;
  final destReach = _internationalReach[dest.size] ?? 0.3;
  if (domestic) {
    affinity *= _isLargeCountry(origin.country) ? 2.6 : 1.85;
    if (distanceKm < 350) {
      affinity *= 0.75;
    } else if (distanceKm < 1500) {
      affinity *= 1.25;
    } else if (distanceKm < 4000 && _isLargeCountry(origin.country)) {
      affinity *= 1.35;
    }
    if (origin.size != AirportSize.major &&
        (dest.size == AirportSize.large || dest.size == AirportSize.major)) {
      affinity *= 1.35;
    }
  } else {
    final longHaul = distanceKm > 3000;
    affinity *= longHaul
        ? math.max(0.08, originReach * (0.35 + destReach))
        : 0.48 + originReach * 0.55;
    if (origin.region == dest.region) affinity *= 1.35;
    final affinityCountries =
        _countryAffinity[origin.country]?.contains(dest.country) == true ||
        _countryAffinity[dest.country]?.contains(origin.country) == true;
    if (affinityCountries) affinity *= 1.15 + originReach * 0.25;
  }
  if (distanceKm < 750) {
    affinity *= 1.25;
  } else if (distanceKm < 2500) {
    affinity *= 1.12;
  } else if (distanceKm > 6000) {
    affinity *= origin.size == AirportSize.major ? 0.9 : 0.42;
  }
  if (!domestic &&
      originReach >= 0.65 &&
      _majorMarketCountries.contains(origin.country) &&
      _majorMarketCountries.contains(dest.country))
    affinity *= 1.12;
  if (!domestic &&
      (origin.size == AirportSize.major ||
          (origin.size == AirportSize.large && dest.size == AirportSize.major)))
    affinity *= 1.18;
  return math.max(0.08, math.min(4.2, affinity * _pairAffinity(origin, dest)));
}

double baselineDailyPassengers(Airport origin, Airport dest) {
  final distanceKm = haversineKm(origin.lat, origin.lon, dest.lat, dest.lon);
  final distFactor = 1 / (1 + distanceKm / 4500);
  final hubBonus = (origin.isHub ? 1.1 : 1) * (dest.isHub ? 1.1 : 1);
  final loungeBonus = _hubDemandMultiplier(origin) * _hubDemandMultiplier(dest);
  return 50 *
      (_sizeMultiplier[origin.size] ?? 1) *
      (_sizeMultiplier[dest.size] ?? 1) *
      distFactor *
      destinationAffinity(origin, dest, distanceKm) *
      hubBonus *
      loungeBonus;
}

double _hubDemandMultiplier(Airport airport) {
  if (!airport.isHub) return 1;
  return [1.0, 1.06, 1.12, 1.2][airport.firstClassLoungeLevel.clamp(0, 3)];
}

double _hubCapacityMultiplier(Airport airport) =>
    [1.0, 1.35, 1.8, 2.5][airport.hubTerminalLevel.clamp(0, 3)];

double getCompetitivenessScore(double price, double avgCompetitorPrice) {
  if (avgCompetitorPrice <= 0) return 1;
  if (price <= 0) return 5;
  return math.pow(price / avgCompetitorPrice, priceElasticity).toDouble();
}

double getSoloPriceDemandShare(double price, double referencePrice) {
  if (referencePrice <= 0) return 1;
  if (price <= 0) return 5;
  final priceRatio = math.max(0.05, price / referencePrice);
  final elasticDemand = math.pow(priceRatio, priceElasticity).toDouble();
  final gougePenalty = priceRatio > 2
      ? math.pow(2 / priceRatio, 3.5).toDouble()
      : 1.0;
  return math.max(0, math.min(5, elasticDemand * gougePenalty));
}

double getAirportCapacity(Airport airport, int gameYear) {
  final base = airportBaseCapacity[airport.size.name] ?? 1200;
  return base *
      _hubCapacityMultiplier(airport) *
      math.pow(1 + 0.015, gameYear - 1960);
}

double airportSaturationMod(double utilization) {
  if (utilization <= 0.5) return 1;
  if (utilization >= 1.5) return 0.4;
  return 1 - 0.6 * ((utilization - 0.5) / 1);
}

double conditionDemandMod(double condition) {
  const threshold = 70.0;
  if (condition >= threshold) return 1;
  return 0.65 + 0.35 * (condition / threshold);
}
