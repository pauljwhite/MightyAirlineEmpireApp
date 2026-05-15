import 'dart:math' as math;

import '../core/constants.dart';
import '../models/models.dart';
import 'demand_model.dart';

const crashDemandPenaltyPct = 0.15;
const repPriceFactor = 0.004;
const maintenanceTiers = {
  MaintenanceTier.light: (
    conditionGain: 20.0,
    minHoursBase: 3.0,
    hoursOwedFactor: 0.5,
    costMultiplier: 2.0,
    durationDays: 1,
  ),
  MaintenanceTier.standard: (
    conditionGain: 50.0,
    minHoursBase: 6.0,
    hoursOwedFactor: 1.0,
    costMultiplier: 1.5,
    durationDays: 2,
  ),
  MaintenanceTier.full: (
    conditionGain: 999.0,
    minHoursBase: 10.0,
    hoursOwedFactor: 1.0,
    costMultiplier: 2.2,
    durationDays: 4,
  ),
};

class FlightCost {
  const FlightCost({
    required this.fuelCost,
    required this.maintenanceCost,
    required this.airportFees,
    required this.crewCost,
    required this.totalCost,
    required this.flightDurationHours,
  });
  final double fuelCost;
  final double maintenanceCost;
  final double airportFees;
  final double crewCost;
  final double totalCost;
  final double flightDurationHours;
}

class RouteEconomicsResult {
  const RouteEconomicsResult({
    required this.route,
    required this.aircraft,
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.passengers,
  });
  final RoutePlan route;
  final Aircraft aircraft;
  final double revenue;
  final double cost;
  final double profit;
  final int passengers;
}

double repPricePremium(double reputationScore) =>
    1 + (reputationScore - 50) * repPriceFactor;

String routePairKey(String origin, String dest) =>
    origin.compareTo(dest) < 0 ? origin + ':' + dest : dest + ':' + origin;

double aircraftAirportFeeMultiplier(AircraftType type) =>
    switch (type.category) {
      AircraftCategory.regional => 0.45,
      AircraftCategory.narrowbody => 0.75,
      AircraftCategory.sst => 1.25,
      AircraftCategory.widebody => 1,
    };

double getAircraftAgeYears(Aircraft aircraft, int currentGameDay) =>
    math.max(0, (currentGameDay - aircraft.purchasedGameDay) / 365);

double getMaintenanceAgeMultiplier(Aircraft aircraft, int currentGameDay) {
  final ageYears = getAircraftAgeYears(aircraft, currentGameDay);
  if (ageYears <= 8) return 1;
  final midLifePenalty = math.min(0.35, math.max(0, ageYears - 8) * 0.025);
  final oldFleetPenalty = math.min(0.45, math.max(0, ageYears - 18) * 0.04);
  return 1 + midLifePenalty + oldFleetPenalty;
}

int computeMaintenanceCost(
  MaintenanceTier tier,
  double hoursOwed,
  int ratePerHour, {
  double ageMultiplier = 1,
}) {
  final cfg = maintenanceTiers[tier]!;
  final hoursBilled = math.max(
    cfg.minHoursBase,
    hoursOwed * cfg.hoursOwedFactor,
  );
  return (hoursBilled * ratePerHour * cfg.costMultiplier * ageMultiplier)
      .round();
}

bool canAirportHandleAircraft(Airport airport, AircraftType type) {
  final runway = airport.longestRunwayM;
  if (runway == null)
    return airport.size == AirportSize.major ||
        airport.size == AirportSize.large ||
        type.category == AircraftCategory.regional;
  return runway >= type.minRunwayM;
}

FlightCost computeFlightCost(
  RoutePlan route,
  Aircraft aircraft,
  AircraftType type,
  Airport origin,
  Airport dest,
  double fuelPriceUsdPerLiter, {
  int? currentGameDay,
}) {
  final duration = route.distanceKm / type.cruiseSpeedKmh;
  final fuelLiters = duration * type.fuelBurnLPer100Km;
  final fuelCost = fuelLiters * fuelPriceUsdPerLiter;
  final conditionFactor = 1 + (100 - aircraft.condition) / 200;
  final ageFactor = currentGameDay == null
      ? 1
      : getMaintenanceAgeMultiplier(aircraft, currentGameDay);
  final maintenanceCost =
      type.maintenanceCostPerHourUSD * duration * conditionFactor * ageFactor;
  final crewCost = crewCostPerFlightHourUsd * duration;
  final hubDiscount = (origin.isHub || dest.isHub) ? (1 - hubCostDiscount) : 1;
  final airportFees =
      (origin.landingFee + dest.landingFee) *
      hubDiscount *
      aircraftAirportFeeMultiplier(type);
  final total = fuelCost + maintenanceCost + crewCost + airportFees;
  return FlightCost(
    fuelCost: fuelCost,
    maintenanceCost: maintenanceCost,
    airportFees: airportFees,
    crewCost: crewCost,
    totalCost: total,
    flightDurationHours: duration,
  );
}

double marketShareForCabin({
  required RoutePlan route,
  required int price,
  required List<RoutePlan> allRoutes,
  required List<Airline> allAirlines,
  required double referencePrice,
  required String airlineId,
  required String cabin,
  String? excludeRouteId,
}) {
  int cabinPrice(RoutePlan r) =>
      cabin == 'business' ? r.priceBusiness : r.priceEconomy;
  final routesOnPair = allRoutes
      .where(
        (candidate) =>
            candidate.isActive &&
            candidate.id != excludeRouteId &&
            routePairKey(candidate.originIata, candidate.destinationIata) ==
                routePairKey(route.originIata, route.destinationIata) &&
            (cabin == 'economy' || cabinPrice(candidate) > 0),
      )
      .toList();
  final airline = allAirlines.where((a) => a.id == airlineId).firstOrNull;
  final premium = airline == null
      ? 1
      : repPricePremium(airline.reputationScore);
  final effectivePrice = price / premium;
  if (routesOnPair.isEmpty)
    return getSoloPriceDemandShare(effectivePrice, referencePrice);
  final avgPrice =
      routesOnPair.fold<double>(0, (sum, r) => sum + cabinPrice(r)) /
      routesOnPair.length;
  final ownScore = getCompetitivenessScore(effectivePrice, avgPrice);
  final totalScore = routesOnPair.fold<double>(0, (sum, r) {
    final competitor = allAirlines
        .where((a) => a.id == r.airlineId)
        .firstOrNull;
    final competitorPremium = competitor == null
        ? 1
        : repPricePremium(competitor.reputationScore);
    return sum +
        getCompetitivenessScore(cabinPrice(r) / competitorPremium, avgPrice);
  });
  return totalScore > 0 ? ownScore / totalScore : 1;
}

RouteEconomicsResult calculateRouteEconomics({
  required RoutePlan route,
  required Aircraft aircraft,
  required AircraftType type,
  required Airport origin,
  required Airport destination,
  required Airline airline,
  required List<RoutePlan> allRoutes,
  required List<Airline> allAirlines,
  required double globalFuelPrice,
  required int gameDay,
  Map<String, double> airportDailyPax = const {},
}) {
  if (!route.isActive ||
      aircraft.isGrounded ||
      aircraft.status == AircraftStatus.maintenance ||
      _isAirportClosed(origin, gameDay) ||
      _isAirportClosed(destination, gameDay) ||
      !canAirportHandleAircraft(origin, type) ||
      !canAirportHandleAircraft(destination, type)) {
    return RouteEconomicsResult(
      route: route,
      aircraft: aircraft,
      revenue: 0,
      cost: 0,
      profit: 0,
      passengers: 0,
    );
  }
  final costs = computeFlightCost(
    route,
    aircraft,
    type,
    origin,
    destination,
    globalFuelPrice,
    currentGameDay: gameDay,
  );
  final flightsPerDay = route.flightsPerWeek / 7;
  final seats = type.seatsEconomy + type.seatsBusiness;
  final ecoReference = seats > 0
      ? (costs.totalCost / seats * 1.3).roundToDouble()
      : 200.0;
  final bizReference = ecoReference * 4;
  final gameYear = 1960 + (gameDay / 365).floor();
  final originUtil =
      (airportDailyPax[route.originIata] ?? 0) /
      getAirportCapacity(origin, gameYear);
  final destUtil =
      (airportDailyPax[route.destinationIata] ?? 0) /
      getAirportCapacity(destination, gameYear);
  final satMod =
      airportSaturationMod(originUtil) * airportSaturationMod(destUtil);
  final isHubRoute =
      airline.hubIatas.contains(route.originIata) ||
      airline.hubIatas.contains(route.destinationIata);
  final baselinePax =
      baselineDailyPassengers(origin, destination) *
      (isHubRoute ? hubDemandBonus : 1) *
      satMod;
  final repMod = 1 + (airline.reputationScore - 50) * reputationDemandFactor;
  final crashPenalty = airline.crashPenaltyDaysLeft > 0
      ? (1 - crashDemandPenaltyPct)
      : 1;
  final condMod = conditionDemandMod(aircraft.condition);
  final ecoShare = marketShareForCabin(
    route: route,
    price: route.priceEconomy,
    allRoutes: allRoutes,
    allAirlines: allAirlines,
    referencePrice: ecoReference,
    airlineId: airline.id,
    cabin: 'economy',
    excludeRouteId: route.id,
  );
  final ecoCapacity = type.seatsEconomy * flightsPerDay;
  final ecoPax = math
      .min(
        ecoCapacity,
        (baselinePax * 0.9 * ecoShare * repMod * crashPenalty * condMod)
            .floor(),
      )
      .round();
  final bizCapacity = type.seatsBusiness * flightsPerDay;
  final bizShare = type.seatsBusiness > 0
      ? marketShareForCabin(
          route: route,
          price: route.priceBusiness,
          allRoutes: allRoutes,
          allAirlines: allAirlines,
          referencePrice: bizReference,
          airlineId: airline.id,
          cabin: 'business',
          excludeRouteId: route.id,
        )
      : 0;
  final bizPax = math
      .min(
        bizCapacity,
        (baselinePax * 0.08 * bizShare * repMod * crashPenalty * condMod)
            .floor(),
      )
      .round();
  final revenue =
      ecoPax * route.priceEconomy + bizPax * route.priceBusiness.toDouble();
  final cost = costs.totalCost * flightsPerDay;
  final hours = costs.flightDurationHours * flightsPerDay;
  var updatedAircraft = aircraft.copyWith(
    totalFlightHours: aircraft.totalFlightHours + hours,
    maintenanceHoursOwed: aircraft.maintenanceHoursOwed + hours,
    condition: math.max(0, aircraft.condition - hours * 0.08),
  );
  updatedAircraft = updatedAircraft.copyWith(
    crashRisk: aircraftCrashRisk(updatedAircraft, gameDay),
  );
  var routeActive = route.isActive;
  if (updatedAircraft.condition < (airline.isPlayer ? 20 : 15) &&
      !updatedAircraft.isGrounded) {
    routeActive = false;
    updatedAircraft = updatedAircraft.copyWith(
      isGrounded: true,
      status: AircraftStatus.idle,
      groundedReason:
          'Critical condition (${updatedAircraft.condition.toStringAsFixed(0)}%) - requires maintenance',
      knownFaultRiskMod: airline.isPlayer
          ? updatedAircraft.knownFaultRiskMod
          : 1,
    );
  }
  final updatedRoute = route.copyWith(
    isActive: routeActive,
    dailyRevenue: revenue,
    dailyCost: cost,
    dailyFuelCost: costs.fuelCost * flightsPerDay,
    dailyMaintenanceCost: costs.maintenanceCost * flightsPerDay,
    dailyCrewCost: costs.crewCost * flightsPerDay,
    dailyAirportFees: costs.airportFees * flightsPerDay,
    dailyProfit: revenue - cost,
    dailyPassengers: ecoPax + bizPax,
    flightDurationHours: costs.flightDurationHours,
    loadFactorEconomy: ecoCapacity > 0 ? ecoPax / ecoCapacity : 0,
    loadFactorBusiness: bizCapacity > 0 ? bizPax / bizCapacity : 0,
  );
  return RouteEconomicsResult(
    route: updatedRoute,
    aircraft: updatedAircraft,
    revenue: revenue,
    cost: cost,
    profit: revenue - cost,
    passengers: ecoPax + bizPax,
  );
}

bool _isAirportClosed(Airport airport, int gameDay) {
  final closedUntil = airport.closedUntilGameDay;
  return closedUntil != null && closedUntil >= gameDay;
}

double aircraftCrashRisk(Aircraft aircraft, int gameDay) {
  final conditionFraction = math.max(0.0, 1 - aircraft.condition / 100);
  final baseRisk = math.pow(conditionFraction, 3).toDouble();
  final ageYears = (gameDay - aircraft.purchasedGameDay) / 365;
  final agePenalty = math.max(0.0, (ageYears - 15) * 0.01);
  return math.min(0.95, baseRisk + agePenalty).toDouble();
}
