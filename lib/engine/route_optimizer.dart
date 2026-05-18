import 'dart:math' as math;

import '../core/constants.dart';
import '../models/models.dart';
import 'demand_model.dart';
import 'economics_engine.dart';

const maxReasonableFareMultiplier = 3.0;

class RouteOptimisationInput {
  const RouteOptimisationInput({
    required this.route,
    required this.aircraft,
    required this.aircraftType,
    required this.origin,
    required this.destination,
    required this.globalFuelPrice,
    required this.airline,
    required this.routeIndex,
    this.airportDailyPax = const {},
    this.gameDay = 0,
  });
  final RoutePlan route;
  final Aircraft aircraft;
  final AircraftType aircraftType;
  final Airport origin;
  final Airport destination;
  final double globalFuelPrice;
  final Airline airline;
  /// Pre-built index for O(1) pair lookups — replaces the old flat
  /// `allRoutes` + `allAirlines` lists that caused O(N) scans inside
  /// every step of the 21-flight × 2-cabin × ~60-price optimiser loop.
  final RouteIndex routeIndex;
  final Map<String, double> airportDailyPax;
  final int gameDay;
}

class RouteOptimisationResult {
  const RouteOptimisationResult({
    required this.flightsPerWeek,
    required this.priceEconomy,
    required this.priceBusiness,
    required this.dailyProfit,
  });
  final int flightsPerWeek;
  final int priceEconomy;
  final int priceBusiness;
  final double dailyProfit;
}

class _MarketContext {
  const _MarketContext({
    required this.referencePrice,
    required this.referencePriceBiz,
    required this.baselinePax,
    required this.repMod,
    required this.condMod,
    required this.playerPremium,
  });
  final double referencePrice;
  final double referencePriceBiz;
  final double baselinePax;
  final double repMod;
  final double condMod;
  final double playerPremium;
}

int normaliseOptimisedPrice(num value) {
  if (value <= 0) return 0;
  final step = value < 200
      ? 5
      : value < 1000
      ? 10
      : value < 5000
      ? 50
      : 100;
  return math.max(0, (value / step).round() * step);
}

_MarketContext _marketContext(RouteOptimisationInput input) {
  final costs = computeFlightCost(
    input.route,
    input.aircraft,
    input.aircraftType,
    input.origin,
    input.destination,
    input.globalFuelPrice,
    currentGameDay: input.gameDay,
  );
  final totalSeats =
      input.aircraftType.seatsEconomy + input.aircraftType.seatsBusiness;
  final referencePrice = totalSeats > 0
      ? (costs.totalCost / totalSeats * 1.3).roundToDouble()
      : 200.0;
  final gameYear = 1960 + (input.gameDay / 365).floor();
  final originUtil =
      (input.airportDailyPax[input.origin.iata] ?? 0) /
      getAirportCapacity(input.origin, gameYear);
  final destUtil =
      (input.airportDailyPax[input.destination.iata] ?? 0) /
      getAirportCapacity(input.destination, gameYear);
  final saturation =
      airportSaturationMod(originUtil) * airportSaturationMod(destUtil);
  final hubRoute =
      input.airline.hubIatas.contains(input.route.originIata) ||
      input.airline.hubIatas.contains(input.route.destinationIata);
  final baseline =
      baselineDailyPassengers(input.origin, input.destination) *
      (hubRoute ? hubDemandBonus : 1) *
      saturation;
  return _MarketContext(
    referencePrice: referencePrice,
    referencePriceBiz: referencePrice * 4,
    baselinePax: baseline,
    repMod: 1 + (input.airline.reputationScore - 50) * reputationDemandFactor,
    condMod: conditionDemandMod(input.aircraft.condition),
    playerPremium: repPricePremium(input.airline.reputationScore),
  );
}

double _cabinMarketShare(
  RouteOptimisationInput input,
  _MarketContext context,
  int price,
  double referencePrice,
  String cabin,
) {
  final effectivePrice = price / context.playerPremium;
  final route = input.route;
  final pairKey = routePairKey(route.originIata, route.destinationIata);
  final pairRoutes = input.routeIndex.activeRoutesByPair[pairKey];
  final competitors = <RoutePlan>[];
  if (pairRoutes != null) {
    for (final candidate in pairRoutes) {
      if (candidate.id == route.id) continue;
      if (cabin != 'economy' && candidate.priceBusiness <= 0) continue;
      competitors.add(candidate);
    }
  }
  if (competitors.isEmpty)
    return getSoloPriceDemandShare(effectivePrice, referencePrice);
  int cabinPrice(RoutePlan r) =>
      cabin == 'business' ? r.priceBusiness : r.priceEconomy;
  final avgPrice =
      competitors.fold<double>(0, (sum, r) => sum + cabinPrice(r)) /
      competitors.length;
  final ownScore = getCompetitivenessScore(effectivePrice, avgPrice);
  final competitorScore = competitors.fold<double>(0, (sum, r) {
    final premium = input.routeIndex.reputationPremiumById[r.airlineId] ?? 1.0;
    return sum + getCompetitivenessScore(cabinPrice(r) / premium, avgPrice);
  });
  return ownScore / math.max(ownScore + competitorScore, 0.0001);
}

double _cabinRevenue(
  RouteOptimisationInput input,
  _MarketContext context,
  int flightsPerWeek,
  int price,
  String cabin,
) {
  final seats = cabin == 'business'
      ? input.aircraftType.seatsBusiness
      : input.aircraftType.seatsEconomy;
  if (seats <= 0) return 0;
  final flightsPerDay = flightsPerWeek / 7;
  final capacity = seats * flightsPerDay;
  final referencePrice = cabin == 'business'
      ? context.referencePriceBiz
      : context.referencePrice;
  final demandShare = cabin == 'business' ? 0.10 : 0.90;
  final marketShare = _cabinMarketShare(
    input,
    context,
    price,
    referencePrice,
    cabin,
  );
  final pax = math.min(
    capacity,
    (context.baselinePax *
            demandShare *
            marketShare *
            context.repMod *
            context.condMod)
        .floor(),
  );
  return (pax * price).toDouble();
}

double _estimatedProfit(
  RouteOptimisationInput input,
  _MarketContext context,
  int flightsPerWeek,
  int priceEconomy,
  int priceBusiness,
) {
  final route = input.route.copyWith(
    flightsPerWeek: flightsPerWeek,
    priceEconomy: priceEconomy,
    priceBusiness: priceBusiness,
  );
  final costs = computeFlightCost(
    route,
    input.aircraft,
    input.aircraftType,
    input.origin,
    input.destination,
    input.globalFuelPrice,
    currentGameDay: input.gameDay,
  );
  final revenue =
      _cabinRevenue(input, context, flightsPerWeek, priceEconomy, 'economy') +
      _cabinRevenue(input, context, flightsPerWeek, priceBusiness, 'business');
  return revenue - costs.totalCost * (flightsPerWeek / 7);
}

List<int> _priceCandidates(
  RouteOptimisationInput input,
  _MarketContext context,
  int flightsPerWeek,
  int currentPrice,
  String cabin,
) {
  final seats = cabin == 'business'
      ? input.aircraftType.seatsBusiness
      : input.aircraftType.seatsEconomy;
  if (seats <= 0) return [0];
  final referencePrice = cabin == 'business'
      ? context.referencePriceBiz
      : context.referencePrice;
  final demandShare = cabin == 'business' ? 0.10 : 0.90;
  final dailyCapacity = seats * (flightsPerWeek / 7);
  final unconstrainedDemand =
      context.baselinePax * demandShare * context.repMod * context.condMod;
  final soloCapacityPrice = dailyCapacity > 0 && unconstrainedDemand > 0
      ? referencePrice *
            math.pow(
              math.max(unconstrainedDemand / dailyCapacity, 0.0001),
              0.5,
            ) *
            context.playerPremium
      : referencePrice;
  final maxPrice = referencePrice * maxReasonableFareMultiplier;
  final prices = <int>{
    0,
    math.min(currentPrice, maxPrice).round(),
    referencePrice.round(),
    math.min(soloCapacityPrice, maxPrice).round(),
    maxPrice.round(),
  };
  for (var multiplier = 0.05; multiplier <= 3.0001; multiplier += 0.05) {
    prices.add((referencePrice * multiplier).round());
  }
  final pairKey2 = routePairKey(
    input.route.originIata,
    input.route.destinationIata,
  );
  final pairRoutes2 =
      input.routeIndex.activeRoutesByPair[pairKey2] ?? const <RoutePlan>[];
  for (final route in pairRoutes2) {
    final price = cabin == 'business'
        ? route.priceBusiness
        : route.priceEconomy;
    if (price <= 0) continue;
    prices.add(math.min(price, maxPrice).round());
    prices.add(math.min(price * 0.9, maxPrice).round());
    prices.add(math.min(price * 1.1, maxPrice).round());
  }
  final normalised =
      prices
          .map((p) => normaliseOptimisedPrice(math.min(p, maxPrice)))
          .where((p) => p >= 0 && p <= maxPrice)
          .toSet()
          .toList()
        ..sort();
  return normalised;
}

({int price, double revenue}) _optimiseCabin(
  RouteOptimisationInput input,
  _MarketContext context,
  int flightsPerWeek,
  int currentPrice,
  String cabin,
) {
  final candidates = _priceCandidates(
    input,
    context,
    flightsPerWeek,
    currentPrice,
    cabin,
  );
  var bestPrice = candidates.first;
  var bestRevenue = _cabinRevenue(
    input,
    context,
    flightsPerWeek,
    bestPrice,
    cabin,
  );
  for (final price in candidates) {
    final revenue = _cabinRevenue(input, context, flightsPerWeek, price, cabin);
    if (revenue > bestRevenue) {
      bestPrice = price;
      bestRevenue = revenue;
    }
  }
  return (price: bestPrice, revenue: bestRevenue);
}

RouteOptimisationResult optimiseRouteSettings(RouteOptimisationInput input) {
  final context = _marketContext(input);
  RouteOptimisationResult? best;
  for (var flights = 1; flights <= 21; flights += 1) {
    final economy = _optimiseCabin(
      input,
      context,
      flights,
      input.route.priceEconomy,
      'economy',
    );
    final business = input.aircraftType.seatsBusiness > 0
        ? _optimiseCabin(
            input,
            context,
            flights,
            input.route.priceBusiness,
            'business',
          )
        : (price: 0, revenue: 0.0);
    final profit = _estimatedProfit(
      input,
      context,
      flights,
      economy.price,
      business.price,
    );
    if (best == null || profit > best.dailyProfit) {
      best = RouteOptimisationResult(
        flightsPerWeek: flights,
        priceEconomy: economy.price,
        priceBusiness: business.price,
        dailyProfit: profit,
      );
    }
  }
  return best ??
      RouteOptimisationResult(
        flightsPerWeek: input.route.flightsPerWeek,
        priceEconomy: input.route.priceEconomy,
        priceBusiness: input.aircraftType.seatsBusiness > 0
            ? input.route.priceBusiness
            : 0,
        dailyProfit: _estimatedProfit(
          input,
          context,
          input.route.flightsPerWeek,
          input.route.priceEconomy,
          input.route.priceBusiness,
        ),
      );
}

