import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/geo.dart';
import '../data/aircraft_types.dart';
import '../data/airports.dart';
import '../engine/demand_model.dart';
import '../engine/economics_engine.dart';
import '../engine/finance.dart';
import '../engine/hub_upgrades.dart';
import '../engine/route_optimizer.dart';
import '../engine/valuation.dart';
import '../models/models.dart';

class _AiSeed {
  const _AiSeed(
    this.name,
    this.iataPrefix,
    this.color,
    this.logoEmoji,
    this.personality,
    this.startHub,
    this.secondHub,
    this.aircraftTypeId,
    this.cashUSD,
  );
  final String name;
  final String iataPrefix;
  final String color;
  final String logoEmoji;
  final AirlinePersonality personality;
  final String startHub;
  final String secondHub;
  final String aircraftTypeId;
  final double cashUSD;
}

const _aiSeeds = <_AiSeed>[
  _AiSeed(
    'Eagle Air',
    'EA',
    '#ef4444',
    'EA',
    AirlinePersonality.aggressive,
    'JFK',
    'LAX',
    'b707-120',
    80000000,
  ),
  _AiSeed(
    'Pacific Coast Airlines',
    'PC',
    '#0ea5e9',
    'PC',
    AirlinePersonality.balanced,
    'LAX',
    'SFO',
    'b707-120',
    65000000,
  ),
  _AiSeed(
    'Euro Wings',
    'EW',
    '#22c55e',
    'EW',
    AirlinePersonality.budget,
    'FRA',
    'CDG',
    'b707-120',
    60000000,
  ),
  _AiSeed(
    'Nordic Air',
    'NA',
    '#818cf8',
    'NA',
    AirlinePersonality.conservative,
    'LHR',
    'AMS',
    'dc8-50',
    70000000,
  ),
  _AiSeed(
    'Gulf Connect',
    'GC',
    '#f59e0b',
    'GC',
    AirlinePersonality.premium,
    'DXB',
    'DOH',
    'dc8-50',
    70000000,
  ),
  _AiSeed(
    'Dragon Air',
    'DA',
    '#e879f9',
    'DA',
    AirlinePersonality.aggressive,
    'PEK',
    'PVG',
    'il18',
    75000000,
  ),
  _AiSeed(
    'Lotus Airways',
    'LA',
    '#a3e635',
    'LA',
    AirlinePersonality.balanced,
    'DEL',
    'BOM',
    'b707-120',
    65000000,
  ),
  _AiSeed(
    'Sky Pacific',
    'SP',
    '#22d3ee',
    'SP',
    AirlinePersonality.balanced,
    'NRT',
    'HKG',
    'dc8-50',
    70000000,
  ),
  _AiSeed(
    'Southern Cross',
    'SC',
    '#a855f7',
    'SC',
    AirlinePersonality.conservative,
    'SYD',
    'MEL',
    'b707-320',
    75000000,
  ),
  _AiSeed(
    'Savanna Air',
    'SV',
    '#facc15',
    'SV',
    AirlinePersonality.budget,
    'JNB',
    'NBO',
    'dc8-50',
    50000000,
  ),
  _AiSeed(
    'Condor Global',
    'CG',
    '#c084fc',
    'CG',
    AirlinePersonality.balanced,
    'GRU',
    'EZE',
    'b707-120',
    55000000,
  ),
  _AiSeed(
    'Maple Leaf Air',
    'ML',
    '#f43f5e',
    'ML',
    AirlinePersonality.conservative,
    'YYZ',
    'YVR',
    'b707-120',
    60000000,
  ),
];

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
  final airportUpgrades = <String, AirportUpgrade>{};
  final airportDailyPax = <String, double>{};
  final newsTicker = <String>[];
  final newsArticles = <String, NewsArticle>{};
  String? latestArticleId;
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
  List<Airline> get competitors => airlines.values
      .where((airline) => !airline.isPlayer)
      .toList(growable: false);

  List<RoutePlan> routesForAirline(String airlineId) =>
      airlines[airlineId]?.routeIds
          .map((id) => routes[id])
          .whereType<RoutePlan>()
          .toList(growable: false) ??
      const [];

  List<Aircraft> fleetForAirline(String airlineId) =>
      airlines[airlineId]?.fleetIds
          .map((id) => aircraft[id])
          .whereType<Aircraft>()
          .toList(growable: false) ??
      const [];

  Airport? airportByIata(String iata) {
    final airport = airportsByIata[iata];
    if (airport == null) return null;
    return airportUpgrades[iata]?.apply(airport) ?? airport;
  }

  List<Airport> get airportList => airports
      .map(
        (airport) => airportUpgrades[airport.iata]?.apply(airport) ?? airport,
      )
      .toList(growable: false);

  double playerStakeIn(String airlineId) =>
      airlines[airlineId]?.shareholders['player'] ?? 0;

  double marketFloatForAirline(String airlineId) {
    final target = airlines[airlineId];
    if (target == null) return 0;
    final owned = target.shareholders.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    return (100 - owned).clamp(0, 100).toDouble();
  }

  double companyValue(String airlineId) {
    final target = airlines[airlineId];
    if (target == null) return 0;
    return rawCompanyValue(
      airline: target,
      aircraft: aircraft,
      routes: routes,
      currentGameDay: gameDay,
    );
  }

  double sharePurchasePrice(String airlineId, double percent) {
    final target = airlines[airlineId];
    if (target == null || target.isPlayer) return 0;
    return calculateSharePrice(
      percentToBuy: percent,
      currentPlayerPercent: playerStakeIn(airlineId),
      airline: target,
      aircraft: aircraft,
      routes: routes,
      currentGameDay: gameDay,
    );
  }

  BuyoutValuation buyoutPrice(String airlineId) {
    final target = airlines[airlineId];
    if (target == null) {
      return const BuyoutValuation(
        fleetValue: 0,
        routeValue: 0,
        cashValue: 0,
        debtValue: 0,
        controlPremium: 0,
        totalPrice: 0,
      );
    }
    return calculateBuyoutPrice(
      airline: target,
      aircraft: aircraft,
      routes: routes,
      currentGameDay: gameDay,
    );
  }

  void setSpeed(int nextSpeed) {
    speed = nextSpeed;
    isPaused = nextSpeed == 0;
    notifyListeners();
  }

  void _markAirportHub(String iata) {
    final current = airportUpgrades[iata] ?? const AirportUpgrade();
    airportUpgrades[iata] = current.copyWith(isHub: true);
  }

  bool setPlayerHub(String iata) {
    final airport = airportByIata(iata);
    if (airport == null) return false;
    if (!player.hubIatas.contains(iata)) {
      airlines['player'] = player.copyWith(
        hubIatas: [...player.hubIatas, iata],
      );
    }
    _markAirportHub(iata);
    notifyListeners();
    return true;
  }

  bool upgradeHubTerminal(String iata) {
    final airport = airportByIata(iata);
    if (airport == null || !player.hubIatas.contains(iata)) return false;
    final cost = getHubTerminalUpgradeCost(airport);
    if (cost == null || player.cashUSD < cost) return false;
    final current = airportUpgrades[iata] ?? const AirportUpgrade(isHub: true);
    airlines['player'] = player.copyWith(cashUSD: player.cashUSD - cost);
    airportUpgrades[iata] = current.copyWith(
      isHub: true,
      hubTerminalLevel: getHubTerminalLevel(airport) + 1,
    );
    newsTicker.add('${airport.iata} terminal upgraded.');
    notifyListeners();
    return true;
  }

  bool upgradeFirstClassLounge(String iata) {
    final airport = airportByIata(iata);
    if (airport == null || !player.hubIatas.contains(iata)) return false;
    final cost = getFirstClassLoungeUpgradeCost(airport);
    if (cost == null || player.cashUSD < cost) return false;
    final current = airportUpgrades[iata] ?? const AirportUpgrade(isHub: true);
    airlines['player'] = player.copyWith(cashUSD: player.cashUSD - cost);
    airportUpgrades[iata] = current.copyWith(
      isHub: true,
      firstClassLoungeLevel: getFirstClassLoungeLevel(airport) + 1,
    );
    newsTicker.add('${airport.iata} first class lounge upgraded.');
    notifyListeners();
    return true;
  }

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
    airportUpgrades.clear();
    airportDailyPax.clear();
    newsTicker.clear();
    newsArticles.clear();
    latestArticleId = null;
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
    _markAirportHub('LHR');
    _initAIAirlines();
    newsTicker.add(
      'Welcome to Mighty Airline Empire. Build routes, buy aircraft, and outlast the market.',
    );
    notifyListeners();
  }

  void _initAIAirlines() {
    final count = math.min(settings.aiCount, _aiSeeds.length);
    for (var i = 0; i < count; i += 1) {
      final seed = _aiSeeds[i];
      if (!airportsByIata.containsKey(seed.startHub) ||
          !airportsByIata.containsKey(seed.secondHub))
        continue;
      final airlineId = 'ai-${i + 1}';
      airlines[airlineId] = Airline(
        id: airlineId,
        name: seed.name,
        iataPrefix: seed.iataPrefix,
        isPlayer: false,
        color: seed.color,
        logoEmoji: seed.logoEmoji,
        cashUSD: seed.cashUSD,
        hubIatas: [seed.startHub],
        personality: seed.personality,
        foundedGameDay: 0,
        reputationScore: switch (seed.personality) {
          AirlinePersonality.premium => 62,
          AirlinePersonality.budget => 46,
          AirlinePersonality.conservative => 56,
          AirlinePersonality.aggressive => 50,
          AirlinePersonality.balanced => 52,
        },
      );
      _markAirportHub(seed.startHub);
      try {
        final route = _createRouteForAirline(
          airlineId: airlineId,
          originIata: seed.startHub,
          destinationIata: seed.secondHub,
          aircraftTypeId: seed.aircraftTypeId,
          flightsPerWeek: _defaultAiFrequency(seed.personality),
          buyNewAircraft: true,
        );
        _optimiseRouteForAirline(route.id, airlineId);
      } catch (_) {
        // Seed data should be valid, but a skipped AI is better than blocking a new game.
      }
    }
  }

  int _defaultAiFrequency(AirlinePersonality personality) =>
      switch (personality) {
        AirlinePersonality.aggressive => 12,
        AirlinePersonality.budget => 14,
        AirlinePersonality.premium => 7,
        AirlinePersonality.conservative => 5,
        AirlinePersonality.balanced => 8,
      };

  double _aiPriceMultiplier(AirlinePersonality personality) =>
      switch (personality) {
        AirlinePersonality.aggressive => 0.9,
        AirlinePersonality.budget => 0.78,
        AirlinePersonality.premium => 1.22,
        AirlinePersonality.conservative => 1.05,
        AirlinePersonality.balanced => 1,
      };

  RoutePlan _createRouteForAirline({
    required String airlineId,
    required String originIata,
    required String destinationIata,
    required String aircraftTypeId,
    int flightsPerWeek = 7,
    bool buyNewAircraft = true,
  }) {
    final airline = airlines[airlineId];
    final origin = airportByIata(originIata);
    final destination = airportByIata(destinationIata);
    final type = aircraftTypesById[aircraftTypeId];
    if (airline == null ||
        origin == null ||
        destination == null ||
        type == null) {
      throw ArgumentError('Invalid AI route inputs');
    }
    final distance = haversineKm(
      origin.lat,
      origin.lon,
      destination.lat,
      destination.lon,
    );
    if (distance > type.rangeKm ||
        !canAirportHandleAircraft(origin, type) ||
        !canAirportHandleAircraft(destination, type)) {
      throw StateError('AI route cannot be flown');
    }
    final routeId = 'rt-' + (_nextRoute++).toString();
    final shellRoute = RoutePlan(
      id: routeId,
      airlineId: airlineId,
      originIata: origin.iata,
      destinationIata: destination.iata,
      flightsPerWeek: flightsPerWeek.clamp(1, 21),
      priceEconomy: 0,
      priceBusiness: 0,
      createdGameDay: gameDay,
      distanceKm: distance,
    );
    final previewAircraft = Aircraft(
      id: 'preview',
      typeId: type.id,
      name: 'Preview',
      airlineId: airlineId,
      purchasedGameDay: gameDay,
    );
    final costs = computeFlightCost(
      shellRoute,
      previewAircraft,
      type,
      origin,
      destination,
      globalFuelPrice,
      currentGameDay: gameDay,
    );
    final seats = type.seatsEconomy + type.seatsBusiness;
    final suggestedEco = seats > 0
        ? (costs.totalCost /
                  seats *
                  1.3 *
                  _aiPriceMultiplier(airline.personality))
              .round()
        : 200;
    routes[routeId] = shellRoute.copyWith(
      priceEconomy: suggestedEco,
      priceBusiness: type.seatsBusiness > 0 ? suggestedEco * 4 : 0,
      flightDurationHours: costs.flightDurationHours,
    );
    airlines[airlineId] = airline.copyWith(
      routeIds: [...airline.routeIds, routeId],
    );
    if (buyNewAircraft) {
      final ac = buyAircraft(type.id, routeId: routeId, airlineId: airlineId);
      routes[routeId] = routes[routeId]!.copyWith(aircraftId: ac.id);
    }
    return routes[routeId]!;
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
      currentLat: airportByIata(owner.hubIatas.firstOrNull ?? 'LHR')?.lat ?? 0,
      currentLon: airportByIata(owner.hubIatas.firstOrNull ?? 'LHR')?.lon ?? 0,
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

  Aircraft buyAircraftForRoute(String typeId, String routeId) {
    final route = routes[routeId];
    final type = aircraftTypesById[typeId];
    final origin = route == null ? null : airportByIata(route.originIata);
    final destination = route == null
        ? null
        : airportByIata(route.destinationIata);
    if (route == null ||
        type == null ||
        origin == null ||
        destination == null) {
      throw StateError('Route or aircraft data missing');
    }
    if (type.rangeKm < route.distanceKm) {
      throw StateError('Aircraft range too short for route');
    }
    if (!canAirportHandleAircraft(origin, type) ||
        !canAirportHandleAircraft(destination, type)) {
      throw StateError('Airport runway too short for aircraft');
    }
    final ac = buyAircraft(typeId);
    assignAircraftToRoute(ac.id, routeId);
    return aircraft[ac.id]!;
  }

  void assignAircraftToRoute(String aircraftId, String? routeId) {
    final ac = aircraft[aircraftId];
    if (ac == null || ac.airlineId != 'player') {
      throw StateError('Aircraft not found');
    }
    if (routeId != null) {
      final route = routes[routeId];
      final type = aircraftTypesById[ac.typeId];
      final origin = route == null ? null : airportByIata(route.originIata);
      final destination = route == null
          ? null
          : airportByIata(route.destinationIata);
      if (route == null ||
          type == null ||
          origin == null ||
          destination == null) {
        throw StateError('Route data missing');
      }
      if (type.rangeKm < route.distanceKm) {
        throw StateError('Aircraft range too short for route');
      }
      if (!canAirportHandleAircraft(origin, type) ||
          !canAirportHandleAircraft(destination, type)) {
        throw StateError('Airport runway too short for aircraft');
      }
      final previousAircraftId = route.aircraftId;
      if (previousAircraftId != null &&
          previousAircraftId != aircraftId &&
          aircraft[previousAircraftId] != null) {
        aircraft[previousAircraftId] = aircraft[previousAircraftId]!.copyWith(
          clearAssignedRoute: true,
          status: AircraftStatus.idle,
        );
      }
      routes[routeId] = route.copyWith(aircraftId: aircraftId, isActive: true);
    }
    if (ac.assignedRouteId != null && ac.assignedRouteId != routeId) {
      final oldRoute = routes[ac.assignedRouteId!];
      if (oldRoute != null) {
        routes[oldRoute.id] = oldRoute.copyWith(
          clearAircraft: true,
          isActive: false,
        );
      }
    }
    aircraft[aircraftId] = ac.copyWith(
      assignedRouteId: routeId,
      clearAssignedRoute: routeId == null,
      status: routeId == null ? AircraftStatus.idle : AircraftStatus.flying,
    );
    notifyListeners();
  }

  double sellAircraft(String aircraftId) {
    final ac = aircraft[aircraftId];
    if (ac == null || ac.airlineId != 'player') {
      throw StateError('Aircraft not found');
    }
    if (ac.status == AircraftStatus.maintenance) {
      throw StateError('Cannot sell aircraft in maintenance');
    }
    final value = computeAircraftValue(ac, gameDay);
    if (ac.assignedRouteId != null) {
      final route = routes[ac.assignedRouteId!];
      if (route != null) {
        routes[route.id] = route.copyWith(clearAircraft: true, isActive: false);
      }
    }
    aircraft.remove(aircraftId);
    airlines['player'] = player.copyWith(
      cashUSD: player.cashUSD + value,
      fleetIds: player.fleetIds.where((id) => id != aircraftId).toList(),
    );
    newsTicker.add('${ac.name} sold for \$${value.round()}.');
    notifyListeners();
    return value;
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
    final origin = airportByIata(originIata);
    final destination = airportByIata(destinationIata);
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

  NewsArticle? get latestArticle =>
      latestArticleId == null ? null : newsArticles[latestArticleId];

  NewsArticle triggerAircraftIncident(String aircraftId, {bool ground = true}) {
    final ac = aircraft[aircraftId];
    if (ac == null) throw StateError('Aircraft not found');
    final type = aircraftTypesById[ac.typeId];
    final airline = airlines[ac.airlineId] ?? player;
    final route = ac.assignedRouteId == null
        ? null
        : routes[ac.assignedRouteId!];
    final airport = route == null
        ? airportByIata(airline.hubIatas.firstOrNull ?? 'LHR')
        : airportByIata(route.originIata);
    final routeLabel = route == null
        ? 'unassigned services'
        : '${route.originIata}-${route.destinationIata}';
    final conditionDelta = ground ? 14.0 : 6.0;
    final nextCondition = math.max(0.0, ac.condition - conditionDelta);
    final reason = ground
        ? 'Technical incident at ${airport?.iata ?? 'base'}'
        : null;
    aircraft[aircraftId] = ac.copyWith(
      condition: nextCondition,
      isGrounded: ground,
      groundedReason: reason,
      status: ground ? AircraftStatus.idle : ac.status,
    );
    final maintenanceCost = maintenanceCostForIncident(aircraftId);
    final article = NewsArticle(
      id: 'article-$gameDay-${newsArticles.length + 1}',
      headline: ground
          ? '${airline.name} aircraft grounded'
          : '${airline.name} aircraft technical fault',
      subheadline:
          '${ac.name} reported a technical issue at ${airport?.city ?? 'base'}',
      paragraphs: [
        '${airline.name} ${type?.model ?? ac.typeId} ${ac.name} reported a technical issue while operating $routeLabel.',
        ground
            ? 'The aircraft has been withdrawn from service pending maintenance. Passengers on affected services may face disruption until the aircraft is cleared.'
            : 'The issue was resolved without grounding, but engineers have logged additional maintenance work.',
        'Operations control can send the aircraft to maintenance from the fleet panel. The estimated standard maintenance cost is ${maintenanceCost.round()} USD.',
      ],
      severity: ground ? 'grounding' : 'technical',
      gameDay: gameDay,
      actionAircraftId: aircraftId,
      actionMaintenanceCost: maintenanceCost.round(),
    );
    newsArticles[article.id] = article;
    latestArticleId = article.id;
    newsTicker.add(
      '!! ${article.headline}: ${article.subheadline} · Read the article',
    );
    if (newsTicker.length > 20)
      newsTicker.removeRange(0, newsTicker.length - 20);
    notifyListeners();
    return article;
  }

  int maintenanceCostForIncident(String aircraftId) =>
      maintenanceCost(aircraftId, MaintenanceTier.standard);

  void _maybeRunRandomFleetEvent() {
    if (gameDay == 0 || gameDay % 9 != 0) return;
    final candidates = playerFleet
        .where(
          (ac) =>
              ac.status != AircraftStatus.maintenance &&
              ac.status != AircraftStatus.crashed,
        )
        .toList();
    if (candidates.isEmpty) return;
    final index = (gameDay + candidates.length) % candidates.length;
    triggerAircraftIncident(candidates[index].id, ground: true);
  }

  int maintenanceCost(String aircraftId, MaintenanceTier tier) {
    final ac = aircraft[aircraftId];
    final type = ac == null ? null : aircraftTypesById[ac.typeId];
    if (ac == null || type == null) return 0;
    return computeMaintenanceCost(
      tier,
      ac.maintenanceHoursOwed,
      type.maintenanceCostPerHourUSD,
      ageMultiplier: getMaintenanceAgeMultiplier(ac, gameDay),
    );
  }

  void startMaintenance(String aircraftId, MaintenanceTier tier) {
    final ac = aircraft[aircraftId];
    if (ac == null || ac.airlineId != 'player')
      throw StateError('Aircraft not found');
    if (ac.status == AircraftStatus.maintenance) return;
    final cost = maintenanceCost(aircraftId, tier);
    if (player.cashUSD < cost)
      throw StateError('Not enough cash for maintenance');
    aircraft[aircraftId] = ac.copyWith(
      status: AircraftStatus.maintenance,
      isGrounded: true,
      lastMaintenanceGameDay: gameDay,
      activeMaintTier: tier,
    );
    airlines['player'] = player.copyWith(cashUSD: player.cashUSD - cost);
    newsTicker.add('${ac.name} entered ${tier.name} maintenance.');
    notifyListeners();
  }

  void completeMaintenance(String aircraftId) {
    final ac = aircraft[aircraftId];
    if (ac == null) return;
    final tier = ac.activeMaintTier ?? MaintenanceTier.standard;
    final cfg = maintenanceTiers[tier]!;
    final condition = tier == MaintenanceTier.full
        ? 100.0
        : math.min(100.0, ac.condition + cfg.conditionGain);
    aircraft[aircraftId] = ac.copyWith(
      status: AircraftStatus.idle,
      isGrounded: condition < 20,
      groundedReason: condition < 20
          ? 'Critical condition - requires maintenance'
          : null,
      condition: condition,
      maintenanceHoursOwed: 0,
      lastMaintenanceGameDay: gameDay,
    );
    newsTicker.add('${ac.name} returned from maintenance.');
    notifyListeners();
  }

  void _completeDueMaintenance(String airlineId) {
    final airline = airlines[airlineId];
    if (airline == null) return;
    for (final aircraftId in airline.fleetIds) {
      final ac = aircraft[aircraftId];
      if (ac == null || ac.status != AircraftStatus.maintenance) continue;
      final tier = ac.activeMaintTier ?? MaintenanceTier.standard;
      final duration = maintenanceTiers[tier]?.durationDays ?? 2;
      if (gameDay - ac.lastMaintenanceGameDay >= duration) {
        completeMaintenance(aircraftId);
      }
    }
  }

  void updateRouteSettings(
    String routeId, {
    int? flightsPerWeek,
    int? priceEconomy,
    int? priceBusiness,
    bool? isActive,
  }) {
    final route = routes[routeId];
    if (route == null) throw StateError('Route not found');
    routes[routeId] = route.copyWith(
      flightsPerWeek: flightsPerWeek?.clamp(1, 21),
      priceEconomy: priceEconomy == null ? null : math.max(0, priceEconomy),
      priceBusiness: priceBusiness == null ? null : math.max(0, priceBusiness),
      isActive: isActive,
    );
    notifyListeners();
  }

  RouteOptimisationResult optimiseRoute(String routeId) =>
      _optimiseRouteForAirline(routeId, 'player');

  RouteOptimisationResult _optimiseRouteForAirline(
    String routeId,
    String airlineId,
  ) {
    final route = routes[routeId];
    if (route == null || route.aircraftId == null)
      throw StateError('Route has no aircraft');
    final ac = aircraft[route.aircraftId];
    final type = ac == null ? null : aircraftTypesById[ac.typeId];
    final origin = airportByIata(route.originIata);
    final destination = airportByIata(route.destinationIata);
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
        airline: airlines[airlineId] ?? player,
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
    final nextAirportPax = <String, double>{};
    final allRoutes = routes.values.toList(growable: false);
    final allAirlines = airlines.values.toList(growable: false);
    final snapshots = <String, DailySnapshot>{};
    final passengerTotals = <String, int>{};
    final netProfits = <String, double>{};

    for (final airlineId in airlines.keys.toList()) {
      final airline = airlines[airlineId];
      if (airline == null || airline.isInsolvent) continue;
      var totalRevenue = 0.0;
      var totalCost = 0.0;
      var totalPassengers = 0;

      _completeDueMaintenance(airlineId);

      for (final routeId in airline.routeIds) {
        final route = routes[routeId];
        if (route == null || route.aircraftId == null) continue;
        final ac = aircraft[route.aircraftId];
        final type = ac == null ? null : aircraftTypesById[ac.typeId];
        final origin = airportByIata(route.originIata);
        final destination = airportByIata(route.destinationIata);
        if (ac == null || type == null || origin == null || destination == null)
          continue;
        final result = calculateRouteEconomics(
          route: route,
          aircraft: ac,
          type: type,
          origin: origin,
          destination: destination,
          airline: airline,
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

      final loans = airline.isPlayer ? airline.loans : const <Loan>[];
      final debtService = airline.isPlayer
          ? calculateDailyDebtService(airline)
          : 0.0;
      totalCost += debtService;
      final profit = totalRevenue - totalCost;
      final paidLoans = debtService > 0
          ? applyLoanPayment(
              loans,
              math.min(airline.cashUSD + totalRevenue, debtService),
            )
          : loans;
      final snapshot = DailySnapshot(
        gameDay: gameDay,
        revenue: totalRevenue,
        costs: totalCost,
        profit: profit,
        passengers: totalPassengers,
        cashEnd: airline.cashUSD + profit,
      );
      final history = [...airline.dailyStats, snapshot];
      snapshots[airlineId] = snapshot;
      netProfits[airlineId] = profit;
      passengerTotals[airlineId] = totalPassengers;
      airlines[airlineId] = airline.copyWith(
        cashUSD: airline.cashUSD + profit,
        totalDebt: paidLoans.fold<double>(
          0,
          (sum, loan) => sum + loan.principalUSD,
        ),
        loans: paidLoans,
        lastDailyProfit: profit,
        totalPassengersAllTime:
            airline.totalPassengersAllTime + totalPassengers,
        dailyStats: history.length > 30
            ? history.sublist(history.length - 30)
            : history,
      );
    }

    var playerDividendTotal = 0.0;
    for (final entry in netProfits.entries) {
      final payer = airlines[entry.key];
      if (payer == null || payer.isPlayer || entry.value <= 0) continue;
      var payerCash = payer.cashUSD;
      for (final shareholder in payer.shareholders.entries) {
        final receiver = airlines[shareholder.key];
        if (receiver == null || shareholder.value <= 0) continue;
        final amount = entry.value * (shareholder.value / 100);
        if (amount <= 0) continue;
        payerCash -= amount;
        airlines[shareholder.key] = receiver.copyWith(
          cashUSD: receiver.cashUSD + amount,
        );
        if (shareholder.key == 'player') playerDividendTotal += amount;
      }
      airlines[entry.key] = (airlines[entry.key] ?? payer).copyWith(
        cashUSD: payerCash,
      );
    }
    if (playerDividendTotal > 500000) {
      newsTicker.add(
        'Dividends: \$${playerDividendTotal.round()} received from shareholdings today.',
      );
    }

    _updateMarketShare(passengerTotals);
    _maybeExpandAI();
    airportDailyPax
      ..clear()
      ..addAll(nextAirportPax);
    gameDay += 1;
    _maybeRunRandomFleetEvent();
    final playerSnapshot =
        snapshots['player'] ??
        DailySnapshot(
          gameDay: gameDay,
          revenue: 0,
          costs: 0,
          profit: 0,
          passengers: 0,
          cashEnd: player.cashUSD,
        );
    newsTicker.add(
      'Day $gameDay: profit ${playerSnapshot.profit.round()} USD, passengers ${playerSnapshot.passengers}.',
    );
    if (newsTicker.length > 20)
      newsTicker.removeRange(0, newsTicker.length - 20);
    notifyListeners();
    return playerSnapshot;
  }

  void _updateMarketShare(Map<String, int> passengerTotals) {
    final total = passengerTotals.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    for (final entry in airlines.entries.toList()) {
      final share = total <= 0
          ? 0.0
          : ((passengerTotals[entry.key] ?? 0) / total) * 100;
      airlines[entry.key] = entry.value.copyWith(marketSharePercent: share);
    }
    final playerShare = airlines['player']?.marketSharePercent ?? 0;
    final competitorsWithShare = competitors.any(
      (airline) => airline.marketSharePercent > 0,
    );
    if (settings.objective == GameObjective.marketShare &&
        competitorsWithShare &&
        playerShare >= settings.targetMarketShare) {
      hasWon = true;
    }
  }

  void _maybeExpandAI() {
    if (gameDay == 0 || gameDay % 10 != 0) return;
    for (final airline in competitors) {
      if (airline.cashUSD < 18000000 || airline.routeIds.length >= 8) continue;
      final hub = airportByIata(airline.hubIatas.firstOrNull ?? '');
      if (hub == null) continue;
      final existingDestinations = airline.routeIds
          .map((id) => routes[id])
          .whereType<RoutePlan>()
          .map((route) => route.destinationIata)
          .toSet();
      final candidates =
          airportList
              .where(
                (airport) =>
                    airport.iata != hub.iata &&
                    !existingDestinations.contains(airport.iata),
              )
              .map(
                (airport) => (
                  airport: airport,
                  demand: baselineDailyPassengers(hub, airport),
                ),
              )
              .toList()
            ..sort((a, b) => b.demand.compareTo(a.demand));
      for (final candidate in candidates.take(20)) {
        final type = _pickAircraftForAI(airline, hub, candidate.airport);
        if (type == null || airline.cashUSD < type.purchasePrice + 10000000)
          continue;
        try {
          final route = _createRouteForAirline(
            airlineId: airline.id,
            originIata: hub.iata,
            destinationIata: candidate.airport.iata,
            aircraftTypeId: type.id,
            flightsPerWeek: _defaultAiFrequency(airline.personality),
            buyNewAircraft: true,
          );
          _optimiseRouteForAirline(route.id, airline.id);
          newsTicker.add(
            '${airline.name} launches ${hub.iata}-${candidate.airport.iata}.',
          );
          break;
        } catch (_) {
          continue;
        }
      }
    }
  }

  AircraftType? _pickAircraftForAI(
    Airline airline,
    Airport origin,
    Airport destination,
  ) {
    final distance = haversineKm(
      origin.lat,
      origin.lon,
      destination.lat,
      destination.lon,
    );
    final affordable = aircraftTypes
        .where(
          (type) =>
              type.rangeKm >= distance &&
              canAirportHandleAircraft(origin, type) &&
              canAirportHandleAircraft(destination, type) &&
              type.purchasePrice <= airline.cashUSD * 0.35,
        )
        .toList();
    if (affordable.isEmpty) return null;
    affordable.sort((a, b) => a.purchasePrice.compareTo(b.purchasePrice));
    return affordable[affordable.length ~/ 2];
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

  double buyShares(String targetAirlineId, double percent) {
    final target = airlines[targetAirlineId];
    if (target == null || target.isPlayer) {
      throw StateError('Target airline not found');
    }
    final amount = percent.clamp(1, 50).toDouble();
    final available = marketFloatForAirline(targetAirlineId);
    if (available < amount) throw StateError('Not enough market float');
    final cost = sharePurchasePrice(targetAirlineId, amount);
    if (player.cashUSD < cost) throw StateError('Not enough cash');
    final nextShareholders = Map<String, double>.from(target.shareholders);
    nextShareholders['player'] = (nextShareholders['player'] ?? 0) + amount;
    airlines['player'] = player.copyWith(cashUSD: player.cashUSD - cost);
    airlines[targetAirlineId] = target.copyWith(
      cashUSD: target.cashUSD + cost,
      shareholders: nextShareholders,
    );
    newsTicker.add(
      'You acquired ${amount.toStringAsFixed(0)}% of ${target.name} for \$${cost.round()}.',
    );
    notifyListeners();
    return cost;
  }

  double sellShares(String targetAirlineId, double percent) {
    final target = airlines[targetAirlineId];
    if (target == null || target.isPlayer) {
      throw StateError('Target airline not found');
    }
    final owned = playerStakeIn(targetAirlineId);
    if (owned < 1) throw StateError('No shares owned');
    final amount = percent.clamp(1, owned).toDouble();
    final proceeds =
        (companyValue(targetAirlineId) / 100 * amount / 100000).round() *
        100000.0;
    final nextShareholders = Map<String, double>.from(target.shareholders);
    final remaining = (nextShareholders['player'] ?? 0) - amount;
    if (remaining <= 0) {
      nextShareholders.remove('player');
    } else {
      nextShareholders['player'] = remaining;
    }
    airlines['player'] = player.copyWith(cashUSD: player.cashUSD + proceeds);
    airlines[targetAirlineId] = target.copyWith(shareholders: nextShareholders);
    newsTicker.add(
      'You sold ${amount.toStringAsFixed(0)}% of ${target.name} for \$${proceeds.round()}.',
    );
    notifyListeners();
    return proceeds;
  }

  double takeoverAirline(String targetAirlineId) {
    final target = airlines[targetAirlineId];
    if (target == null || target.isPlayer) {
      throw StateError('Target airline not found');
    }
    final stake = playerStakeIn(targetAirlineId);
    if (!target.isInsolvent && stake < 50) {
      throw StateError('Majority stake required');
    }
    final valuation = buyoutPrice(targetAirlineId);
    final ownedValue = companyValue(targetAirlineId) * (stake / 100);
    final price = math.max(0, valuation.totalPrice - ownedValue).toDouble();
    if (player.cashUSD < price) throw StateError('Not enough cash');

    final acquiredFleet = <String>[];
    for (final aircraftId in target.fleetIds) {
      final ac = aircraft[aircraftId];
      if (ac == null) continue;
      final type = aircraftTypesById[ac.typeId];
      final hasRoute = ac.assignedRouteId != null;
      aircraft[aircraftId] = ac.copyWith(
        airlineId: 'player',
        name: type == null
            ? '${player.name} aircraft'
            : '${player.name} ${type.model}',
        isGrounded: false,
        status: hasRoute ? AircraftStatus.flying : AircraftStatus.idle,
      );
      acquiredFleet.add(aircraftId);
    }

    final acquiredRoutes = <String>[];
    for (final routeId in target.routeIds) {
      final route = routes[routeId];
      if (route == null) continue;
      routes[routeId] = route.copyWith(
        airlineId: 'player',
        isActive: route.aircraftId != null,
        dailyRevenue: 0,
        dailyCost: 0,
        dailyProfit: 0,
        dailyPassengers: 0,
        loadFactorEconomy: 0,
        loadFactorBusiness: 0,
      );
      acquiredRoutes.add(routeId);
    }

    for (final entry in airlines.entries.toList()) {
      if (entry.key == targetAirlineId) continue;
      final holdings = Map<String, double>.from(entry.value.shareholders);
      final transferred = holdings.remove(targetAirlineId);
      if (transferred != null) {
        holdings['player'] = (holdings['player'] ?? 0) + transferred;
        airlines[entry.key] = entry.value.copyWith(shareholders: holdings);
      }
    }

    airlines['player'] = player.copyWith(
      cashUSD: player.cashUSD - price,
      fleetIds: [...player.fleetIds, ...acquiredFleet],
      routeIds: [...player.routeIds, ...acquiredRoutes],
    );
    airlines.remove(targetAirlineId);
    newsTicker.add('${player.name} has acquired ${target.name}.');
    notifyListeners();
    return price;
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
    'airportUpgrades': airportUpgrades.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'airportDailyPax': airportDailyPax,
    'newsTicker': newsTicker,
    'newsArticles': newsArticles.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'latestArticleId': latestArticleId,
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
    airportUpgrades
      ..clear()
      ..addAll(
        (raw['airportUpgrades'] as Map? ?? const {}).map(
          (key, value) => MapEntry(
            key as String,
            AirportUpgrade.fromJson(Map<String, Object?>.from(value as Map)),
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
    newsArticles
      ..clear()
      ..addAll(
        (raw['newsArticles'] as Map? ?? const {}).map(
          (key, value) => MapEntry(
            key as String,
            NewsArticle.fromJson(Map<String, Object?>.from(value as Map)),
          ),
        ),
      );
    latestArticleId = raw['latestArticleId'] as String?;
    _nextAircraft =
        (raw['nextAircraft'] as num?)?.round() ?? aircraft.length + 1;
    _nextRoute = (raw['nextRoute'] as num?)?.round() ?? routes.length + 1;
    _nextLoan = (raw['nextLoan'] as num?)?.round() ?? 1;
    for (final airline in airlines.values) {
      for (final hubIata in airline.hubIatas) {
        _markAirportHub(hubIata);
      }
    }
    notifyListeners();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
