import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/geo.dart';
import '../data/aircraft_types.dart';
import '../data/airports.dart';
import '../engine/ai_preferences.dart';
import '../engine/demand_model.dart';
import '../engine/economics_engine.dart';
import '../engine/finance.dart';
import '../engine/ai_news.dart';
import '../engine/hub_upgrades.dart';
import '../engine/route_optimizer.dart';
import '../engine/valuation.dart';
import '../models/models.dart';

const optimiseAllBaseCostUSD = 2000000.0;
const optimiseAllCostPerRouteUSD = 2500000.0;
const gameDayMs = 86400000;
const _airportEventSampleSize = 220;
const _eventScale = 0.6;
const _maxAiAirlines = 16;
const _aiSpawnIntervalDays = 15;
const _aiCashStressThreshold = 15000000.0;
const _aiCriticalCashThreshold = 5000000.0;
const _aiLossMakingRouteThreshold = -2500.0;
const _aiBuyoutIntervalDays = 90;
const _aiDissolveIntervalDays = 30;
const _aiDissolveThreshold = -50000000.0;
const _aiShareSaleCashThreshold = 8000000.0;
const _aiSharePurchaseIntervalDays = 45;
/// Minimum cash an AI must hold above its expansion reserve before it
/// considers buying minority stakes in rivals.
const _aiSharePurchaseCashFloor = 40000000.0;
/// Maximum combined stake an AI airline will hold in any single rival.
const _aiSharePurchaseMaxStake = 20.0;

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

const _aiNamePrefixes = [
  'Atlas',
  'Nordic',
  'Pacific',
  'Horizon',
  'Stellar',
  'Astra',
  'Pinnacle',
  'Summit',
  'Cardinal',
  'Zenith',
  'Liberty',
  'Frontier',
  'Pioneer',
  'Vanguard',
  'Polar',
  'Tropic',
  'Alpine',
  'Sahara',
  'Orient',
  'Andean',
  'Caspian',
  'Baltic',
  'Adriatic',
  'Iberian',
  'Boreal',
  'Austral',
  'Solar',
  'Nova',
  'Apex',
  'Crown',
  'Omega',
  'Aegean',
  'Amber',
  'Azure',
  'Borealis',
  'Cascade',
  'Equinox',
  'Falcon',
  'Indigo',
  'Jade',
  'Kestrel',
  'Lodestar',
  'Magellan',
  'Nimbus',
  'Orion',
  'Pegasus',
  'Quest',
  'Solaris',
  'Tasman',
  'Venture',
  'Windward',
  'Zephyr',
];

const _aiNameSuffixes = [
  'Air',
  'Airlines',
  'Airways',
  'Aviation',
  'Express',
  'Connect',
  'Jet',
  'Wings',
  'Lines',
  'Global',
  'Link',
  'Sky',
  'Aero',
  'Fly',
];

const _aiSpawnHubs = [
  'JFK',
  'LAX',
  'LHR',
  'CDG',
  'FRA',
  'AMS',
  'NRT',
  'HKG',
  'SIN',
  'DXB',
  'SYD',
  'GRU',
  'MEX',
  'JNB',
  'BOM',
  'PEK',
  'ICN',
  'BKK',
  'KUL',
  'IST',
  'ATL',
  'ORD',
  'DFW',
  'MIA',
  'SFO',
  'YYZ',
  'MAD',
  'BCN',
  'FCO',
  'MUC',
  'ZRH',
  'VIE',
  'CPH',
  'OSL',
  'ARN',
  'WAW',
  'LIS',
  'ATH',
  'CAI',
  'NBO',
  'CPT',
  'DEL',
  'BLR',
  'MNL',
  'CGK',
  'AKL',
  'SCL',
  'BOG',
  'LIM',
  'YVR',
];

const _aiSpawnLogos = [
  '✈️',
  '🛫',
  '🌍',
  '🌎',
  '🌏',
  '🌐',
  '⭐',
  '🌟',
  '🚀',
  '🌙',
  '🌊',
  '🏔️',
];

const _aiSpawnColors = [
  '#ef4444',
  '#0ea5e9',
  '#22c55e',
  '#818cf8',
  '#f59e0b',
  '#e879f9',
  '#a3e635',
  '#22d3ee',
  '#a855f7',
  '#facc15',
  '#c084fc',
  '#f43f5e',
  '#14b8a6',
  '#fb7185',
  '#38bdf8',
  '#84cc16',
  '#f97316',
  '#6366f1',
];

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
  GameController({bool autoStart = true}) {
    if (autoStart) startNewGame();
  }

  static const saveVersion = 1;
  static const exportKind = 'mighty-airline-empire-save';
  static const exportVersion = 1;
  GameSettings settings = const GameSettings();
  int gameDay = 0;
  int gameTimeMs = 0;
  int speed = 60;
  bool isPaused = false;
  bool hasWon = false;
  bool hasLost = false;
  bool hasStarted = false;
  ThemeModeSetting themeMode = ThemeModeSetting.dark;
  bool showAiOnMap = true;
  double globalFuelPrice = fuelPriceUsdPerLiter;
  final airlines = <String, Airline>{};
  final aircraft = <String, Aircraft>{};
  final routes = <String, RoutePlan>{};
  final airportUpgrades = <String, AirportUpgrade>{};
  final airportDailyPax = <String, double>{};
  final newsTicker = <NewsTickerItem>[];
  final newsArticles = <String, NewsArticle>{};
  final newspaperQueue = <String>[];
  final mapAnimationTick = ValueNotifier<int>(0);
  /// Increments when the route set changes structurally (added/removed/active
  /// toggled, aircraft assignment changed, airline color changed). Used by the
  /// map to skip rebuilding polylines/markers when nothing visually changed.
  final routesStructureVersion = ValueNotifier<int>(0);
  /// Increments when airport-visual state changes (hubs, closures, theme).
  final airportStateVersion = ValueNotifier<int>(0);
  String? latestArticleId;
  int _nextAircraft = 1;
  int _nextRoute = 1;
  int _nextLoan = 1;
  int _nextTicker = 1;
  int _nextAirline = 1;
  int _animFrameSkip = 0;
  int _lastAutoSaveRealMs = 0;

  static const _aiExpansionReserveUSD = 5000000.0;

  @override
  void dispose() {
    mapAnimationTick.dispose();
    routesStructureVersion.dispose();
    airportStateVersion.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    routesStructureVersion.value += 1;
    airportStateVersion.value += 1;
    super.notifyListeners();
  }

  void pushNewsItem(
    String text, {
    String severity = 'normal',
    String? articleId,
    bool playerRelated = false,
    NewsArticle? article,
  }) {
    var linkedArticleId = articleId;
    if (article != null) {
      linkedArticleId = article.id;
      _publishNewsArticle(article);
    } else if (playerRelated && linkedArticleId == null) {
      linkedArticleId = 'ticker-article-$gameDay-${newsArticles.length + 1}';
      _publishNewsArticle(
        NewsArticle(
          id: linkedArticleId,
          headline: player.name,
          subheadline: text,
          paragraphs: [text],
          severity: severity == 'breaking' ? 'crash' : 'incident',
          gameDay: gameDay,
          suppressAutoOpen: true,
        ),
      );
    }
    newsTicker.insert(
      0,
      NewsTickerItem(
        id: 'ticker-$gameDay-${_nextTicker++}',
        text: text,
        severity: severity,
        articleId: linkedArticleId,
        playerRelated: playerRelated,
      ),
    );
    if (newsTicker.length > 20) {
      newsTicker.removeRange(20, newsTicker.length);
    }
  }

  void _publishNewsArticle(NewsArticle article) {
    newsArticles[article.id] = article;
    latestArticleId = article.id;
    newspaperQueue
      ..remove(article.id)
      ..add(article.id);
    if (newspaperQueue.length > 8) {
      newspaperQueue.removeRange(0, newspaperQueue.length - 8);
    }
  }

  List<NewsArticle> get queuedNewspaperArticles => newspaperQueue
      .map((id) => newsArticles[id])
      .whereType<NewsArticle>()
      .toList(growable: false);

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

  double stakeInAirline(String targetAirlineId, String ownerAirlineId) =>
      airlines[targetAirlineId]?.shareholders[ownerAirlineId] ?? 0;

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

  double sharePurchasePrice(
    String airlineId,
    double percent, {
    String source = 'market',
  }) {
    final target = airlines[airlineId];
    if (target == null || target.isPlayer) return 0;
    return calculateSharePrice(
      percentToBuy: percent,
      currentPlayerPercent: playerStakeIn(airlineId),
      airline: target,
      aircraft: aircraft,
      routes: routes,
      currentGameDay: gameDay,
      fromSecondaryMarket: source != 'market',
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
    if (!hasStarted) return;
    if (isPaused || speed <= 0) return;
    final delta = (realDelta.inMilliseconds * speed).round();
    if (delta <= 0) return;
    gameTimeMs += delta;
    final targetDay = gameTimeMs ~/ gameDayMs;
    var daysProcessed = 0;
    while (gameDay < targetDay && daysProcessed < 14) {
      runDailyTick();
      daysProcessed += 1;
    }
    _animFrameSkip = (_animFrameSkip + 1) % 2;
    if (_animFrameSkip == 0) {
      _advanceAircraftPositions(delta * 2);
      mapAnimationTick.value += 1;
    }
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

  void setShowAiOnMap(bool show) {
    showAiOnMap = show;
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

  /// Resets to a clean pre-game state so the game map doesn't show behind
  /// the new-game dialog when restarting. Call before showing the modal.
  void resetToPreStart() {
    hasStarted = false;
    airlines.clear();
    aircraft.clear();
    routes.clear();
    airportUpgrades.clear();
    airportDailyPax.clear();
    newsTicker.clear();
    newsArticles.clear();
    newspaperQueue.clear();
    latestArticleId = null;
    notifyListeners();
  }

  void startNewGame([GameSettings? nextSettings]) {
    hasStarted = true;
    settings = nextSettings ?? settings;
    gameDay = 0;
    gameTimeMs = 0;
    speed = 60;
    isPaused = false;
    hasWon = false;
    hasLost = false;
    showAiOnMap = true;
    globalFuelPrice = fuelPriceUsdPerLiter;
    airlines.clear();
    aircraft.clear();
    routes.clear();
    airportUpgrades.clear();
    airportDailyPax.clear();
    newsTicker.clear();
    newsArticles.clear();
    newspaperQueue.clear();
    latestArticleId = null;
    _nextAircraft = 1;
    _nextRoute = 1;
    _nextLoan = 1;
    _nextTicker = 1;
    _nextAirline = 1;
    _lastAutoSaveRealMs = 0;
    final startingHub = airportsByIata.containsKey(settings.startingHubIata)
        ? settings.startingHubIata
        : 'LHR';
    airlines['player'] = Airline(
      id: 'player',
      name: settings.playerAirlineName,
      iataPrefix: 'PLY',
      isPlayer: true,
      color: settings.playerAirlineColor,
      logoEmoji: settings.playerAirlineEmoji,
      cashUSD: settings.startingCash,
      hubIatas: [startingHub],
      foundedGameDay: 0,
      reputationScore: 55,
    );
    _markAirportHub(startingHub);
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
    _seedAICrossShareholdings();
  }

  void _seedAICrossShareholdings() {
    final skyPacific = airlines['ai-8'];
    final eagleAir = airlines['ai-1'];
    if (skyPacific != null && eagleAir != null) {
      airlines[skyPacific.id] = skyPacific.copyWith(
        shareholders: {...skyPacific.shareholders, eagleAir.id: 8},
      );
    }
    final gulfConnect = airlines['ai-5'];
    final pacificCoast = airlines['ai-2'];
    if (gulfConnect != null && pacificCoast != null) {
      airlines[gulfConnect.id] = gulfConnect.copyWith(
        shareholders: {...gulfConnect.shareholders, pacificCoast.id: 5},
      );
    }
  }

  int _defaultAiFrequency(AirlinePersonality personality) =>
      switch (personality) {
        AirlinePersonality.aggressive => 10,
        AirlinePersonality.budget => 10,
        AirlinePersonality.premium => 7,
        AirlinePersonality.conservative => 5,
        AirlinePersonality.balanced => 7,
      };

  /// Hard cap on the number of routes an AI airline may operate. Prevents
  /// unlimited expansion and keeps AI fleet sizes realistic.
  int _aiMaxRoutes(AirlinePersonality personality) =>
      switch (personality) {
        AirlinePersonality.aggressive => 16,
        AirlinePersonality.balanced => 12,
        AirlinePersonality.budget => 10,
        AirlinePersonality.premium => 9,
        AirlinePersonality.conservative => 7,
      };

  /// Daily per-aircraft overhead for AI airlines (staff, admin, ground
  /// handling, and facilities costs not captured in per-flight economics).
  double _aiOverheadPerAircraftPerDay(AirlinePersonality personality) =>
      switch (personality) {
        AirlinePersonality.aggressive => 2200,   // large ops, higher labour
        AirlinePersonality.balanced => 1800,
        AirlinePersonality.budget => 1100,        // lean staffing model
        AirlinePersonality.premium => 2800,       // premium service standards
        AirlinePersonality.conservative => 1500,
      };

  double _aiPriceMultiplier(AirlinePersonality personality) =>
      switch (personality) {
        AirlinePersonality.aggressive => 0.9,
        AirlinePersonality.budget => 0.75,
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
      status: routeId == null ? AircraftStatus.idle : AircraftStatus.flying,
      currentLat: airportByIata(owner.hubIatas.firstOrNull ?? 'LHR')?.lat ?? 0,
      currentLon: airportByIata(owner.hubIatas.firstOrNull ?? 'LHR')?.lon ?? 0,
    );
    // Apply fleet maintenance policy to newly purchased aircraft
    final policy = owner.maintenancePolicy;
    aircraft[id] = policy.enabled
        ? ac.copyWith(
            autoMaintenanceEnabled: true,
            autoMaintenanceThreshold: policy.threshold,
            autoMaintenanceTier: policy.tier,
          )
        : ac;
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
      resumeRouteAfterMaintenance: false,
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
    final requestedType = aircraftTypesById[aircraftTypeId];
    final assignedAircraft = aircraftId == null ? null : aircraft[aircraftId];
    final type = assignedAircraft == null
        ? requestedType
        : aircraftTypesById[assignedAircraft.typeId];
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
    final willHaveAircraft = aircraftId != null || buyNewAircraft;
    if (willHaveAircraft) {
      if (distance > type.rangeKm)
        throw StateError('Aircraft range too short for route');
      if (!canAirportHandleAircraft(origin, type) ||
          !canAirportHandleAircraft(destination, type))
        throw StateError('Airport runway too short for aircraft');
      if (aircraftId == null && player.cashUSD < type.purchasePrice) {
        throw StateError('Insufficient funds to purchase aircraft');
      }
    }
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
      isActive: willHaveAircraft,
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
        status: AircraftStatus.flying,
      );
    }
    notifyListeners();
    return routes[routeId]!;
  }

  NewsArticle? get latestArticle =>
      latestArticleId == null ? null : newsArticles[latestArticleId];

  NewsArticle? get nextAutoOpenArticle {
    for (final article in queuedNewspaperArticles) {
      if (!article.suppressAutoOpen) return article;
    }
    return null;
  }

  void popNewspaper([String? articleId]) {
    if (articleId == null) {
      if (newspaperQueue.isNotEmpty) newspaperQueue.removeAt(0);
    } else {
      newspaperQueue.remove(articleId);
    }
    notifyListeners();
  }

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
      crashRisk: aircraftCrashRisk(
        ac.copyWith(condition: nextCondition),
        gameDay,
      ),
      isGrounded: ground,
      groundedReason: reason,
      status: ground ? AircraftStatus.idle : ac.status,
    );
    final maintenanceCost = maintenanceCostForIncident(aircraftId);
    final shouldAutoMaintain =
        airline.isPlayer &&
        ground &&
        airline.maintenancePolicy.autoMaintainIssues;
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
      suppressAutoOpen: shouldAutoMaintain,
    );
    _publishNewsArticle(article);
    pushNewsItem(
      '${article.headline}: ${article.subheadline}',
      severity: ground ? 'breaking' : 'fleet',
      articleId: article.id,
      playerRelated: airline.isPlayer,
    );
    if (shouldAutoMaintain) {
      _startMaintenanceInternal(aircraftId, airline.maintenancePolicy.tier);
    }
    notifyListeners();
    return article;
  }

  int maintenanceCostForIncident(String aircraftId) =>
      maintenanceCost(aircraftId, MaintenanceTier.standard);

  // Typed aircraft events — (label, probability, conditionHit, reputationHit, ground)
  static const _fleetEvents = <(String, double, double, double, bool)>[
    ('bird strike', 0.0018, 8, 2, false),
    ('engine fault', 0.0012, 14, 5, true),
    ('hydraulic issue', 0.0010, 10, 3, true),
    ('tyre blowout', 0.0016, 6, 2, false),
    ('fuselage crack', 0.0007, 18, 8, true),
    ('avionics fault', 0.0009, 8, 4, true),
    ('fuel leak', 0.0008, 12, 6, true),
    ('pressurisation fault', 0.0006, 10, 5, true),
    ('landing gear fault', 0.0011, 12, 5, true),
    ('fire warning', 0.0005, 16, 10, true),
  ];

  void _maybeRunRandomFleetEvent() {
    final rng = math.Random(gameDay * 37199 + 1);
    // Run for all airlines — AI + player
    for (final airlineId in airlines.keys.toList()) {
      final airline = airlines[airlineId];
      if (airline == null || airline.isInsolvent) continue;
      final fleet = airline.isPlayer
          ? playerFleet
          : fleetForAirline(airlineId);
      final candidates = fleet
          .where(
            (ac) =>
                ac.status != AircraftStatus.maintenance &&
                ac.status != AircraftStatus.crashed &&
                !ac.isGrounded,
          )
          .toList();
      if (candidates.isEmpty) continue;
      for (final ac in candidates) {
        for (final evt in _fleetEvents) {
          final (label, prob, condHit, repHit, grounds) = evt;
          if (rng.nextDouble() > prob * _eventScale) continue;
          final newCondition = (ac.condition - condHit).clamp(0, 100).toDouble();
          final newReputation =
              (airline.reputationScore - repHit).clamp(0, 100).toDouble();
          airlines[airlineId] = airline.copyWith(
            reputationScore: newReputation,
          );
          if (grounds || newCondition < 30) {
            if (airline.isPlayer) {
              triggerAircraftIncident(ac.id, ground: grounds);
            } else {
              aircraft[ac.id] = ac.copyWith(
                condition: newCondition,
                isGrounded: grounds,
                groundedReason: label,
              );
            }
          } else {
            aircraft[ac.id] = ac.copyWith(condition: newCondition);
          }
          if (airline.isPlayer) {
            pushNewsItem(
              '${ac.name} suffered a $label.',
              severity: 'fleet',
              playerRelated: true,
            );
          } else {
            final route = ac.assignedRouteId == null
                ? null
                : routes[ac.assignedRouteId!];
            final routeLabel = route == null
                ? 'unassigned services'
                : '${route.originIata}-${route.destinationIata}';
            pushNewsItem(
              '${airline.name}: $label on ${ac.name}.',
              severity: 'fleet',
              article: generateFleetEventArticle(
                id: 'fleet-${ac.id}-$gameDay',
                airlineName: airline.name,
                aircraftName: ac.name,
                faultLabel: label,
                routeLabel: routeLabel,
                grounds: grounds,
                gameDay: gameDay,
                seed: ac.id.hashCode ^ gameDay,
              ),
            );
          }
          break; // one event per aircraft per day
        }
      }
    }
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
      maintenanceHoursOwed: ac.maintenanceHoursOwed,
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
    var resumeRouteAfterMaintenance = false;
    if (ac.assignedRouteId != null) {
      final route = routes[ac.assignedRouteId!];
      if (route != null) {
        resumeRouteAfterMaintenance = route.isActive;
        routes[route.id] = route.copyWith(isActive: false);
      }
    }
    aircraft[aircraftId] = ac.copyWith(
      status: AircraftStatus.maintenance,
      isGrounded: true,
      lastMaintenanceGameDay: gameDay,
      activeMaintTier: tier,
      knownFaultRiskMod: 1,
      resumeRouteAfterMaintenance: resumeRouteAfterMaintenance,
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
    final assignedRoute = ac.assignedRouteId == null
        ? null
        : routes[ac.assignedRouteId!];
    final shouldResumeRoute =
        ac.resumeRouteAfterMaintenance &&
        assignedRoute != null &&
        condition >= 20;
    if (shouldResumeRoute) {
      routes[assignedRoute.id] = assignedRoute.copyWith(isActive: true);
    }
    aircraft[aircraftId] = ac.copyWith(
      status: shouldResumeRoute ? AircraftStatus.flying : AircraftStatus.idle,
      isGrounded: condition < 20,
      groundedReason: condition < 20
          ? 'Critical condition - requires maintenance'
          : null,
      condition: condition,
      maintenanceHoursOwed: 0,
      crashRisk: aircraftCrashRisk(ac.copyWith(condition: condition), gameDay),
      knownFaultRiskMod: 1,
      lastMaintenanceGameDay: gameDay,
      resumeRouteAfterMaintenance: false,
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
    for (final aircraftId in airline.fleetIds.toList()) {
      final ac = aircraft[aircraftId];
      if (ac == null ||
          ac.status == AircraftStatus.maintenance ||
          ac.status == AircraftStatus.crashed ||
          !ac.autoMaintenanceEnabled) {
        continue;
      }
      final tier = ac.autoMaintenanceTier;
      final duration = maintenanceTiers[tier]?.durationDays ?? 2;
      final cooldownElapsed =
          ac.lastMaintenanceGameDay == 0 ||
          gameDay > ac.lastMaintenanceGameDay + duration;
      final belowThreshold = ac.condition <= ac.autoMaintenanceThreshold;
      final groundedNeedsFix =
          ac.isGrounded && ac.status != AircraftStatus.maintenance;

      // Nothing to do — healthy and not grounded for any reason.
      if (!belowThreshold && !groundedNeedsFix) continue;

      // Flying plane below threshold: ground it to pause flights and revenue.
      // Maintenance will formally start next tick once it's no longer flying.
      if (belowThreshold && !ac.isGrounded && ac.status == AircraftStatus.flying) {
        aircraft[aircraftId] = ac.copyWith(
          isGrounded: true,
          groundedReason: 'awaiting maintenance',
        );
        continue;
      }

      // Grounded planes (incident or awaiting maintenance) bypass the cooldown —
      // they're already on the ground, no reason to delay further.
      if (!groundedNeedsFix && !cooldownElapsed) continue;

      if (_startMaintenanceInternal(aircraftId, tier)) {
        final reason = groundedNeedsFix
            ? 'grounded (${ac.groundedReason ?? 'incident'})'
            : 'condition ${ac.condition.toStringAsFixed(0)}%';
        pushNewsItem(
          'Auto-maintenance triggered for ${ac.name} ($reason).',
          playerRelated: true,
        );
      }
    }
  }

  void _applyAIMaintenancePolicy(String airlineId) {
    final airline = airlines[airlineId];
    if (airline == null || airline.isPlayer || airline.isInsolvent) return;
    final threshold = switch (airline.personality) {
      AirlinePersonality.premium => 65.0,
      AirlinePersonality.conservative => 52.0,
      AirlinePersonality.balanced => 40.0,
      AirlinePersonality.aggressive => 28.0,
      AirlinePersonality.budget => 18.0,
    };
    final tier = switch (airline.personality) {
      AirlinePersonality.premium => MaintenanceTier.full,
      AirlinePersonality.conservative => MaintenanceTier.standard,
      AirlinePersonality.balanced => MaintenanceTier.standard,
      AirlinePersonality.aggressive => MaintenanceTier.light,
      AirlinePersonality.budget => MaintenanceTier.light,
    };
    for (final aircraftId in airline.fleetIds.toList()) {
      final ac = aircraft[aircraftId];
      if (ac == null ||
          ac.status == AircraftStatus.maintenance ||
          ac.status == AircraftStatus.crashed) {
        continue;
      }
      final needsMaint = ac.condition <= threshold || ac.isGrounded;
      if (!needsMaint) continue;
      _startMaintenanceInternal(aircraftId, tier);
    }
  }

  bool launchPRCampaign({required double cost, required double reputationGain}) {
    if (player.cashUSD < cost) return false;
    airlines['player'] = player.copyWith(
      cashUSD: player.cashUSD - cost,
      reputationScore: (player.reputationScore + reputationGain).clamp(0, 100).toDouble(),
    );
    notifyListeners();
    return true;
  }

  void updateMaintenancePolicy(MaintenancePolicy policy) {
    final next = policy.copyWith(
      threshold: policy.threshold.clamp(20, 80).toDouble(),
    );
    airlines['player'] = player.copyWith(maintenancePolicy: next);
    for (final aircraftId in player.fleetIds) {
      final ac = aircraft[aircraftId];
      if (ac == null || ac.excludedFromPolicy) continue;
      // If this plane is now below the new threshold (wasn't before), reset the
      // cooldown so the next policy check isn't blocked by a recent maintenance.
      final nowBelowThreshold = next.enabled && ac.condition <= next.threshold;
      aircraft[aircraftId] = ac.copyWith(
        autoMaintenanceEnabled: next.enabled,
        autoMaintenanceThreshold: next.threshold,
        autoMaintenanceTier: next.tier,
        lastMaintenanceGameDay: nowBelowThreshold ? 0 : null,
      );
    }
    // Immediately apply the updated policy so planes already below the new
    // threshold get grounded/scheduled without waiting for the next tick.
    _applyAutoMaintenancePolicy('player');
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

  void setAutoMaintenance(
    String aircraftId,
    bool enabled,
    double threshold,
    MaintenanceTier tier,
  ) {
    final ac = aircraft[aircraftId];
    if (ac == null || ac.airlineId != 'player') return;
    aircraft[aircraftId] = ac.copyWith(
      autoMaintenanceEnabled: enabled,
      autoMaintenanceThreshold: threshold.clamp(20, 80).toDouble(),
      autoMaintenanceTier: tier,
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
    // For AI airlines, cap flights/week to the personality default so the
    // optimizer cannot push frequencies beyond what is realistic for each type.
    final airline = airlines[airlineId];
    final maxFlights = (airline == null || airline.isPlayer)
        ? result.flightsPerWeek
        : _defaultAiFrequency(airline.personality);
    routes[routeId] = input.route.copyWith(
      flightsPerWeek: result.flightsPerWeek.clamp(1, maxFlights),
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
    final crashEvents =
        <({String aircraftId, String routeId, String airlineId})>[];

    for (final airlineId in airlines.keys.toList()) {
      final airline = airlines[airlineId];
      if (airline == null || airline.isInsolvent) continue;
      var totalRevenue = 0.0;
      var totalCost = 0.0;
      var totalPassengers = 0;

      _completeDueMaintenance(airlineId);
      _applyAutoMaintenancePolicy(airlineId);
      _applyAIMaintenancePolicy(airlineId);

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
        if (_shouldAircraftCrash(ac, result.route)) {
          crashEvents.add((
            aircraftId: ac.id,
            routeId: routeId,
            airlineId: airlineId,
          ));
        }
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
      // AI operating overhead: staff, administration, ground handling and
      // facility costs that the simplified per-flight model omits.
      if (!airline.isPlayer) {
        final aiFleetSize = fleetForAirline(airlineId).length;
        totalCost +=
            aiFleetSize * _aiOverheadPerAircraftPerDay(airline.personality);
      }
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
      final penaltyLeft = (airline.crashPenaltyDaysLeft - 1).clamp(0, 9999);
      const reputationRecovery = 0.1;
      // Drain reputation for operating poorly-maintained aircraft (condition < 40)
      final fleet = airline.isPlayer
          ? playerFleet
          : fleetForAirline(airlineId);
      final conditionDrain = fleet
          .where((ac) =>
              ac.status == AircraftStatus.flying && ac.condition < 40)
          .fold<double>(0.0, (sum, ac) {
        return sum + ((40 - ac.condition) / 40) * 0.15;
      });
      final newReputation =
          (airline.reputationScore + reputationRecovery - conditionDrain)
          .clamp(0, 100)
          .toDouble();
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
        crashPenaltyDaysLeft: penaltyLeft,
        reputationScore: newReputation,
      );
    }

    for (final crash in crashEvents) {
      _triggerAircraftCrash(crash.aircraftId, crash.routeId, crash.airlineId);
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
    _pruneDistressedAIRoutes();
    _maybeSellAICrossHoldings();
    _maybeRunAIMarketConsolidation();
    _maybeSpawnNewAI();
    _maybeExpandAI();
    _adjustAIPrices();
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
    _scheduleAutoSave();
    return playerSnapshot;
  }

  // ─── Auto-save ────────────────────────────────────────────────────────────

  static const _autoSaveKey = 'mighty_airline_autosave';
  static const _autoSaveIntervalRealMs = 20000;

  void _scheduleAutoSave() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastAutoSaveRealMs < _autoSaveIntervalRealMs) return;
    _lastAutoSaveRealMs = nowMs;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_autoSaveKey, exportJson());
    });
  }

  static Future<String?> loadAutoSave() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_autoSaveKey);
  }

  static Future<void> clearAutoSave() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_autoSaveKey);
  }

  bool _isAirportClosed(Airport airport) {
    final closedUntil = airport.closedUntilGameDay;
    return closedUntil != null && closedUntil >= gameDay;
  }

  bool _shouldAircraftCrash(Aircraft ac, RoutePlan route) {
    if (ac.status == AircraftStatus.crashed ||
        ac.status == AircraftStatus.maintenance ||
        ac.crashRisk <= 0.001) {
      return false;
    }
    final flightsPerDay = route.flightsPerWeek / 7;
    final probability =
        (ac.crashRisk * ac.knownFaultRiskMod * flightsPerDay * 0.0008)
            .clamp(0.0, 1.0)
            .toDouble();
    if (probability <= 0) return false;
    return _stableUnitInterval('$gameDay:${ac.id}:${route.id}:crash') <
        probability;
  }

  double _stableUnitInterval(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return (hash & 0xffffffff) / 0xffffffff;
  }

  /// Returns a deterministic but varied crash narrative based on [seed] ∈ [0,1).
  ({String headline, String subheadline, List<String> paragraphs})
  _crashScenario({
    required String airlineName,
    required String model,
    required String registration,
    required String routeLabel,
    required double seed,
  }) {
    final idx = (seed * 15).floor().clamp(0, 14);
    switch (idx) {
      case 0:
        return (
          headline: 'Breaking: $airlineName jet lost after dual-engine flameout',
          subheadline:
              'Crew declared emergency over $routeLabel corridor before contact was lost',
          paragraphs: [
            'A $model operated by $airlineName has been lost after both engines flamed out during the cruise phase of a $routeLabel service. Air traffic control recorded the crew declaring a full emergency at flight level 350, citing total loss of thrust on both powerplants. The aircraft descended below radar coverage and did not arrive at its destination.',
            'Preliminary data from the quick-access recorder indicates a simultaneous surge event across both engines, consistent with fuel contamination or sustained ingestion of volcanic ash at altitude. Investigators are cross-referencing the route with SIGMET reports filed in the region for the preceding 72 hours.',
            '$airlineName has grounded the affected $model fleet pending emergency borescope inspections of high-pressure turbine stages and fuel system integrity checks. The carrier has dispatched a crisis response team and is cooperating fully with the national accident investigation authority.',
          ],
        );
      case 1:
        return (
          headline: 'Breaking: $airlineName $model strikes high ground near destination',
          subheadline:
              'Aircraft operating normally before CFIT event on $routeLabel approach',
          paragraphs: [
            'A $model registered as $registration and operated by $airlineName has been destroyed after impacting elevated terrain during the descent phase of a $routeLabel flight. The aircraft was under radar contact and had been cleared for the approach when it deviated below the minimum safe altitude. No distress call was received before contact was lost.',
            'Accident investigators have recovered both the flight data recorder and cockpit voice recorder from the wreckage site. Early analysis suggests the crew may have been operating under an incorrect altimeter setting and did not respond to terrain proximity warnings. The investigation will examine crew fatigue records, approach briefing documentation, and the serviceability history of the ground-proximity warning system.',
            '$airlineName has immediately suspended all operations on the $routeLabel route and has placed its entire fleet on a mandatory terrain-awareness systems audit. The airline\'s CEO issued a public statement expressing profound condolences and pledging full transparency with investigators.',
          ],
        );
      case 2:
        return (
          headline: 'Breaking: Structural failure destroys $airlineName aircraft in cruise',
          subheadline:
              '$routeLabel flight lost after catastrophic airframe breakup at altitude',
          paragraphs: [
            'A $model operated by $airlineName on a $routeLabel service has been lost following what investigators believe to have been a catastrophic in-flight structural failure. Radar tracks show the aircraft making a series of rapid altitude excursions before disappearing from screens. Debris has been located across a wide geographic area, consistent with a high-altitude break-up event.',
            'Structural engineers from the manufacturer have been summoned to assist with the investigation. Sources within the inquiry indicate that the failure originated in the aft pressure bulkhead, an area subject to high cyclical stress loads. The airframe had accumulated significant pressurisation cycles and had undergone fuselage repair work eighteen months prior.',
            'Airworthiness authorities have issued an emergency airworthiness directive requiring all operators of the $model type to conduct detailed non-destructive testing of the aft fuselage section before any further revenue flights. $airlineName has suspended all flying pending compliance.',
          ],
        );
      case 3:
        return (
          headline: 'Breaking: $airlineName flight lost after cargo fire on $routeLabel route',
          subheadline:
              'Crew reported uncontrollable smoke in cabin before aircraft went silent',
          paragraphs: [
            'An $airlineName $model has been destroyed following a rapidly-spreading fire that originated in the forward cargo hold during a $routeLabel service. The crew first reported smoke in the cabin and declared an emergency, requesting an immediate diversion. A second transmission indicated the fire suppression system had been discharged but smoke was intensifying. The aircraft was subsequently lost from radar.',
            'Investigators are examining the cargo manifest in detail. Preliminary findings suggest the fire may have been initiated by improperly declared lithium battery shipments. The heat generated by the failure overwhelmed the aircraft\'s fixed cargo fire suppression capacity within minutes, propagating into flight-critical wiring looms.',
            'The incident has prompted an immediate regulatory review of dangerous goods screening procedures at both ends of the $routeLabel corridor. $airlineName has suspended all cargo carriage pending an independent audit, and has cooperated with customs authorities who are examining the documentation trail for the consignment in question.',
          ],
        );
      case 4:
        return (
          headline: 'Breaking: $airlineName $model downed by massive bird strike on departure',
          subheadline:
              'Multiple engine ingestions cause total thrust loss on $routeLabel takeoff roll',
          paragraphs: [
            'A $model operated by $airlineName has been lost after a catastrophic bird strike during the takeoff roll on a $routeLabel service. The crew rejected the takeoff at high speed after both engines ingested large birds, but was unable to stop the aircraft within the remaining runway. The aircraft overran the runway end and struck terrain, resulting in a post-impact fire.',
            'Wildlife hazard reports from the aerodrome cite a long-established roosting colony in the approach path, with multiple minor bird-strike incidents recorded in the preceding three months. Airport operations had been aware of the hazard but had not escalated to a flight-suspension protocol. The inquiry will examine the adequacy of the aerodrome\'s wildlife management programme.',
            '$airlineName has called for a formal audit of bird-strike reporting compliance at all stations it serves. The carrier has also questioned why earlier incidents on the same runway were not communicated to flight crews in their pre-departure briefings.',
          ],
        );
      case 5:
        return (
          headline: 'Breaking: $airlineName $model lost in severe windshear encounter',
          subheadline:
              'Rapid airspeed fluctuation on $routeLabel final approach preceded loss of control',
          paragraphs: [
            'An $airlineName $model has been destroyed after encountering severe windshear at low altitude during an instrument approach on a $routeLabel service. The crew received a windshear alert at approximately 600 feet above ground level and executed a go-around, but the aircraft suffered a catastrophic loss of lift during the recovery manoeuvre and impacted terrain short of the airfield perimeter.',
            'Meteorological data recovered from the aerodrome weather station shows a microburst event with a peak outflow velocity exceeding 50 knots at the time of the accident. A preceding aircraft had reported moderate windshear on the same approach, but the warning was not flagged as severe by the terminal weather advisory system.',
            'The inquiry will scrutinise the decision to continue the approach in prevailing meteorological conditions, the adequacy of pilot training on microburst recovery, and the latency of low-level windshear alert system data relay to the cockpit. $airlineName has suspended $routeLabel operations pending a safety assessment.',
          ],
        );
      case 6:
        return (
          headline: 'Breaking: Ice ingestion forces $airlineName $model down over $routeLabel corridor',
          subheadline:
              'Crew lost control after both engines surged following ice crystal accumulation',
          paragraphs: [
            'A $model operated by $airlineName has been lost after the crew reported a dual-engine rollback during a $routeLabel sector. The aircraft had been operating in a region of convective cloud associated with an inter-tropical convergence zone when the engines began surging and then lost power. The crew was unable to restart either powerplant before impact.',
            'Ice crystal icing — a phenomenon in which super-cooled water droplets accrete inside engine cores at high altitude — has been identified as the probable initiating cause. The condition is not detected by standard airborne weather radar and can develop rapidly in high-altitude tropical convection. The engines on the $model type were known to have a susceptibility to the phenomenon.',
            'Airworthiness regulators have issued a notice to airmen requiring operators of the $model to avoid identified high-altitude convective cells by a wider margin and to monitor engine anti-ice performance more closely in tropical cruise environments. An airworthiness directive mandating engine core modification is expected within 90 days.',
          ],
        );
      case 7:
        return (
          headline: 'Breaking: $airlineName $model crashes after hydraulic loss on $routeLabel service',
          subheadline:
              'Total hydraulic failure left crew unable to control aircraft on approach',
          paragraphs: [
            'A $model operated by $airlineName has been destroyed following a catastrophic loss of hydraulic pressure that rendered the aircraft\'s primary flight control surfaces inoperative during a $routeLabel approach. The crew declared an emergency and attempted to manoeuvre using asymmetric engine thrust, a technique practised in simulators but rarely executed in practice. The attempt was unsuccessful.',
            'Engineering inspectors have identified a fractured hydraulic line in the aft equipment bay, consistent with chafing against an incorrectly routed electrical conduit. A redundant hydraulic circuit that should have maintained partial control authority was found to have been depressurised due to a faulty isolation valve that had been flagged in the aircraft\'s deferred defect log seven weeks prior.',
            'The accident has raised serious questions about the management of open deferred defects within $airlineName\'s maintenance organisation. Regulators have ordered an emergency audit of the carrier\'s deferred defect procedures across its entire fleet and have placed a senior airworthiness inspector on-site at the airline\'s main maintenance base.',
          ],
        );
      case 8:
        return (
          headline: 'Breaking: $airlineName $model breaks apart in extreme turbulence',
          subheadline:
              'Aircraft encountered severe mountain wave conditions on the $routeLabel sector',
          paragraphs: [
            'An $airlineName $model has been lost after encountering extreme clear-air turbulence associated with a mountain wave system during cruise on a $routeLabel service. Radar data shows the aircraft performing a rapid and uncontrolled pitch excursion before the fuselage separated into multiple sections. The event lasted fewer than twelve seconds from onset to structural failure.',
            'The turbulence intensity experienced by the aircraft is estimated to have been in excess of 4g peak — well beyond the certified design limit load of the airframe. PIREP data from a military aircraft that transited the same airway two hours earlier described moderate chop, giving no indication of the severity of the wave event that had developed by the time of the accident.',
            '$airlineName has cooperated with meteorological agencies to reconstruct the atmospheric conditions at the time of the accident. The inquiry will examine whether route planning tools adequately identify mountain wave hazard zones, and whether real-time turbulence reporting systems provided sufficient warning to redirect the flight.',
          ],
        );
      case 9:
        return (
          headline: 'Breaking: Fuel starvation forces $airlineName $model down on $routeLabel route',
          subheadline:
              'Both engines flame out short of destination after crew loses track of fuel state',
          paragraphs: [
            'A $model operated by $airlineName has been lost after both engines flamed out due to fuel exhaustion during a $routeLabel service. The crew had been managing a series of diversion requests prompted by destination weather and airspace restrictions, and failed to correctly recalculate the fuel requirement for each successive amendment to the flight plan. The aircraft ran dry at low altitude with no suitable aerodrome within gliding range.',
            'Flight data recorder information shows the crew received low-fuel warnings 47 minutes before impact but elected to continue to the planned destination rather than divert immediately. Radio communications in the final phase of the flight indicate crew resource management broke down, with the captain dismissing the first officer\'s repeated requests to seek an emergency landing.',
            'The accident represents the most serious fuel mismanagement event on record for a commercial turbine aircraft in recent years. Investigators are examining training standards for fuel emergency procedures, workload management in high-congestion airspace, and whether the carrier\'s dispatch authority provided adequate fuel planning support to the crew during the multiple reroutes.',
          ],
        );
      case 10:
        return (
          headline: 'Breaking: $airlineName $model crashes after icing stall on departure',
          subheadline:
              'Undetected ice contamination on wings caused loss of control on $routeLabel takeoff',
          paragraphs: [
            'A $model operated by $airlineName has been lost shortly after departure on a $routeLabel service after wing ice contamination caused a stall at low altitude. The aircraft had been deiced on stand, but a significant holdover time was exceeded before the crew began the takeoff roll. Freezing drizzle had continued to fall during the extended taxi, depositing a thin but aerodynamically critical layer of ice on the wing leading edges.',
            'Witnesses reported the aircraft climbing steeply before the nose pitched sharply down and the aircraft rolled to an unrecoverable angle. The stall occurred at approximately 400 feet, leaving insufficient altitude for recovery. The crew had not performed an independent pre-takeoff contamination check prior to departure, contrary to the operator\'s standard operating procedures.',
            'Regulators have ordered a mandatory review of ground deicing procedures and holdover time monitoring at all aerodromes served by $airlineName. The airline has suspended $routeLabel winter operations pending the adoption of an enhanced contamination check protocol, including an independent visual inspection carried out at the runway threshold before every winter departure.',
          ],
        );
      case 11:
        return (
          headline: 'Breaking: $airlineName $model lost after explosive decompression on $routeLabel',
          subheadline:
              'Fuselage skin rupture at cruise altitude caused rapid uncontrolled descent',
          paragraphs: [
            'A $model registered as $registration and operated by $airlineName has been lost after a section of fuselage skin separated at cruise altitude during a $routeLabel service, causing a rapid and catastrophic decompression. The structural failure incapacitated the flight crew within seconds. The aircraft entered an uncontrolled descent and impacted terrain.',
            'Metallurgical analysis of recovered fuselage panels has identified fatigue cracking originating at a rivet line adjacent to a passenger door frame — a region identified in a manufacturer service bulletin issued two years prior as requiring additional inspections in aircraft with more than 25,000 pressurisation cycles. Records indicate $registration had not received the bulletin-mandated inspection.',
            'An emergency airworthiness directive has been issued worldwide, requiring operators of the $model type to perform immediate non-destructive testing of the identified fuselage zones before any further flight above 10,000 feet. $airlineName\'s maintenance records are the subject of a formal criminal investigation by national aviation authorities.',
          ],
        );
      case 12:
        return (
          headline: 'Breaking: $airlineName loses $model in runway excursion on $routeLabel landing',
          subheadline:
              'Brake and thrust-reverser failures combined to catastrophic effect on wet runway',
          paragraphs: [
            'A $model operated by $airlineName has been destroyed after overrunning the end of the runway during landing on a $routeLabel service. The crew was unable to arrest the aircraft\'s groundspeed after touchdown due to a combination of anti-skid system failure, a jammed thrust reverser on the right engine, and an undetected accumulation of rubber deposits on the runway surface. The aircraft travelled through the runway end safety area and struck a blast fence.',
            'Maintenance records reveal the anti-skid control unit had been logged as intermittently faulty on three prior flights, but had been cleared each time after a ground test that did not replicate the in-flight failure mode. The jammed thrust reverser had been reported by the preceding inbound crew but was not actioned before the aircraft was returned to service.',
            '$airlineName\'s maintenance quality assurance process is under intense regulatory scrutiny following the revelation of the deferred faults. The aerodrome operator has also been called to explain why runway maintenance reports showing rubber contamination had not triggered a mandatory rubber-removal grinding operation on the affected landing area.',
          ],
        );
      case 13:
        return (
          headline: 'Breaking: $airlineName crew loses control of $model in night departure',
          subheadline:
              'Spatial disorientation on $routeLabel sector causes fatal upset in dark conditions',
          paragraphs: [
            'A $model operated by $airlineName has been lost after the flight crew experienced spatial disorientation shortly after departure on a night $routeLabel service. The aircraft climbed normally through the cloud base but then entered a series of increasing bank oscillations consistent with the classic "graveyard spiral" disorientation pattern. The airframe exceeded its structural limits during the resulting uncontrolled descent and broke up below the cloud layer.',
            'Cockpit voice recorder data indicates the crew was engaged in a discussion about an unrelated technical issue in the moments before the upset began, consistent with attention narrowing that is a known precursor to loss of spatial awareness. The aircraft\'s autopilot was not engaged, and neither crew member identified the developing bank until the aircraft had rolled beyond 60 degrees.',
            'Investigators are examining the standard of upset prevention and recovery training at $airlineName. The carrier\'s simulator programme will be reviewed to determine whether crews are receiving adequate exposure to unusual attitude recovery scenarios in instrument meteorological conditions, particularly during the critical initial climb phase.',
          ],
        );
      case 14:
        return (
          headline: 'Breaking: Runaway trim sends $airlineName $model into fatal dive',
          subheadline:
              'Automated system failure overpowered crew inputs on $routeLabel sector',
          paragraphs: [
            'A $model operated by $airlineName has been lost after a malfunctioning automated stabiliser trim system drove the horizontal stabiliser to a nose-down limit stop during cruise on a $routeLabel service. The resultant aerodynamic forces were sufficient to overpower the crew\'s manual control inputs. The aircraft entered a near-vertical dive from which it did not recover.',
            'Engineering analysis of recovered components has identified a failed angle-of-attack sensor whose erroneous output triggered the runaway trim. The flight management system was configured to act on input from a single sensor rather than requiring corroboration from the opposing side, a known but unmitigated design vulnerability. A similar fault had been reported by another operator of the same type 14 months prior but had not been escalated to the manufacturer\'s safety organisation.',
            'Aviation authorities across multiple jurisdictions have simultaneously issued emergency airworthiness directives mandating software modifications to the trim control law and requiring enhanced angle-of-attack sensor cross-checking before each flight. The $model type has been temporarily grounded worldwide pending manufacturer confirmation of the software fix.',
          ],
        );
      default:
        return (
          headline: 'Breaking: ${airlineName} $model lost on $routeLabel service',
          subheadline:
              'Investigators launch inquiry after aircraft fails to arrive at destination',
          paragraphs: [
            'A $model operated by $airlineName has been lost while operating a $routeLabel service. The aircraft, registered as $registration, failed to arrive at its destination and wreckage has been located. The cause of the accident remains under active investigation by national airworthiness authorities.',
            '$airlineName has suspended services on the $routeLabel route and is cooperating fully with investigators. The carrier has offered support to the families of all those aboard and has convened an emergency board session to assess the operational implications.',
            'Regulators have ordered a precautionary review of the carrier\'s safety management system pending the outcome of the formal investigation. The flight data and cockpit voice recorders have been recovered and will be analysed at the national accident laboratory.',
          ],
        );
    }
  }

  void _triggerAircraftCrash(
    String aircraftId,
    String routeId,
    String airlineId,
  ) {
    final ac = aircraft[aircraftId];
    final route = routes[routeId];
    final airline = airlines[airlineId];
    if (ac == null ||
        route == null ||
        airline == null ||
        ac.status == AircraftStatus.crashed) {
      return;
    }
    final type = aircraftTypesById[ac.typeId];
    final routeLabel = '${route.originIata}-${route.destinationIata}';
    aircraft[aircraftId] = ac.copyWith(
      status: AircraftStatus.crashed,
      isGrounded: true,
      groundedReason: 'Aircraft lost in accident',
      condition: 0,
      crashRisk: 0,
    );
    routes[routeId] = route.copyWith(isActive: false);

    airlines[airlineId] = airline.copyWith(
      cashUSD: airline.cashUSD - 50000000,
      reputationScore: math.max(0, airline.reputationScore - 25).toDouble(),
      crashPenaltyDaysLeft: 30,
    );

    final scenarioSeed = _stableUnitInterval(
      '$gameDay:${ac.id}:${route.id}:scenario',
    );
    final scenario = _crashScenario(
      airlineName: airline.name,
      model: type?.model ?? 'aircraft',
      registration: ac.name,
      routeLabel: routeLabel,
      seed: scenarioSeed,
    );

    final article = NewsArticle(
      id: '${airline.isPlayer ? 'crash' : 'ai_crash'}_${gameDay}_$aircraftId',
      headline: airline.isPlayer
          ? scenario.headline
          : 'Crash: ${airline.name} aircraft lost on $routeLabel',
      subheadline: scenario.subheadline,
      paragraphs: scenario.paragraphs,
      severity: 'crash',
      gameDay: gameDay,
      playerRelated: airline.isPlayer,
    );
    _publishNewsArticle(article);
    pushNewsItem(
      '${airline.isPlayer ? 'BREAKING' : 'CRASH'}: ${airline.name} ${type?.model ?? 'aircraft'} lost on $routeLabel.',
      severity: 'breaking',
      articleId: article.id,
      playerRelated: airline.isPlayer,
    );
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
        pushNewsItem(
          message,
          severity: 'breaking',
          article: generateAirportClosureArticle(
            id: 'airport-${airport.iata}-$gameDay',
            eventId: event.id,
            airportIata: airport.iata,
            cityName: airport.city,
            closureReason: event.closureReason,
            durationDays: durationDays,
            gameDay: gameDay,
            seed: airport.iata.hashCode ^ gameDay,
          ),
        );
        break;
      }
    }
  }

  void _resolveInsolvencies() {
    const playerInsolvencyLimit = -100000000.0;
    const aiInsolvencyLimit = -50000000.0;
    final playerAirline = airlines['player'];
    if (playerAirline != null && playerAirline.cashUSD <= playerInsolvencyLimit) {
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
      if (airline.cashUSD > aiInsolvencyLimit) {
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
      pushNewsItem(
        '${airline.name} has entered insolvency protection.',
        article: generateInsolvencyArticle(
          id: 'insolvency-${airline.id}-$gameDay',
          airlineName: airline.name,
          gameDay: gameDay,
          seed: airline.id.hashCode ^ gameDay,
        ),
      );
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
    // Win check uses cumulative all-time passengers (consistent with web app)
    final totalAllTime = airlines.values
        .fold<int>(0, (sum, a) => sum + a.totalPassengersAllTime);
    final playerAllTime = airlines['player']?.totalPassengersAllTime ?? 0;
    final playerCumulativeShare = totalAllTime <= 0
        ? 0.0
        : playerAllTime / totalAllTime * 100;
    final competitorsWithShare = competitors.any(
      (airline) => airline.marketSharePercent > 0,
    );
    if (settings.objective == GameObjective.marketShare &&
        competitorsWithShare &&
        playerCumulativeShare >= settings.targetMarketShare) {
      hasWon = true;
    }
  }

  int _aiExpansionIntervalDays(AirlinePersonality personality) =>
      switch (personality) {
        AirlinePersonality.aggressive => 5,
        AirlinePersonality.balanced => 8,
        AirlinePersonality.conservative => 16,
        AirlinePersonality.premium => 12,
        AirlinePersonality.budget => 8,
      };

  void _maybeExpandAI() {
    if (gameDay == 0) return;
    for (final airline in competitors) {
      final interval = _aiExpansionIntervalDays(airline.personality);
      // Stagger by a deterministic per-airline offset so not all expand at once
      final offset = airline.id.hashCode.abs() % interval;
      if ((gameDay + offset) % interval != 0) continue;
      // Don't expand beyond the per-personality route cap.
      if (airline.routeIds.length >= _aiMaxRoutes(airline.personality)) continue;
      final aiCashReserve = 12000000 + airline.fleetIds.length * 2500000.0;
      if (airline.cashUSD < aiCashReserve) {
        continue;
      }
      final hub = airportByIata(airline.hubIatas.firstOrNull ?? '');
      if (hub == null) continue;
      final existingDestinations = airline.routeIds
          .map((id) => routes[id])
          .whereType<RoutePlan>()
          .map((route) => route.destinationIata)
          .toSet();
      final allRoutes = routes.values.toList(growable: false);
      final allAirlines = airlines.values.toList(growable: false);
      final candidates = _buildAIRouteCandidates(hub, existingDestinations);
      for (final candidate in candidates) {
        final type = _pickAircraftForAI(airline, hub, candidate.airport);
        if (type == null ||
            airline.cashUSD < type.purchasePrice + _aiExpansionReserveUSD) {
          continue;
        }
        // Profitability gate: estimate daily profit before committing
        final distKm = haversineKm(
          hub.lat,
          hub.lon,
          candidate.airport.lat,
          candidate.airport.lon,
        );
        final flightHours = distKm / type.cruiseSpeedKmh;
        // Compute cost-based seed price (mirrors web estimateAIOperation)
        final flightsPerWeek = _defaultAiFrequency(airline.personality);
        final costProbeRoute = RoutePlan(
          id: '_cost_probe',
          airlineId: airline.id,
          originIata: hub.iata,
          destinationIata: candidate.airport.iata,
          aircraftId: '_dummy',
          flightsPerWeek: flightsPerWeek,
          priceEconomy: 100,
          priceBusiness: 0,
          isActive: true,
          createdGameDay: gameDay,
          distanceKm: distKm,
          flightDurationHours: flightHours,
        );
        final costProbeAc = Aircraft(
          id: '_dummy',
          name: '_dummy',
          airlineId: airline.id,
          typeId: type.id,
          status: AircraftStatus.flying,
          purchasedGameDay: gameDay,
          condition: 100,
        );
        final flightCosts = computeFlightCost(
          costProbeRoute,
          costProbeAc,
          type,
          hub,
          candidate.airport,
          globalFuelPrice,
          currentGameDay: gameDay,
        );
        final totalSeats = type.seatsEconomy + type.seatsBusiness;
        final costPerSeat =
            totalSeats > 0 ? flightCosts.totalCost / totalSeats : 200.0;
        final priceMultiplier = _aiPriceMultiplier(airline.personality);
        final seedEco =
            math.max(50, (costPerSeat * 1.45 * priceMultiplier).round());
        final seedBiz =
            type.seatsBusiness > 0 ? (seedEco * 4.0).round() : 0;
        final dummyRoute = RoutePlan(
          id: '_estimate',
          airlineId: airline.id,
          originIata: hub.iata,
          destinationIata: candidate.airport.iata,
          aircraftId: '_dummy',
          flightsPerWeek: flightsPerWeek,
          priceEconomy: seedEco,
          priceBusiness: seedBiz,
          isActive: true,
          createdGameDay: gameDay,
          distanceKm: distKm,
          flightDurationHours: flightHours,
        );
        final dummyAc = Aircraft(
          id: '_dummy',
          name: '_dummy',
          airlineId: airline.id,
          typeId: type.id,
          status: AircraftStatus.flying,
          purchasedGameDay: gameDay,
          condition: 100,
        );
        final est = calculateRouteEconomics(
          route: dummyRoute,
          aircraft: dummyAc,
          type: type,
          origin: hub,
          destination: candidate.airport,
          airline: airline,
          allRoutes: allRoutes,
          allAirlines: allAirlines,
          globalFuelPrice: globalFuelPrice,
          gameDay: gameDay,
          airportDailyPax: airportDailyPax,
        );
        // Reject routes below profit/load-factor thresholds.
        // Transcontinental routes (>4 500 km) get a relaxed floor: they carry
        // fewer flights-per-day so daily revenue is naturally lower, but
        // per-flight economics are strong.
        final estimatedLF =
            (est.passengers.toDouble() /
                    math.max(1, type.seatsEconomy + type.seatsBusiness))
                .clamp(0, 1);
        final isTranscontinental = distKm >= 4500;
        final profitFloor = isTranscontinental ? 3000.0 : 6000.0;
        final lfFloor = isTranscontinental ? 0.25 : 0.35;
        if (est.profit < profitFloor || estimatedLF < lfFloor) continue;
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
            article: generateRouteArticle(
              id: 'route-launch-${airline.id}-${hub.iata}-${candidate.airport.iata}-$gameDay',
              airlineName: airline.name,
              originIata: hub.iata,
              destIata: candidate.airport.iata,
              distanceKm: distKm,
              gameDay: gameDay,
              seed: airline.id.hashCode ^ hub.iata.hashCode ^ candidate.airport.iata.hashCode ^ gameDay,
            ),
          );
          break;
        } catch (_) {
          continue;
        }
      }
    }
  }

  void _adjustAIPrices() {
    for (final airline in competitors) {
      if (airline.isInsolvent) continue;
      for (final routeId in airline.routeIds) {
        final route = routes[routeId];
        final ac = route?.aircraftId == null
            ? null
            : aircraft[route!.aircraftId!];
        final type = ac == null ? null : aircraftTypesById[ac.typeId];
        final origin = route == null ? null : airportByIata(route.originIata);
        final dest =
            route == null ? null : airportByIata(route.destinationIata);
        if (route == null ||
            ac == null ||
            type == null ||
            origin == null ||
            dest == null) {
          continue;
        }
        final allRoutes = routes.values.toList(growable: false);
        final allAirlines = airlines.values.toList(growable: false);
        // 8-step sweep: 0.84x to 1.20x of current price
        const steps = [0.84, 0.90, 0.96, 1.00, 1.04, 1.08, 1.14, 1.20];
        var bestProfit = -double.infinity;
        var bestEco = route.priceEconomy;
        var bestBiz = route.priceBusiness;
        for (final mult in steps) {
          final trialRoute = route.copyWith(
            priceEconomy: (route.priceEconomy * mult).round(),
            priceBusiness: (route.priceBusiness * mult).round(),
          );
          final result = calculateRouteEconomics(
            route: trialRoute,
            aircraft: ac,
            type: type,
            origin: origin,
            destination: dest,
            airline: airline,
            allRoutes: allRoutes,
            allAirlines: allAirlines,
            globalFuelPrice: globalFuelPrice,
            gameDay: gameDay,
            airportDailyPax: airportDailyPax,
          );
          if (result.profit > bestProfit) {
            bestProfit = result.profit;
            bestEco = trialRoute.priceEconomy;
            bestBiz = trialRoute.priceBusiness;
          }
        }
        // Only update if change exceeds 2.5%
        final ecoChange = (bestEco - route.priceEconomy).abs() / route.priceEconomy;
        if (ecoChange > 0.025) {
          routes[routeId] = route.copyWith(
            priceEconomy: bestEco,
            priceBusiness: bestBiz,
          );
        }
      }
    }
  }

  void _pruneDistressedAIRoutes() {
    for (final airline in competitors) {
      if (airline.isInsolvent || airline.cashUSD >= _aiCashStressThreshold) {
        continue;
      }
      final maxRoutes = airline.cashUSD < _aiCriticalCashThreshold ? 3 : 1;
      final worstRoutes =
          airline.routeIds
              .map((routeId) => routes[routeId])
              .whereType<RoutePlan>()
              .where((route) => route.dailyProfit < _aiLossMakingRouteThreshold)
              .toList()
            ..sort((a, b) => a.dailyProfit.compareTo(b.dailyProfit));

      for (final route in worstRoutes.take(maxRoutes)) {
        _removeAIRoute(route);
        pushNewsItem(
          '${airline.name} has suspended a loss-making route.',
          article: generateRouteTerminationArticle(
            id: 'termination-${airline.id}-${route.id}-$gameDay',
            airlineName: airline.name,
            gameDay: gameDay,
            seed: airline.id.hashCode ^ route.id.hashCode ^ gameDay,
          ),
        );
      }
    }
  }

  void _maybeSellAICrossHoldings() {
    for (final seller in competitors) {
      if (seller.isInsolvent || seller.cashUSD > _aiShareSaleCashThreshold) {
        continue;
      }
      for (final target in competitors) {
        if (target.id == seller.id) continue;
        final stake = target.shareholders[seller.id] ?? 0;
        if (stake <= 0) continue;
        final amount = math.max(1, (stake / 2).floor()).toDouble();
        _sellAIShareholding(seller.id, target.id, amount);
      }
    }
  }

  double _sellAIShareholding(
    String sellerId,
    String targetAirlineId,
    double percent,
  ) {
    final seller = airlines[sellerId];
    final target = airlines[targetAirlineId];
    if (seller == null ||
        target == null ||
        seller.isPlayer ||
        target.isPlayer ||
        percent <= 0) {
      return 0;
    }
    final currentStake = target.shareholders[sellerId] ?? 0;
    if (currentStake <= 0) return 0;
    final amount = percent.clamp(1, currentStake).toDouble();
    final proceeds =
        (companyValue(targetAirlineId) / 100 * amount / 100000).round() *
        100000.0;
    final nextShareholders = Map<String, double>.from(target.shareholders);
    final remaining = currentStake - amount;
    if (remaining <= 0) {
      nextShareholders.remove(sellerId);
    } else {
      nextShareholders[sellerId] = remaining;
    }
    airlines[sellerId] = seller.copyWith(cashUSD: seller.cashUSD + proceeds);
    airlines[targetAirlineId] = target.copyWith(shareholders: nextShareholders);
    pushNewsItem(
      '${seller.name} sold ${amount.toStringAsFixed(0)}% of ${target.name}.',
    );
    return proceeds;
  }

  void _maybeRunAIMarketConsolidation() {
    if (gameDay > 0 && gameDay % _aiBuyoutIntervalDays == 0) {
      _maybeRunAIBuyout();
    }
    if (gameDay > 0 && gameDay % _aiDissolveIntervalDays == 0) {
      _dissolveHopelessAIAirlines();
    }
    if (gameDay > 0 && gameDay % _aiSharePurchaseIntervalDays == 0) {
      _maybeRunAISharePurchases();
    }
  }

  /// AI airlines with spare cash occasionally buy small minority stakes in
  /// rivals. Aggressive and balanced personalities are most active; premium
  /// and conservative participate rarely; budget airlines don't bother.
  void _maybeRunAISharePurchases() {
    final rng = math.Random(gameDay * 31337);
    for (final buyer in competitors) {
      if (buyer.isInsolvent) continue;
      // Gate by personality — not all types are acquisitive.
      final purchaseChance = switch (buyer.personality) {
        AirlinePersonality.aggressive => 0.65,
        AirlinePersonality.balanced => 0.40,
        AirlinePersonality.premium => 0.20,
        AirlinePersonality.conservative => 0.15,
        AirlinePersonality.budget => 0.0,
      };
      if (rng.nextDouble() > purchaseChance) continue;
      // Must have meaningful surplus above the cash floor.
      if (buyer.cashUSD < _aiSharePurchaseCashFloor) continue;
      // Pick a random solvent rival that isn't the buyer itself.
      final candidates = competitors
          .where(
            (t) =>
                t.id != buyer.id &&
                !t.isInsolvent &&
                // Don't double-down beyond the stake cap.
                (t.shareholders[buyer.id] ?? 0) < _aiSharePurchaseMaxStake,
          )
          .toList(growable: false);
      if (candidates.isEmpty) continue;
      final target = candidates[rng.nextInt(candidates.length)];
      // Buy a modest slug: 3–8 % chosen randomly, capped by remaining float
      // and the per-airline stake ceiling.
      final currentStake = target.shareholders[buyer.id] ?? 0.0;
      final maxBuy = math.min(
        8.0,
        _aiSharePurchaseMaxStake - currentStake,
      );
      if (maxBuy < 3) continue;
      final slug = (3 + rng.nextInt((maxBuy - 3 + 1).toInt())).toDouble();
      // Check there is enough market float to absorb the purchase.
      final totalIssued = target.shareholders.values.fold<double>(0, (s, v) => s + v);
      final float = 100.0 - totalIssued;
      if (float < slug) continue;
      // Price it the same way the player market does.
      final cost = calculateSharePrice(
        percentToBuy: slug,
        currentPlayerPercent: currentStake,
        airline: target,
        aircraft: aircraft,
        routes: routes,
        currentGameDay: gameDay,
        fromSecondaryMarket: false,
      );
      if (buyer.cashUSD - cost < _aiSharePurchaseCashFloor) continue;
      // Commit the transaction.
      final nextShareholders = Map<String, double>.from(target.shareholders);
      nextShareholders[buyer.id] = currentStake + slug;
      airlines[buyer.id] = buyer.copyWith(cashUSD: buyer.cashUSD - cost);
      airlines[target.id] = target.copyWith(
        cashUSD: target.cashUSD + cost,
        shareholders: nextShareholders,
      );
      pushNewsItem(
        '${buyer.name} acquires ${slug.toStringAsFixed(0)}% stake in ${target.name}.',
      );
    }
  }

  void _maybeRunAIBuyout() {
    final targets = competitors
        .where((airline) => airline.canBeTakenOver || airline.isInsolvent)
        .toList(growable: false);
    final buyers = competitors
        .where(
          (airline) =>
              !airline.isInsolvent &&
              airline.cashUSD > 30000000 &&
              (airline.personality == AirlinePersonality.aggressive ||
                  airline.personality == AirlinePersonality.balanced),
        )
        .toList(growable: false);
    if (targets.isEmpty || buyers.isEmpty) return;

    targets.sort((a, b) => a.cashUSD.compareTo(b.cashUSD));
    buyers.sort((a, b) => b.cashUSD.compareTo(a.cashUSD));
    for (final target in targets) {
      for (final buyer in buyers) {
        if (buyer.id == target.id) continue;
        final price = math
            .max(
              0,
              target.fleetIds.length * 5000000 -
                  math.max(0, -target.cashUSD).round(),
            )
            .toDouble();
        if (buyer.cashUSD < price) continue;
        _aiAcquireAirline(buyer.id, target.id, price);
        pushNewsItem(
          'ACQUISITION: ${buyer.name} has acquired ${target.name}.',
          article: generateAcquisitionArticle(
            id: 'acquisition-${buyer.id}-${target.id}-$gameDay',
            buyerName: buyer.name,
            targetName: target.name,
            gameDay: gameDay,
            seed: buyer.id.hashCode ^ target.id.hashCode ^ gameDay,
          ),
        );
        return;
      }
    }
  }

  void _aiAcquireAirline(String buyerId, String targetId, double price) {
    final buyer = airlines[buyerId];
    final target = airlines[targetId];
    if (buyer == null || target == null || buyer.isPlayer || target.isPlayer) {
      return;
    }
    final acquiredFleet = <String>[];
    for (final aircraftId in target.fleetIds) {
      final ac = aircraft[aircraftId];
      if (ac == null) continue;
      aircraft[aircraftId] = ac.copyWith(airlineId: buyerId);
      acquiredFleet.add(aircraftId);
    }
    final acquiredRoutes = <String>[];
    for (final routeId in target.routeIds) {
      final route = routes[routeId];
      if (route == null) continue;
      routes[routeId] = route.copyWith(airlineId: buyerId);
      acquiredRoutes.add(routeId);
    }
    for (final entry in airlines.entries.toList()) {
      if (entry.key == targetId) continue;
      final holdings = Map<String, double>.from(entry.value.shareholders);
      final transferred = holdings.remove(targetId);
      if (transferred != null) {
        holdings[buyerId] = (holdings[buyerId] ?? 0) + transferred;
        airlines[entry.key] = entry.value.copyWith(shareholders: holdings);
      }
    }
    airlines[buyerId] = buyer.copyWith(
      cashUSD: buyer.cashUSD - price,
      fleetIds: [...buyer.fleetIds, ...acquiredFleet],
      routeIds: [...buyer.routeIds, ...acquiredRoutes],
    );
    airlines.remove(targetId);
  }

  void _dissolveHopelessAIAirlines() {
    for (final airline in competitors.toList()) {
      if (!airline.isInsolvent || airline.cashUSD > _aiDissolveThreshold) {
        continue;
      }
      for (final routeId in airline.routeIds) {
        routes.remove(routeId);
      }
      for (final aircraftId in airline.fleetIds) {
        aircraft.remove(aircraftId);
      }
      for (final entry in airlines.entries.toList()) {
        if (entry.key == airline.id) continue;
        final holdings = Map<String, double>.from(entry.value.shareholders)
          ..remove(airline.id);
        if (holdings.length != entry.value.shareholders.length) {
          airlines[entry.key] = entry.value.copyWith(shareholders: holdings);
        }
      }
      final dissolvedName = airline.name;
      final dissolvedId = airline.id;
      airlines.remove(airline.id);
      pushNewsItem(
        '$dissolvedName has been dissolved after prolonged insolvency.',
        article: generateDissolutionArticle(
          id: 'dissolution-$dissolvedId-$gameDay',
          airlineName: dissolvedName,
          gameDay: gameDay,
          seed: dissolvedId.hashCode ^ gameDay,
        ),
      );
    }
  }

  void _removeAIRoute(RoutePlan route) {
    if (route.airlineId == 'player') return;
    final airline = airlines[route.airlineId];
    if (airline == null) return;
    if (route.aircraftId != null) {
      final ac = aircraft[route.aircraftId!];
      if (ac != null) {
        aircraft[ac.id] = ac.copyWith(
          clearAssignedRoute: true,
          status: AircraftStatus.idle,
        );
      }
    }
    routes.remove(route.id);
    airlines[airline.id] = airline.copyWith(
      routeIds: airline.routeIds.where((id) => id != route.id).toList(),
    );
  }

  void _maybeSpawnNewAI() {
    if (gameDay == 0 || gameDay % _aiSpawnIntervalDays != 0) return;
    final activeCompetitors = competitors
        .where((airline) => !airline.isInsolvent)
        .toList(growable: false);
    if (activeCompetitors.length >= _maxAiAirlines) return;

    final rng = math.Random(gameDay * 92821 + activeCompetitors.length * 97);
    final shouldSpawn = activeCompetitors.length < 4 || rng.nextDouble() < 0.5;
    if (!shouldSpawn) return;

    final existingNames = airlines.values
        .map((airline) => airline.name)
        .toSet();
    final usedHubs = activeCompetitors
        .expand((airline) => airline.hubIatas)
        .toSet();
    final availableHubs = _aiSpawnHubs
        .where(
          (iata) => !usedHubs.contains(iata) && airportsByIata[iata] != null,
        )
        .toList(growable: false);
    if (availableHubs.isEmpty) return;

    final hub = airportByIata(availableHubs[rng.nextInt(availableHubs.length)]);
    if (hub == null) return;
    final name = _generateSpawnedAirlineName(existingNames, rng);
    final prefix = name
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0])
        .join()
        .toUpperCase()
        .padRight(2, 'X')
        .substring(0, 2);
    final usedColors = airlines.values
        .map((airline) => airline.color.toLowerCase())
        .toSet();
    final color = _aiSpawnColors.firstWhere(
      (candidate) => !usedColors.contains(candidate.toLowerCase()),
      orElse: () => _aiSpawnColors[rng.nextInt(_aiSpawnColors.length)],
    );
    final personalities = AirlinePersonality.values;
    final personality = personalities[rng.nextInt(personalities.length)];
    final airlineId = 'ai-spawned-${_nextAirline++}';
    final startingCash = 30000000 + rng.nextInt(30000001);

    airlines[airlineId] = Airline(
      id: airlineId,
      name: name,
      iataPrefix: prefix,
      isPlayer: false,
      color: color,
      logoEmoji: _aiSpawnLogos[rng.nextInt(_aiSpawnLogos.length)],
      cashUSD: startingCash.toDouble(),
      hubIatas: [hub.iata],
      personality: personality,
      foundedGameDay: gameDay,
      reputationScore: 50,
    );
    _markAirportHub(hub.iata);
    pushNewsItem(
      'NEW ENTRANT: $name has launched a new hub at ${hub.iata}.',
      article: generateNewEntrantArticle(
        id: 'entrant-$airlineId-$gameDay',
        airlineName: name,
        hubIata: hub.iata,
        hubCity: hub.city,
        gameDay: gameDay,
        seed: airlineId.hashCode ^ gameDay,
      ),
    );

    final airline = airlines[airlineId]!;
    final existingDestinations = <String>{};
    final candidates = _buildAIRouteCandidates(hub, existingDestinations);
    for (final candidate in candidates) {
      if (existingDestinations.contains(candidate.airport.iata)) continue;
      final type = _pickAircraftForAI(airline, hub, candidate.airport);
      if (type == null ||
          airlines[airlineId]!.cashUSD < type.purchasePrice + 10000000) {
        continue;
      }
      try {
        final route = _createRouteForAirline(
          airlineId: airlineId,
          originIata: hub.iata,
          destinationIata: candidate.airport.iata,
          aircraftTypeId: type.id,
          flightsPerWeek: _defaultAiFrequency(personality),
          buyNewAircraft: true,
        );
        _optimiseRouteForAirline(route.id, airlineId);
        break;
      } catch (_) {
        continue;
      }
    }
  }

  String _generateSpawnedAirlineName(
    Set<String> existingNames,
    math.Random rng,
  ) {
    for (var i = 0; i < 30; i++) {
      final candidate =
          '${_aiNamePrefixes[rng.nextInt(_aiNamePrefixes.length)]} ${_aiNameSuffixes[rng.nextInt(_aiNameSuffixes.length)]}';
      if (!existingNames.contains(candidate)) return candidate;
    }
    return 'New entrant ${_nextAirline + 1}';
  }

  /// Builds a mixed candidate pool for AI route expansion.
  ///
  /// Pure demand-sort buries transcontinental routes because the demand model
  /// applies a strong distance penalty. This helper returns:
  ///   - up to 16 short/medium-haul candidates sorted by demand
  ///   - up to 12 transcontinental candidates (>4 500 km, different region,
  ///     major or large airports) sorted by airport size then demand
  ///
  /// The two pools are deduplicated and capped at 28 total entries.
  List<({Airport airport, double demand})> _buildAIRouteCandidates(
    Airport hub,
    Set<String> excludeIatas,
  ) {
    final all = airportList
        .where(
          (a) => a.iata != hub.iata && !excludeIatas.contains(a.iata),
        )
        .map((airport) {
          final distKm =
              haversineKm(hub.lat, hub.lon, airport.lat, airport.lon);
          return (
            airport: airport,
            demand: baselineDailyPassengers(hub, airport),
            distKm: distKm,
          );
        })
        .toList();

    // Short/medium haul — demand-sorted (unchanged behaviour)
    final demandSorted = (all.toList()
          ..sort((a, b) => b.demand.compareTo(a.demand)))
        .take(16)
        .toList();
    final demandIatas = demandSorted.map((c) => c.airport.iata).toSet();

    // Transcontinental — major/large airports in a different region, >4 500 km
    final transcontinental =
        (all
                .where(
                  (c) =>
                      c.distKm >= 4500 &&
                      c.airport.region != hub.region &&
                      (c.airport.size == AirportSize.major ||
                          c.airport.size == AirportSize.large) &&
                      !demandIatas.contains(c.airport.iata),
                )
                .toList()
              ..sort((a, b) {
                // Major before large, then higher demand wins within tier
                final sizeA = a.airport.size == AirportSize.major ? 1 : 0;
                final sizeB = b.airport.size == AirportSize.major ? 1 : 0;
                if (sizeA != sizeB) return sizeB.compareTo(sizeA);
                return b.demand.compareTo(a.demand);
              }))
            .take(12);

    return [
      ...demandSorted.map((c) => (airport: c.airport, demand: c.demand)),
      ...transcontinental.map((c) => (airport: c.airport, demand: c.demand)),
    ];
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
              type.purchasePrice <= airline.cashUSD * switch (airline.personality) {
                AirlinePersonality.aggressive => 0.34,
                AirlinePersonality.balanced => 0.28,
                AirlinePersonality.budget => 0.30,
                AirlinePersonality.premium => 0.30,
                AirlinePersonality.conservative => 0.24,
              },
        )
        .toList();
    if (affordable.isEmpty) return null;
    final homeAirport = airportByIata(airline.hubIatas.firstOrNull ?? '');
    affordable.sort((a, b) {
      final scoreA =
          a.seatsEconomy *
          aiManufacturerPreferenceWeight(airline, a, homeAirport);
      final scoreB =
          b.seatsEconomy *
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

  double buyShares(
    String targetAirlineId,
    double percent, {
    String source = 'market',
  }) {
    final target = airlines[targetAirlineId];
    if (target == null || target.isPlayer) {
      throw StateError('Target airline not found');
    }
    final amount = percent.clamp(1, 50).toDouble();
    final isSecondary = source != 'market';
    if (isSecondary) {
      final sellerStake = stakeInAirline(targetAirlineId, source);
      if (sellerStake < amount) throw StateError('Not enough seller shares');
    } else {
      final available = marketFloatForAirline(targetAirlineId);
      if (available < amount) throw StateError('Not enough market float');
    }
    final cost = sharePurchasePrice(targetAirlineId, amount, source: source);
    if (player.cashUSD < cost) throw StateError('Not enough cash');
    final nextShareholders = Map<String, double>.from(target.shareholders);
    nextShareholders['player'] = (nextShareholders['player'] ?? 0) + amount;
    if (isSecondary) {
      final remaining = (nextShareholders[source] ?? 0) - amount;
      if (remaining <= 0) {
        nextShareholders.remove(source);
      } else {
        nextShareholders[source] = remaining;
      }
    }
    airlines['player'] = player.copyWith(cashUSD: player.cashUSD - cost);
    if (isSecondary) {
      final seller = airlines[source];
      if (seller != null) {
        airlines[source] = seller.copyWith(cashUSD: seller.cashUSD + cost);
      }
    }
    airlines[targetAirlineId] = target.copyWith(
      cashUSD: isSecondary ? target.cashUSD : target.cashUSD + cost,
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
        dailyFuelCost: 0,
        dailyMaintenanceCost: 0,
        dailyCrewCost: 0,
        dailyAirportFees: 0,
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

  String exportProgressJson() => jsonEncode({
    'kind': exportKind,
    'exportVersion': exportVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'game': 'Mighty Airline Empire',
    'state': toJson(),
  });

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
    'showAiOnMap': showAiOnMap,
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
    'newspaperQueue': newspaperQueue,
    'latestArticleId': latestArticleId,
    'nextAircraft': _nextAircraft,
    'nextRoute': _nextRoute,
    'nextLoan': _nextLoan,
    'nextAirline': _nextAirline,
  };

  void importJson(String rawJson) {
    hasStarted = true;
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final raw = decoded['state'] is Map
        ? Map<String, dynamic>.from(decoded['state'] as Map)
        : decoded;
    settings = GameSettings.fromJson(
      Map<String, Object?>.from(raw['settings'] as Map? ?? const {}),
    );
    gameDay = (raw['gameDay'] as num?)?.round() ?? 0;
    gameTimeMs = (raw['gameTimeMs'] as num?)?.round() ?? 0;
    speed = (raw['speed'] as num?)?.round() ?? 60;
    isPaused = raw['isPaused'] == true;
    hasWon = raw['hasWon'] == true;
    hasLost = raw['hasLost'] == true;
    themeMode = _themeModeFromJson(raw['themeMode']);
    showAiOnMap = raw['showAiOnMap'] != false;
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
    airlines.addAll(
      (raw['aiAirlines'] as Map? ?? const {}).map(
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
    aircraft.addAll(
      (raw['aiAircraft'] as Map? ?? const {}).map(
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
    routes.addAll(
      (raw['aiRoutes'] as Map? ?? const {}).map(
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
    newspaperQueue
      ..clear()
      ..addAll(
        (raw['newspaperQueue'] as List? ?? const []).whereType<String>().where(
          newsArticles.containsKey,
        ),
      );
    latestArticleId = raw['latestArticleId'] as String?;
    _nextAircraft =
        (raw['nextAircraft'] as num?)?.round() ?? aircraft.length + 1;
    _nextRoute = (raw['nextRoute'] as num?)?.round() ?? routes.length + 1;
    _nextLoan = (raw['nextLoan'] as num?)?.round() ?? 1;
    _nextAirline =
        (raw['nextAirline'] as num?)?.round() ??
        airlines.keys.where((id) => id.startsWith('ai-spawned-')).length + 1;
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
