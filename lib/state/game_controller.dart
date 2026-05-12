import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/geo.dart';
import '../data/aircraft_types.dart';
import '../data/airports.dart';
import '../engine/economics_engine.dart';
import '../engine/finance.dart';
import '../engine/route_optimizer.dart';
import '../models/models.dart';

class GameController extends ChangeNotifier {
  GameController() {
    startNewGame();
  }

  static const saveVersion = 1;
  GameSettings settings = const GameSettings();
  int gameDay = 0;
  int gameTimeMs = 0;
  int speed = 300;
  bool isPaused = false;
  bool hasWon = false;
  double globalFuelPrice = fuelPriceUsdPerLiter;
  final airlines = <String, Airline>{};
  final aircraft = <String, Aircraft>{};
  final routes = <String, RoutePlan>{};
  final airportDailyPax = <String, double>{};
  final newsTicker = <String>[];
  int _nextAircraft = 1;
  int _nextRoute = 1;
  int _nextLoan = 1;

  Airline get player => airlines['player']!;
  List<RoutePlan> get playerRoutes => player.routeIds
      .map((id) => routes[id])
      .whereType<RoutePlan>()
      .toList(growable: false);
  List<Aircraft> get playerFleet => player.fleetIds
      .map((id) => aircraft[id])
      .whereType<Aircraft>()
      .toList(growable: false);

  void startNewGame([GameSettings? nextSettings]) {
    settings = nextSettings ?? settings;
    gameDay = 0;
    gameTimeMs = 0;
    speed = 300;
    isPaused = false;
    hasWon = false;
    globalFuelPrice = fuelPriceUsdPerLiter;
    airlines.clear();
    aircraft.clear();
    routes.clear();
    airportDailyPax.clear();
    newsTicker.clear();
    _nextAircraft = 1;
    _nextRoute = 1;
    _nextLoan = 1;
    airlines['player'] = Airline(
      id: 'player',
      name: settings.playerAirlineName,
      iataPrefix: 'PLY',
      isPlayer: true,
      color: settings.playerAirlineColor,
      logoEmoji: settings.playerAirlineEmoji,
      cashUSD: settings.startingCash,
      hubIatas: const ['LHR'],
      foundedGameDay: 0,
      reputationScore: 55,
    );
    newsTicker.add(
      'Welcome to Mighty Airline Empire. Build routes, buy aircraft, and outlast the market.',
    );
    notifyListeners();
  }

  Aircraft buyAircraft(String typeId, {String? routeId, String? airlineId}) {
    final type = aircraftTypesById[typeId];
    if (type == null) throw ArgumentError('Unknown aircraft type ' + typeId);
    final ownerId = airlineId ?? 'player';
    final owner = airlines[ownerId];
    if (owner == null) throw StateError('Unknown airline ' + ownerId);
    if (owner.cashUSD < type.purchasePrice)
      throw StateError('Not enough cash to buy aircraft');
    final id = 'ac-' + (_nextAircraft++).toString();
    final ac = Aircraft(
      id: id,
      typeId: typeId,
      name: type.model + ' #' + id.toUpperCase(),
      airlineId: ownerId,
      purchasedGameDay: gameDay,
      assignedRouteId: routeId,
      currentLat: airportsByIata[owner.hubIatas.firstOrNull ?? 'LHR']?.lat ?? 0,
      currentLon: airportsByIata[owner.hubIatas.firstOrNull ?? 'LHR']?.lon ?? 0,
    );
    aircraft[id] = ac;
    airlines[ownerId] = owner.copyWith(
      cashUSD: owner.cashUSD - type.purchasePrice,
      fleetIds: [...owner.fleetIds, id],
    );
    if (routeId != null && routes[routeId] != null) {
      routes[routeId] = routes[routeId]!.copyWith(aircraftId: id);
    }
    notifyListeners();
    return ac;
  }

  RoutePlan createRoute({
    required String originIata,
    required String destinationIata,
    required String aircraftTypeId,
    String? aircraftId,
    int flightsPerWeek = 7,
    int? priceEconomy,
    int? priceBusiness,
    bool buyNewAircraft = true,
  }) {
    final origin = airportsByIata[originIata];
    final destination = airportsByIata[destinationIata];
    final type = aircraftTypesById[aircraftTypeId];
    if (origin == null || destination == null || type == null)
      throw ArgumentError('Invalid route inputs');
    if (origin.iata == destination.iata)
      throw ArgumentError('Route origin and destination must differ');
    final distance = haversineKm(
      origin.lat,
      origin.lon,
      destination.lat,
      destination.lon,
    );
    if (distance > type.rangeKm)
      throw StateError('Aircraft range too short for route');
    if (!canAirportHandleAircraft(origin, type) ||
        !canAirportHandleAircraft(destination, type))
      throw StateError('Airport runway too short for aircraft');
    final routeId = 'rt-' + (_nextRoute++).toString();
    var assignedAircraftId = aircraftId;
    final shellRoute = RoutePlan(
      id: routeId,
      airlineId: 'player',
      originIata: origin.iata,
      destinationIata: destination.iata,
      aircraftId: assignedAircraftId,
      flightsPerWeek: flightsPerWeek.clamp(1, 21),
      priceEconomy: priceEconomy ?? 0,
      priceBusiness: priceBusiness ?? 0,
      createdGameDay: gameDay,
      distanceKm: distance,
    );
    final dummyAircraft = Aircraft(
      id: 'preview',
      typeId: type.id,
      name: 'Preview',
      airlineId: 'player',
      purchasedGameDay: gameDay,
    );
    final costs = computeFlightCost(
      shellRoute,
      assignedAircraftId == null
          ? dummyAircraft
          : aircraft[assignedAircraftId] ?? dummyAircraft,
      type,
      origin,
      destination,
      globalFuelPrice,
      currentGameDay: gameDay,
    );
    final seats = type.seatsEconomy + type.seatsBusiness;
    final suggestedEco = seats > 0
        ? (costs.totalCost / seats * 1.3).round()
        : 200;
    final route = shellRoute.copyWith(
      priceEconomy: priceEconomy ?? suggestedEco,
      priceBusiness:
          priceBusiness ?? (type.seatsBusiness > 0 ? suggestedEco * 4 : 0),
      flightDurationHours: costs.flightDurationHours,
    );
    routes[routeId] = route;
    airlines['player'] = player.copyWith(
      routeIds: [...player.routeIds, routeId],
    );
    if (assignedAircraftId == null && buyNewAircraft) {
      assignedAircraftId = buyAircraft(type.id, routeId: routeId).id;
      routes[routeId] = routes[routeId]!.copyWith(
        aircraftId: assignedAircraftId,
      );
    } else if (assignedAircraftId != null &&
        aircraft[assignedAircraftId] != null) {
      aircraft[assignedAircraftId] = aircraft[assignedAircraftId]!.copyWith(
        assignedRouteId: routeId,
      );
    }
    notifyListeners();
    return routes[routeId]!;
  }

  RouteOptimisationResult optimiseRoute(String routeId) {
    final route = routes[routeId];
    if (route == null || route.aircraftId == null)
      throw StateError('Route has no aircraft');
    final ac = aircraft[route.aircraftId];
    final type = ac == null ? null : aircraftTypesById[ac.typeId];
    final origin = airportsByIata[route.originIata];
    final destination = airportsByIata[route.destinationIata];
    if (ac == null || type == null || origin == null || destination == null)
      throw StateError('Route is missing data');
    final result = optimiseRouteSettings(
      RouteOptimisationInput(
        route: route,
        aircraft: ac,
        aircraftType: type,
        origin: origin,
        destination: destination,
        globalFuelPrice: globalFuelPrice,
        airline: player,
        allAirlines: airlines.values.toList(),
        allRoutes: routes.values.toList(),
        airportDailyPax: airportDailyPax,
        gameDay: gameDay,
      ),
    );
    routes[routeId] = route.copyWith(
      flightsPerWeek: result.flightsPerWeek,
      priceEconomy: result.priceEconomy,
      priceBusiness: result.priceBusiness,
    );
    notifyListeners();
    return result;
  }

  DailySnapshot runDailyTick() {
    var totalRevenue = 0.0;
    var totalCost = 0.0;
    var totalPassengers = 0;
    final nextAirportPax = <String, double>{};
    final allRoutes = routes.values.toList(growable: false);
    final allAirlines = airlines.values.toList(growable: false);
    for (final routeId in player.routeIds) {
      final route = routes[routeId];
      if (route == null || route.aircraftId == null) continue;
      final ac = aircraft[route.aircraftId];
      final type = ac == null ? null : aircraftTypesById[ac.typeId];
      final origin = airportsByIata[route.originIata];
      final destination = airportsByIata[route.destinationIata];
      if (ac == null || type == null || origin == null || destination == null)
        continue;
      final result = calculateRouteEconomics(
        route: route,
        aircraft: ac,
        type: type,
        origin: origin,
        destination: destination,
        airline: player,
        allRoutes: allRoutes,
        allAirlines: allAirlines,
        globalFuelPrice: globalFuelPrice,
        gameDay: gameDay,
        airportDailyPax: airportDailyPax,
      );
      routes[routeId] = result.route;
      aircraft[ac.id] = result.aircraft;
      totalRevenue += result.revenue;
      totalCost += result.cost;
      totalPassengers += result.passengers;
      nextAirportPax[route.originIata] =
          (nextAirportPax[route.originIata] ?? 0) + result.passengers;
      nextAirportPax[route.destinationIata] =
          (nextAirportPax[route.destinationIata] ?? 0) + result.passengers;
    }
    final debtService = calculateDailyDebtService(player);
    totalCost += debtService;
    final profit = totalRevenue - totalCost;
    final paidLoans = debtService > 0
        ? applyLoanPayment(
            player.loans,
            math.min(player.cashUSD + totalRevenue, debtService),
          )
        : player.loans;
    final snapshot = DailySnapshot(
      gameDay: gameDay,
      revenue: totalRevenue,
      costs: totalCost,
      profit: profit,
      passengers: totalPassengers,
      cashEnd: player.cashUSD + profit,
    );
    final history = [...player.dailyStats, snapshot];
    airlines['player'] = player.copyWith(
      cashUSD: player.cashUSD + profit,
      totalDebt: paidLoans.fold<double>(
        0,
        (sum, loan) => sum + loan.principalUSD,
      ),
      loans: paidLoans,
      lastDailyProfit: profit,
      totalPassengersAllTime: player.totalPassengersAllTime + totalPassengers,
      dailyStats: history.length > 30
          ? history.sublist(history.length - 30)
          : history,
    );
    airportDailyPax
      ..clear()
      ..addAll(nextAirportPax);
    gameDay += 1;
    newsTicker.add(
      'Day ' +
          gameDay.toString() +
          ': profit ' +
          profit.round().toString() +
          ' USD, passengers ' +
          totalPassengers.toString() +
          '.',
    );
    if (newsTicker.length > 20)
      newsTicker.removeRange(0, newsTicker.length - 20);
    notifyListeners();
    return snapshot;
  }

  Loan applyForLoan(LoanOffer offer) {
    final loan = Loan(
      id: 'loan-' + (_nextLoan++).toString(),
      principalUSD: offer.amountUSD,
      annualInterestRate: offer.annualInterestRate,
      termYears: offer.termYears,
      dailyPaymentUSD: calculateDailyLoanPayment(
        offer.amountUSD,
        offer.annualInterestRate,
        offer.termYears,
      ),
      issuedGameDay: gameDay,
    );
    airlines['player'] = player.copyWith(
      cashUSD: player.cashUSD + loan.principalUSD,
      totalDebt: player.totalDebt + loan.principalUSD,
      loans: [...player.loans, loan],
    );
    notifyListeners();
    return loan;
  }

  void repayLoans(double amountUSD) {
    final payment = math.max(0, math.min(amountUSD, player.cashUSD)).toDouble();
    final loans = applyLoanPayment(player.loans, payment);
    airlines['player'] = player.copyWith(
      cashUSD: player.cashUSD - payment,
      totalDebt: loans.fold<double>(0, (sum, loan) => sum + loan.principalUSD),
      loans: loans,
    );
    notifyListeners();
  }

  String exportJson() => jsonEncode(toJson());

  Map<String, Object?> toJson() => {
    'version': saveVersion,
    'settings': settings.toJson(),
    'gameDay': gameDay,
    'gameTimeMs': gameTimeMs,
    'speed': speed,
    'isPaused': isPaused,
    'hasWon': hasWon,
    'globalFuelPrice': globalFuelPrice,
    'airlines': airlines.map((key, value) => MapEntry(key, value.toJson())),
    'aircraft': aircraft.map((key, value) => MapEntry(key, value.toJson())),
    'routes': routes.map((key, value) => MapEntry(key, value.toJson())),
    'airportDailyPax': airportDailyPax,
    'newsTicker': newsTicker,
    'nextAircraft': _nextAircraft,
    'nextRoute': _nextRoute,
    'nextLoan': _nextLoan,
  };

  void importJson(String rawJson) {
    final raw = jsonDecode(rawJson) as Map<String, dynamic>;
    settings = GameSettings.fromJson(
      Map<String, Object?>.from(raw['settings'] as Map? ?? const {}),
    );
    gameDay = (raw['gameDay'] as num?)?.round() ?? 0;
    gameTimeMs = (raw['gameTimeMs'] as num?)?.round() ?? 0;
    speed = (raw['speed'] as num?)?.round() ?? 300;
    isPaused = raw['isPaused'] == true;
    hasWon = raw['hasWon'] == true;
    globalFuelPrice =
        (raw['globalFuelPrice'] as num?)?.toDouble() ?? fuelPriceUsdPerLiter;
    airlines
      ..clear()
      ..addAll(
        (raw['airlines'] as Map? ?? const {}).map(
          (key, value) => MapEntry(
            key as String,
            Airline.fromJson(Map<String, Object?>.from(value as Map)),
          ),
        ),
      );
    aircraft
      ..clear()
      ..addAll(
        (raw['aircraft'] as Map? ?? const {}).map(
          (key, value) => MapEntry(
            key as String,
            Aircraft.fromJson(Map<String, Object?>.from(value as Map)),
          ),
        ),
      );
    routes
      ..clear()
      ..addAll(
        (raw['routes'] as Map? ?? const {}).map(
          (key, value) => MapEntry(
            key as String,
            RoutePlan.fromJson(Map<String, Object?>.from(value as Map)),
          ),
        ),
      );
    airportDailyPax
      ..clear()
      ..addAll(
        (raw['airportDailyPax'] as Map? ?? const {}).map(
          (key, value) => MapEntry(key as String, (value as num).toDouble()),
        ),
      );
    newsTicker
      ..clear()
      ..addAll(List<String>.from(raw['newsTicker'] as List? ?? const []));
    _nextAircraft =
        (raw['nextAircraft'] as num?)?.round() ?? aircraft.length + 1;
    _nextRoute = (raw['nextRoute'] as num?)?.round() ?? routes.length + 1;
    _nextLoan = (raw['nextLoan'] as num?)?.round() ?? 1;
    notifyListeners();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
