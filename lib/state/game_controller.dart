import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/geo.dart';
import '../data/aircraft_types.dart';
import '../data/airports.dart';
import '../engine/ai_preferences.dart';
import '../engine/demand_model.dart';
import '../engine/economics_engine.dart';
import '../engine/finance.dart';
import '../engine/hub_upgrades.dart';
import '../engine/route_optimizer.dart';
import '../engine/valuation.dart';
import '../models/models.dart';

const optimiseAllBaseCostUSD = 2000000.0;
const optimiseAllCostPerRouteUSD = 2500000.0;
const gameDayMs = 86400000;
const _airportEventSampleSize = 45;
const _eventScale = 0.6;

class NetworkOptimisationPreview {
  const NetworkOptimisationPreview({
    required this.eligibleCount,
    required this.optimisableCount,
    required this.costUSD,
  });

  final int eligibleCount;
  final int optimisableCount;
  final double costUSD;

  bool get hasChanges => optimisableCount > 0;
}

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

class _AirportEventDef {
  const _AirportEventDef({
    required this.id,
    required this.newsTemplate,
    required this.closureReason,
    required this.minDays,
    required this.maxDays,
    required this.probability,
    required this.sizesAffected,
  });

  final String id;
  final String newsTemplate;
  final String closureReason;
  final int minDays;
  final int maxDays;
  final double probability;
  final Set<AirportSize> sizesAffected;
}

const _airportEvents = <_AirportEventDef>[
  _AirportEventDef(
    id: 'storm',
    newsTemplate:
        'STORM: Severe weather forces closure of {city} Airport ({airport}). Flights suspended for {duration}.',
    closureReason: 'Storm',
    minDays: 1,
    maxDays: 2,
    probability: 0.0004,
    sizesAffected: {
      AirportSize.small,
      AirportSize.medium,
      AirportSize.large,
      AirportSize.major,
    },
  ),
  _AirportEventDef(
    id: 'blizzard',
    newsTemplate:
        'BLIZZARD: Heavy snowfall shuts down {city} Airport ({airport}). Operations halted for {duration}.',
    closureReason: 'Blizzard',
    minDays: 1,
    maxDays: 3,
    probability: 0.0003,
    sizesAffected: {AirportSize.medium, AirportSize.large, AirportSize.major},
  ),
  _AirportEventDef(
    id: 'fog',
    newsTemplate:
        'FOG: Dense fog blankets {city} Airport ({airport}), forcing a {duration} suspension of all flights.',
    closureReason: 'Dense fog',
    minDays: 1,
    maxDays: 1,
    probability: 0.0005,
    sizesAffected: {
      AirportSize.small,
      AirportSize.medium,
      AirportSize.large,
      AirportSize.major,
    },
  ),
  _AirportEventDef(
    id: 'it_outage',
    newsTemplate:
        'IT OUTAGE: Systems failure at {city} Airport ({airport}) grounds all flights. Engineers working to restore services.',
    closureReason: 'IT outage',
    minDays: 1,
    maxDays: 1,
    probability: 0.0003,
    sizesAffected: {AirportSize.large, AirportSize.major},
  ),
  _AirportEventDef(
    id: 'security_alert',
    newsTemplate:
        'SECURITY: {city} Airport ({airport}) evacuated and closed following a security alert. Flights diverted.',
    closureReason: 'Security alert',
    minDays: 1,
    maxDays: 1,
    probability: 0.0002,
    sizesAffected: {AirportSize.large, AirportSize.major},
  ),
  _AirportEventDef(
    id: 'runway_incident',
    newsTemplate:
        'RUNWAY CLOSED: {city} Airport ({airport}) runway closed following an aircraft incident. Flights suspended for {duration}.',
    closureReason: 'Runway incident',
    minDays: 1,
    maxDays: 2,
    probability: 0.0003,
    sizesAffected: {AirportSize.medium, AirportSize.large, AirportSize.major},
  ),
  _AirportEventDef(
    id: 'ash_cloud',
    newsTemplate:
        'ASH CLOUD: Volcanic ash disruption closes {city} Airport ({airport}) for {duration}.',
    closureReason: 'Volcanic ash',
    minDays: 1,
    maxDays: 3,
    probability: 0.00015,
    sizesAffected: {
      AirportSize.small,
      AirportSize.medium,
      AirportSize.large,
      AirportSize.major,
    },
  ),
  _AirportEventDef(
    id: 'flood',
    newsTemplate:
        'FLOODING: Flash flooding at {city} Airport ({airport}) suspends all operations for {duration}.',
    closureReason: 'Flooding',
    minDays: 1,
    maxDays: 2,
    probability: 0.0002,
    sizesAffected: {
      AirportSize.small,
      AirportSize.medium,
      AirportSize.large,
      AirportSize.major,
    },
  ),
  _AirportEventDef(
    id: 'bird_flock',
    newsTemplate:
        'BIRD STRIKE RISK: Large bird flock grounds all traffic at {city} Airport ({airport}) for {duration}.',
    closureReason: 'Bird flock hazard',
    minDays: 1,
    maxDays: 1,
    probability: 0.0002,
    sizesAffected: {AirportSize.small, AirportSize.medium},
  ),
  _AirportEventDef(
    id: 'power_failure',
    newsTemplate:
        'POWER FAILURE: Major blackout at {city} Airport ({airport}) halts all operations. Backup power insufficient.',
    closureReason: 'Power failure',
    minDays: 1,
    maxDays: 2,
    probability: 0.00025,
    sizesAffected: {AirportSize.medium, AirportSize.large, AirportSize.major},
  ),
];

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
  bool hasLost = false;
  ThemeModeSetting themeMode = ThemeModeSetting.dark;
  double globalFuelPrice = fuelPriceUsdPerLiter;
  final airlines = <String, Airline>{};
  final aircraft = <String, Aircraft>{};
  final routes = <String, RoutePlan>{};
  final airportUpgrades = <String, AirportUpgrade>{};
  final airportDailyPax = <String, double>{};
  final newsTicker = <NewsTickerItem>[];
  final newsArticles = <String, NewsArticle>{};
  String? latestArticleId;
  int _nextAircraft = 1;
  int _nextRoute = 1;
  int _nextLoan = 1;
  int _nextTicker = 1;

  void pushNewsItem(
    String text, {
    String severity = 'normal',
    String? articleId,
    bool playerRelated = false,
  }) {
    newsTicker.insert(
      0,
      NewsTickerItem(
        id: 'ticker-$gameDay-${_nextTicker++}',
        text: text,
        severity: severity,
        articleId: articleId,
        playerRelated: playerRelated,
      ),
    );
    if (newsTicker.length > 20) {
      newsTicker.removeRange(20, newsTicker.length);
    }
  }

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

  bool isAirportClosed(String iata) {
    final airport = airportByIata(iata);
    final closedUntil = airport?.closedUntilGameDay;
    return closedUntil != null && closedUntil >= gameDay;
  }

  void setAirportClosure(String iata, int untilGameDay, String reason) {
    if (!airportsByIata.containsKey(iata)) return;
    final current = airportUpgrades[iata] ?? const AirportUpgrade();
    airportUpgrades[iata] = current.copyWith(
      closedUntilGameDay: untilGameDay,
      closureReason: reason,
    );
    notifyListeners();
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

  void advanceGameClock(Duration realDelta) {
    if (isPaused || speed <= 0) return;
    final delta = (realDelta.inMilliseconds * speed).round();
    if (delta <= 0) return;
    _advanceAircraftPositions(delta);
    gameTimeMs += delta;
    final targetDay = gameTimeMs ~/ gameDayMs;
    var daysProcessed = 0;
    while (gameDay < targetDay && daysProcessed < 14) {
      runDailyTick();
      daysProcessed += 1;
    }
    if (daysProcessed == 0) notifyListeners();
  }

  void _advanceAircraftPositions(int deltaGameMs) {
    for (final route in routes.values) {
      if (!route.isActive || route.aircraftId == null) continue;
      final ac = aircraft[route.aircraftId!];
      final type = ac == null ? null : aircraftTypesById[ac.typeId];
      final origin = airportByIata(route.originIata);
      final destination = airportByIata(route.destinationIata);
      if (ac == null ||
          type == null ||
          origin == null ||
          destination == null ||
          ac.isGrounded ||
          ac.status == AircraftStatus.maintenance ||
          ac.status == AircraftStatus.crashed ||
          _isAirportClosed(origin) ||
          _isAirportClosed(destination)) {
        continue;
      }
      final flightMs = math.max(
        1.0,
        (route.distanceKm / type.cruiseSpeedKmh) * 3600000,
      );
      final cycleMs = flightMs * 2;
      final cycle = (ac.flightProgress * cycleMs + deltaGameMs) % cycleMs;
      final outbound = cycle < flightMs;
      final legProgress = outbound
          ? cycle / flightMs
          : (cycle - flightMs) / flightMs;
      final fromLat = outbound ? origin.lat : destination.lat;
      final fromLon = outbound ? origin.lon : destination.lon;
      final toLat = outbound ? destination.lat : origin.lat;
      final toLon = outbound ? destination.lon : origin.lon;
      aircraft[ac.id] = ac.copyWith(
        currentLat: fromLat + (toLat - fromLat) * legProgress,
        currentLon: fromLon + (toLon - fromLon) * legProgress,
        flightProgress: cycle / cycleMs,
        status: AircraftStatus.flying,
      );
    }
  }

  void dismissGameOutcome() {
    hasWon = false;
    hasLost = false;
    notifyListeners();
  }

  void setThemeMode(ThemeModeSetting mode) {
    themeMode = mode;
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

  bool removePlayerHub(String iata) {
    if (!player.hubIatas.contains(iata) || player.hubIatas.length <= 1) {
      return false;
    }
    airlines['player'] = player.copyWith(
      hubIatas: player.hubIatas.where((hub) => hub != iata).toList(),
    );
    final current = airportUpgrades[iata];
    if (current != null) {
      airportUpgrades[iata] = current.copyWith(isHub: false);
    }
    pushNewsItem('$iata removed from your hub network.', playerRelated: true);
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
    pushNewsItem('${airport.iata} terminal upgraded.', playerRelated: true);
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
    pushNewsItem(
      '${airport.iata} first class lounge upgraded.',
      playerRelated: true,
    );
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
    hasLost = false;
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
    _nextTicker = 1;
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
    pushNewsItem(
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
    pushNewsItem(
      '${ac.name} sold for \$${value.round()}.',
      playerRelated: true,
    );
    notifyListeners();
    return value;
  }

  bool deleteRoute(String routeId) {
    final route = routes[routeId];
    if (route == null || route.airlineId != 'player') return false;
    if (route.aircraftId != null) {
      final ac = aircraft[route.aircraftId!];
      if (ac != null) {
        aircraft[ac.id] = ac.copyWith(
          clearAssignedRoute: true,
          status: AircraftStatus.idle,
        );
      }
    }
    routes.remove(routeId);
    airlines['player'] = player.copyWith(
      routeIds: player.routeIds.where((id) => id != routeId).toList(),
    );
    pushNewsItem(
      '${route.originIata}-${route.destinationIata} route deleted.',
      playerRelated: true,
    );
    notifyListeners();
    return true;
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
    pushNewsItem(
      '${article.headline}: ${article.subheadline}',
      severity: ground ? 'breaking' : 'fleet',
      articleId: article.id,
      playerRelated: airline.isPlayer,
    );
    if (airline.isPlayer &&
        ground &&
        airline.maintenancePolicy.autoMaintainIssues) {
      _startMaintenanceInternal(aircraftId, airline.maintenancePolicy.tier);
    }
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
    if (!_startMaintenanceInternal(aircraftId, tier)) {
      throw StateError('Not enough cash for maintenance');
    }
    notifyListeners();
  }

  void keepIssueAircraftFlying(String aircraftId) {
    final ac = aircraft[aircraftId];
    if (ac == null || ac.airlineId != 'player')
      throw StateError('Aircraft not found');
    final route = ac.assignedRouteId == null
        ? null
        : routes[ac.assignedRouteId!];
    if (route != null) {
      routes[route.id] = route.copyWith(isActive: true);
    }
    aircraft[aircraftId] = ac.copyWith(
      isGrounded: false,
      clearGroundedReason: true,
      status: route == null ? AircraftStatus.idle : AircraftStatus.flying,
      maintenanceHoursOwed: ac.maintenanceHoursOwed + 18,
      knownFaultRiskMod: math.max(ac.knownFaultRiskMod, 3),
    );
    pushNewsItem(
      '${ac.name} returned to service with a known fault logged.',
      severity: 'fleet',
      playerRelated: true,
    );
    notifyListeners();
  }

  bool _startMaintenanceInternal(String aircraftId, MaintenanceTier tier) {
    final ac = aircraft[aircraftId];
    if (ac == null || ac.airlineId != 'player') return false;
    if (ac.status == AircraftStatus.maintenance) return true;
    final cost = maintenanceCost(aircraftId, tier);
    if (player.cashUSD < cost) return false;
    if (ac.assignedRouteId != null) {
      final route = routes[ac.assignedRouteId!];
      if (route != null) {
        routes[route.id] = route.copyWith(isActive: false);
      }
    }
    aircraft[aircraftId] = ac.copyWith(
      status: AircraftStatus.maintenance,
      isGrounded: true,
      lastMaintenanceGameDay: gameDay,
      activeMaintTier: tier,
    );
    airlines['player'] = player.copyWith(cashUSD: player.cashUSD - cost);
    pushNewsItem(
      '${ac.name} entered ${tier.name} maintenance.',
      playerRelated: true,
    );
    return true;
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
    pushNewsItem('${ac.name} returned from maintenance.', playerRelated: true);
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

  void _applyAutoMaintenancePolicy(String airlineId) {
    final airline = airlines[airlineId];
    if (airline == null || !airline.isPlayer) return;
    final policy = airline.maintenancePolicy;
    if (!policy.enabled) return;
    for (final aircraftId in airline.fleetIds.toList()) {
      final ac = aircraft[aircraftId];
      if (ac == null ||
          ac.excludedFromPolicy ||
          ac.status == AircraftStatus.maintenance ||
          ac.status == AircraftStatus.crashed ||
          ac.condition > policy.threshold) {
        continue;
      }
      _startMaintenanceInternal(aircraftId, policy.tier);
    }
  }

  void updateMaintenancePolicy(MaintenancePolicy policy) {
    final next = policy.copyWith(
      threshold: policy.threshold.clamp(20, 80).toDouble(),
    );
    airlines['player'] = player.copyWith(maintenancePolicy: next);
    for (final aircraftId in player.fleetIds) {
      final ac = aircraft[aircraftId];
      if (ac == null || ac.excludedFromPolicy) continue;
      aircraft[aircraftId] = ac.copyWith(
        autoMaintenanceEnabled: next.enabled,
        autoMaintenanceThreshold: next.threshold,
        autoMaintenanceTier: next.tier,
      );
    }
    notifyListeners();
  }

  void setAircraftPolicyExclusion(String aircraftId, bool excluded) {
    final ac = aircraft[aircraftId];
    if (ac == null || ac.airlineId != 'player') return;
    final policy = player.maintenancePolicy;
    aircraft[aircraftId] = ac.copyWith(
      excludedFromPolicy: excluded,
      autoMaintenanceEnabled: excluded
          ? ac.autoMaintenanceEnabled
          : policy.enabled,
      autoMaintenanceThreshold: excluded
          ? ac.autoMaintenanceThreshold
          : policy.threshold,
      autoMaintenanceTier: excluded ? ac.autoMaintenanceTier : policy.tier,
    );
    notifyListeners();
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

  RouteOptimisationInput _optimisationInputForRoute(
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
    return RouteOptimisationInput(
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
    );
  }

  bool _matchesOptimisedResult(
    RoutePlan route,
    RouteOptimisationResult result,
  ) =>
      route.flightsPerWeek == result.flightsPerWeek &&
      route.priceEconomy == result.priceEconomy &&
      route.priceBusiness == result.priceBusiness;

  RouteOptimisationResult? previewRouteOptimisation(String routeId) {
    try {
      final input = _optimisationInputForRoute(routeId, 'player');
      final result = optimiseRouteSettings(input);
      return _matchesOptimisedResult(input.route, result) ? null : result;
    } catch (_) {
      return null;
    }
  }

  RouteOptimisationResult optimiseRoute(String routeId) =>
      _optimiseRouteForAirline(routeId, 'player');

  RouteOptimisationResult _optimiseRouteForAirline(
    String routeId,
    String airlineId,
  ) {
    final input = _optimisationInputForRoute(routeId, airlineId);
    final result = optimiseRouteSettings(input);
    routes[routeId] = input.route.copyWith(
      flightsPerWeek: result.flightsPerWeek,
      priceEconomy: result.priceEconomy,
      priceBusiness: result.priceBusiness,
    );
    notifyListeners();
    return result;
  }

  Map<String, RouteOptimisationResult> _networkOptimisationChanges() {
    final changes = <String, RouteOptimisationResult>{};
    for (final route in playerRoutes) {
      try {
        final input = _optimisationInputForRoute(route.id, 'player');
        final result = optimiseRouteSettings(input);
        if (!_matchesOptimisedResult(input.route, result)) {
          changes[route.id] = result;
        }
      } catch (_) {
        continue;
      }
    }
    return changes;
  }

  int _networkOptimisationEligibleCount() {
    var count = 0;
    for (final route in playerRoutes) {
      try {
        _optimisationInputForRoute(route.id, 'player');
        count += 1;
      } catch (_) {
        continue;
      }
    }
    return count;
  }

  NetworkOptimisationPreview previewNetworkOptimisation() {
    final changes = _networkOptimisationChanges();
    final cost = changes.isEmpty
        ? 0.0
        : optimiseAllBaseCostUSD + changes.length * optimiseAllCostPerRouteUSD;
    return NetworkOptimisationPreview(
      eligibleCount: _networkOptimisationEligibleCount(),
      optimisableCount: changes.length,
      costUSD: cost,
    );
  }

  bool optimiseAllPlayerRoutes() {
    final changes = _networkOptimisationChanges();
    if (changes.isEmpty) return false;
    final cost =
        optimiseAllBaseCostUSD + changes.length * optimiseAllCostPerRouteUSD;
    if (player.cashUSD < cost) return false;
    airlines['player'] = player.copyWith(cashUSD: player.cashUSD - cost);
    for (final entry in changes.entries) {
      final route = routes[entry.key];
      if (route == null) continue;
      final result = entry.value;
      routes[entry.key] = route.copyWith(
        flightsPerWeek: result.flightsPerWeek,
        priceEconomy: result.priceEconomy,
        priceBusiness: result.priceBusiness,
      );
    }
    pushNewsItem(
      'Network optimisation completed for ${changes.length} routes at a consulting cost of \$${cost.round()}.',
      playerRelated: true,
    );
    notifyListeners();
    return true;
  }

  DailySnapshot runDailyTick() {
    _clearExpiredAirportClosures();
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
      _applyAutoMaintenancePolicy(airlineId);

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
      totalCost += airline.hubIatas.length * hubAnnualFeeUsd / 365;
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
      pushNewsItem(
        'Dividends: \$${playerDividendTotal.round()} received from shareholdings today.',
        playerRelated: true,
      );
    }

    _updateMarketShare(passengerTotals);
    _resolveInsolvencies();
    _maybeExpandAI();
    airportDailyPax
      ..clear()
      ..addAll(nextAirportPax);
    gameDay += 1;
    final dayBoundaryMs = gameDay * gameDayMs;
    if (gameTimeMs < dayBoundaryMs) gameTimeMs = dayBoundaryMs;
    _maybeRunRandomFleetEvent();
    _maybeRunAirportClosureEvents();
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
    pushNewsItem(
      'Day $gameDay: profit ${playerSnapshot.profit.round()} USD, passengers ${playerSnapshot.passengers}.',
    );
    notifyListeners();
    return playerSnapshot;
  }

  bool _isAirportClosed(Airport airport) {
    final closedUntil = airport.closedUntilGameDay;
    return closedUntil != null && closedUntil >= gameDay;
  }

  void _clearExpiredAirportClosures() {
    for (final entry in airportUpgrades.entries.toList()) {
      final closedUntil = entry.value.closedUntilGameDay;
      if (closedUntil != null && closedUntil < gameDay) {
        airportUpgrades[entry.key] = entry.value.copyWith(clearClosure: true);
      }
    }
  }

  void _maybeRunAirportClosureEvents() {
    if (airports.isEmpty) return;
    final rng = math.Random(gameDay * 104729 + 37);
    final checks = math.min(_airportEventSampleSize, airports.length);
    final offset = (gameDay * _airportEventSampleSize) % airports.length;

    for (var i = 0; i < checks; i++) {
      final airport = airportByIata(
        airports[(offset + i) % airports.length].iata,
      );
      if (airport == null || _isAirportClosed(airport)) continue;

      for (final event in _airportEvents) {
        if (!event.sizesAffected.contains(airport.size)) continue;
        if (rng.nextDouble() > event.probability * _eventScale) continue;

        final durationDays =
            event.minDays + rng.nextInt(event.maxDays - event.minDays + 1);
        final untilDay = gameDay + durationDays - 1;
        final durationLabel = durationDays == 1
            ? '1 day'
            : '$durationDays days';
        final message = event.newsTemplate
            .replaceAll('{airport}', airport.iata)
            .replaceAll('{city}', airport.city)
            .replaceAll('{duration}', durationLabel);
        final current = airportUpgrades[airport.iata] ?? const AirportUpgrade();
        airportUpgrades[airport.iata] = current.copyWith(
          closedUntilGameDay: untilDay,
          closureReason: event.closureReason,
        );
        pushNewsItem(message, severity: 'breaking');
        break;
      }
    }
  }

  void _resolveInsolvencies() {
    const insolvencyLimit = -100000000.0;
    final playerAirline = airlines['player'];
    if (playerAirline != null && playerAirline.cashUSD <= insolvencyLimit) {
      hasLost = true;
      pushNewsItem(
        '${playerAirline.name} is insolvent after cash fell below -\$100M.',
        severity: 'breaking',
        playerRelated: true,
      );
    }

    var anyCompetitor = false;
    var allCompetitorsInsolvent = true;
    for (final airline in competitors) {
      anyCompetitor = true;
      if (airline.cashUSD > insolvencyLimit) {
        allCompetitorsInsolvent = false;
        continue;
      }
      if (airline.isInsolvent) continue;
      for (final routeId in airline.routeIds) {
        final route = routes[routeId];
        if (route != null) routes[routeId] = route.copyWith(isActive: false);
      }
      airlines[airline.id] = airline.copyWith(
        isInsolvent: true,
        canBeTakenOver: true,
        marketSharePercent: 0,
      );
      pushNewsItem('${airline.name} has entered insolvency protection.');
    }

    if (settings.objective == GameObjective.lastAirlineStanding &&
        anyCompetitor &&
        allCompetitorsInsolvent) {
      hasWon = true;
    }
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
          pushNewsItem(
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
              type.yearIntroduced <= settings.startingYear + gameDay ~/ 365 &&
              type.rangeKm >= distance &&
              canAirportHandleAircraft(origin, type) &&
              canAirportHandleAircraft(destination, type) &&
              type.purchasePrice <= airline.cashUSD * 0.35,
        )
        .toList();
    if (affordable.isEmpty) return null;
    final homeAirport = airportByIata(airline.hubIatas.firstOrNull ?? '');
    affordable.sort((a, b) {
      final scoreA =
          (a.seatsEconomy + a.seatsBusiness * 1.8) *
          aiManufacturerPreferenceWeight(airline, a, homeAirport);
      final scoreB =
          (b.seatsEconomy + b.seatsBusiness * 1.8) *
          aiManufacturerPreferenceWeight(airline, b, homeAirport);
      final scoreCompare = scoreB.compareTo(scoreA);
      return scoreCompare == 0
          ? a.purchasePrice.compareTo(b.purchasePrice)
          : scoreCompare;
    });
    return affordable.first;
  }

  double playerLoanCreditLimit() {
    final recentStats = player.dailyStats.length <= 14
        ? player.dailyStats
        : player.dailyStats.sublist(player.dailyStats.length - 14);
    final averageDailyProfit = recentStats.isEmpty
        ? 0.0
        : recentStats.fold<double>(0, (sum, stat) => sum + stat.profit) /
              recentStats.length;
    final cashCollateral = math.max(0, player.cashUSD) * 0.25;
    final operatingAssetValue = math.max(
      0,
      companyValue(player.id) - math.max(0, player.cashUSD),
    );
    return math.max(
      25000000,
      operatingAssetValue * 1.2 +
          cashCollateral +
          math.max(0, averageDailyProfit) * 365 * 2,
    );
  }

  bool canApplyForLoan(LoanOffer offer) =>
      player.totalDebt + offer.amountUSD <= playerLoanCreditLimit();

  Loan applyForLoan(LoanOffer offer) {
    if (!canApplyForLoan(offer)) {
      throw StateError('Loan exceeds available credit.');
    }
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

  void repayLoan(String loanId, double amountUSD) {
    final loan = player.loans.where((loan) => loan.id == loanId).firstOrNull;
    if (loan == null) return;
    final payment = math
        .max(
          0,
          math.min(amountUSD, math.min(player.cashUSD, loan.principalUSD)),
        )
        .toDouble();
    if (payment <= 0) return;
    final loans = applyLoanPrincipalPayment(player.loans, loanId, payment);
    airlines['player'] = player.copyWith(
      cashUSD: player.cashUSD - payment,
      totalDebt: loans.fold<double>(0, (sum, loan) => sum + loan.principalUSD),
      loans: loans,
    );
    pushNewsItem(
      'Loan repayment made: ${payment.round()} USD principal paid.',
      playerRelated: true,
    );
    notifyListeners();
  }

  double playerCompanyValue() => math.max(
    5000000,
    math.max(0, player.cashUSD) +
        playerFleet
            .where((ac) => ac.status != AircraftStatus.crashed)
            .fold<double>(
              0,
              (sum, ac) => sum + computeAircraftValue(ac, gameDay),
            ) +
        playerRoutes
            .where((route) => route.isActive && route.dailyProfit > 0)
            .fold<double>(0, (sum, route) => sum + route.dailyProfit * 365 * 2),
  );

  double rebrandCost({String? name, String? color, String? logoEmoji}) {
    final value = playerCompanyValue();
    final nameChanged =
        name != null && name.trim().isNotEmpty && name.trim() != player.name;
    final colorChanged = color != null && color != player.color;
    final logoChanged =
        logoEmoji != null &&
        logoEmoji.trim().isNotEmpty &&
        logoEmoji.trim() != player.logoEmoji;
    final baseCost = nameChanged && colorChanged
        ? math.max(1200000, value * 0.05)
        : nameChanged
        ? math.max(1000000, value * 0.04)
        : colorChanged
        ? math.max(250000, value * 0.015)
        : 0.0;
    final logoCost = logoChanged ? math.max(500000, value * 0.02) : 0.0;
    return (baseCost + logoCost).roundToDouble();
  }

  double rebrandAirline({String? name, String? color, String? logoEmoji}) {
    final cost = rebrandCost(name: name, color: color, logoEmoji: logoEmoji);
    if (cost <= 0) return 0;
    if (player.cashUSD < cost) throw StateError('Not enough cash');
    airlines['player'] = player.copyWith(
      name: name == null || name.trim().isEmpty ? null : name.trim(),
      color: color,
      logoEmoji: logoEmoji == null || logoEmoji.trim().isEmpty
          ? null
          : logoEmoji.trim(),
      cashUSD: player.cashUSD - cost,
    );
    pushNewsItem(
      'AIRLINE: ${airlines['player']!.name} completed a rebrand.',
      playerRelated: true,
    );
    notifyListeners();
    return cost;
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
    pushNewsItem(
      'You acquired ${amount.toStringAsFixed(0)}% of ${target.name} for \$${cost.round()}.',
      playerRelated: true,
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
    pushNewsItem(
      'You sold ${amount.toStringAsFixed(0)}% of ${target.name} for \$${proceeds.round()}.',
      playerRelated: true,
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
    pushNewsItem(
      '${player.name} has acquired ${target.name}.',
      playerRelated: true,
    );
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
    'hasLost': hasLost,
    'themeMode': themeMode.name,
    'globalFuelPrice': globalFuelPrice,
    'airlines': airlines.map((key, value) => MapEntry(key, value.toJson())),
    'aircraft': aircraft.map((key, value) => MapEntry(key, value.toJson())),
    'routes': routes.map((key, value) => MapEntry(key, value.toJson())),
    'airportUpgrades': airportUpgrades.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'airportDailyPax': airportDailyPax,
    'newsTicker': newsTicker.map((item) => item.toJson()).toList(),
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
    hasLost = raw['hasLost'] == true;
    themeMode = _themeModeFromJson(raw['themeMode']);
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
      ..addAll(
        (raw['newsTicker'] as List? ?? const []).indexed.map(
          (entry) => NewsTickerItem.fromJson(entry.$2, entry.$1),
        ),
      );
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

ThemeModeSetting _themeModeFromJson(Object? value) {
  if (value is String) {
    for (final mode in ThemeModeSetting.values) {
      if (mode.name == value) return mode;
    }
  }
  return ThemeModeSetting.dark;
}
