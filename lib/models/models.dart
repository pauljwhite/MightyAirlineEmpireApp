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

enum AircraftStatus { idle, flying, maintenance, crashed }

enum MaintenanceTier { light, standard, full }

enum AirlinePersonality { aggressive, balanced, conservative, budget, premium }

enum Difficulty { easy, normal, hard }

enum GameObjective { lastAirlineStanding, marketShare }

T _enumValue<T extends Enum>(List<T> values, Object? value, T fallback) {
  if (value is String) {
    for (final item in values) {
      if (item.name == value) return item;
    }
  }
  return fallback;
}

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
  }) => Airport(
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
    firstClassLoungeLevel: firstClassLoungeLevel ?? this.firstClassLoungeLevel,
  );
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
  String get displayName => manufacturer + ' ' + model;
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

class Aircraft {
  const Aircraft({
    required this.id,
    required this.typeId,
    required this.name,
    required this.airlineId,
    required this.purchasedGameDay,
    this.totalFlightHours = 0,
    this.condition = 100,
    this.maintenanceHoursOwed = 0,
    this.isGrounded = false,
    this.groundedReason,
    this.lastMaintenanceGameDay = 0,
    this.crashRisk = 0.0001,
    this.assignedRouteId,
    this.status = AircraftStatus.idle,
    this.currentLat = 0,
    this.currentLon = 0,
    this.flightProgress = 0,
    this.activeMaintTier,
    this.autoMaintenanceEnabled = false,
    this.autoMaintenanceThreshold = 40,
    this.autoMaintenanceTier = MaintenanceTier.standard,
    this.knownFaultRiskMod = 1,
    this.excludedFromPolicy = false,
  });
  final String id;
  final String typeId;
  final String name;
  final String airlineId;
  final int purchasedGameDay;
  final double totalFlightHours;
  final double condition;
  final double maintenanceHoursOwed;
  final bool isGrounded;
  final String? groundedReason;
  final int lastMaintenanceGameDay;
  final double crashRisk;
  final String? assignedRouteId;
  final AircraftStatus status;
  final double currentLat;
  final double currentLon;
  final double flightProgress;
  final MaintenanceTier? activeMaintTier;
  final bool autoMaintenanceEnabled;
  final double autoMaintenanceThreshold;
  final MaintenanceTier autoMaintenanceTier;
  final double knownFaultRiskMod;
  final bool excludedFromPolicy;
  Aircraft copyWith({
    String? assignedRouteId,
    double? totalFlightHours,
    double? condition,
    double? maintenanceHoursOwed,
    AircraftStatus? status,
    bool? isGrounded,
    String? groundedReason,
    int? lastMaintenanceGameDay,
  }) => Aircraft(
    id: id,
    typeId: typeId,
    name: name,
    airlineId: airlineId,
    purchasedGameDay: purchasedGameDay,
    totalFlightHours: totalFlightHours ?? this.totalFlightHours,
    condition: condition ?? this.condition,
    maintenanceHoursOwed: maintenanceHoursOwed ?? this.maintenanceHoursOwed,
    isGrounded: isGrounded ?? this.isGrounded,
    groundedReason: groundedReason ?? this.groundedReason,
    lastMaintenanceGameDay:
        lastMaintenanceGameDay ?? this.lastMaintenanceGameDay,
    crashRisk: crashRisk,
    assignedRouteId: assignedRouteId ?? this.assignedRouteId,
    status: status ?? this.status,
    currentLat: currentLat,
    currentLon: currentLon,
    flightProgress: flightProgress,
    activeMaintTier: activeMaintTier,
    autoMaintenanceEnabled: autoMaintenanceEnabled,
    autoMaintenanceThreshold: autoMaintenanceThreshold,
    autoMaintenanceTier: autoMaintenanceTier,
    knownFaultRiskMod: knownFaultRiskMod,
    excludedFromPolicy: excludedFromPolicy,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'typeId': typeId,
    'name': name,
    'airlineId': airlineId,
    'purchasedGameDay': purchasedGameDay,
    'totalFlightHours': totalFlightHours,
    'condition': condition,
    'maintenanceHoursOwed': maintenanceHoursOwed,
    'isGrounded': isGrounded,
    'groundedReason': groundedReason,
    'lastMaintenanceGameDay': lastMaintenanceGameDay,
    'crashRisk': crashRisk,
    'assignedRouteId': assignedRouteId,
    'status': status.name,
    'currentLat': currentLat,
    'currentLon': currentLon,
    'flightProgress': flightProgress,
    'activeMaintTier': activeMaintTier?.name,
    'autoMaintenanceEnabled': autoMaintenanceEnabled,
    'autoMaintenanceThreshold': autoMaintenanceThreshold,
    'autoMaintenanceTier': autoMaintenanceTier.name,
    'knownFaultRiskMod': knownFaultRiskMod,
    'excludedFromPolicy': excludedFromPolicy,
  };
  factory Aircraft.fromJson(Map<String, Object?> json) => Aircraft(
    id: json['id'] as String,
    typeId: json['typeId'] as String,
    name: json['name'] as String,
    airlineId: json['airlineId'] as String,
    purchasedGameDay: (json['purchasedGameDay'] as num?)?.round() ?? 0,
    totalFlightHours: (json['totalFlightHours'] as num?)?.toDouble() ?? 0,
    condition: (json['condition'] as num?)?.toDouble() ?? 100,
    maintenanceHoursOwed:
        (json['maintenanceHoursOwed'] as num?)?.toDouble() ?? 0,
    isGrounded: json['isGrounded'] == true,
    groundedReason: json['groundedReason'] as String?,
    lastMaintenanceGameDay:
        (json['lastMaintenanceGameDay'] as num?)?.round() ?? 0,
    crashRisk: (json['crashRisk'] as num?)?.toDouble() ?? 0.0001,
    assignedRouteId: json['assignedRouteId'] as String?,
    status: _enumValue(
      AircraftStatus.values,
      json['status'],
      AircraftStatus.idle,
    ),
    currentLat: (json['currentLat'] as num?)?.toDouble() ?? 0,
    currentLon: (json['currentLon'] as num?)?.toDouble() ?? 0,
    flightProgress: (json['flightProgress'] as num?)?.toDouble() ?? 0,
    activeMaintTier: json['activeMaintTier'] == null
        ? null
        : _enumValue(
            MaintenanceTier.values,
            json['activeMaintTier'],
            MaintenanceTier.standard,
          ),
    autoMaintenanceEnabled: json['autoMaintenanceEnabled'] == true,
    autoMaintenanceThreshold:
        (json['autoMaintenanceThreshold'] as num?)?.toDouble() ?? 40,
    autoMaintenanceTier: _enumValue(
      MaintenanceTier.values,
      json['autoMaintenanceTier'],
      MaintenanceTier.standard,
    ),
    knownFaultRiskMod: (json['knownFaultRiskMod'] as num?)?.toDouble() ?? 1,
    excludedFromPolicy: json['excludedFromPolicy'] == true,
  );
}

class RoutePlan {
  const RoutePlan({
    required this.id,
    required this.airlineId,
    required this.originIata,
    required this.destinationIata,
    this.aircraftId,
    required this.flightsPerWeek,
    required this.priceEconomy,
    required this.priceBusiness,
    this.isActive = true,
    required this.createdGameDay,
    required this.distanceKm,
    this.flightDurationHours = 0,
    this.dailyPassengers = 0,
    this.dailyRevenue = 0,
    this.dailyCost = 0,
    this.dailyProfit = 0,
    this.loadFactorEconomy = 0,
    this.loadFactorBusiness = 0,
  });
  final String id;
  final String airlineId;
  final String originIata;
  final String destinationIata;
  final String? aircraftId;
  final int flightsPerWeek;
  final int priceEconomy;
  final int priceBusiness;
  final bool isActive;
  final int createdGameDay;
  final double distanceKm;
  final double flightDurationHours;
  final int dailyPassengers;
  final double dailyRevenue;
  final double dailyCost;
  final double dailyProfit;
  final double loadFactorEconomy;
  final double loadFactorBusiness;
  RoutePlan copyWith({
    String? aircraftId,
    int? flightsPerWeek,
    int? priceEconomy,
    int? priceBusiness,
    bool? isActive,
    double? flightDurationHours,
    int? dailyPassengers,
    double? dailyRevenue,
    double? dailyCost,
    double? dailyProfit,
    double? loadFactorEconomy,
    double? loadFactorBusiness,
  }) => RoutePlan(
    id: id,
    airlineId: airlineId,
    originIata: originIata,
    destinationIata: destinationIata,
    aircraftId: aircraftId ?? this.aircraftId,
    flightsPerWeek: flightsPerWeek ?? this.flightsPerWeek,
    priceEconomy: priceEconomy ?? this.priceEconomy,
    priceBusiness: priceBusiness ?? this.priceBusiness,
    isActive: isActive ?? this.isActive,
    createdGameDay: createdGameDay,
    distanceKm: distanceKm,
    flightDurationHours: flightDurationHours ?? this.flightDurationHours,
    dailyPassengers: dailyPassengers ?? this.dailyPassengers,
    dailyRevenue: dailyRevenue ?? this.dailyRevenue,
    dailyCost: dailyCost ?? this.dailyCost,
    dailyProfit: dailyProfit ?? this.dailyProfit,
    loadFactorEconomy: loadFactorEconomy ?? this.loadFactorEconomy,
    loadFactorBusiness: loadFactorBusiness ?? this.loadFactorBusiness,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'airlineId': airlineId,
    'originIata': originIata,
    'destinationIata': destinationIata,
    'aircraftId': aircraftId,
    'flightsPerWeek': flightsPerWeek,
    'priceEconomy': priceEconomy,
    'priceBusiness': priceBusiness,
    'isActive': isActive,
    'createdGameDay': createdGameDay,
    'distanceKm': distanceKm,
    'flightDurationHours': flightDurationHours,
    'dailyPassengers': dailyPassengers,
    'dailyRevenue': dailyRevenue,
    'dailyCost': dailyCost,
    'dailyProfit': dailyProfit,
    'loadFactorEconomy': loadFactorEconomy,
    'loadFactorBusiness': loadFactorBusiness,
  };
  factory RoutePlan.fromJson(Map<String, Object?> json) => RoutePlan(
    id: json['id'] as String,
    airlineId: json['airlineId'] as String,
    originIata: json['originIata'] as String,
    destinationIata: json['destinationIata'] as String,
    aircraftId: json['aircraftId'] as String?,
    flightsPerWeek: (json['flightsPerWeek'] as num?)?.round() ?? 1,
    priceEconomy: (json['priceEconomy'] as num?)?.round() ?? 0,
    priceBusiness: (json['priceBusiness'] as num?)?.round() ?? 0,
    isActive: json['isActive'] != false,
    createdGameDay: (json['createdGameDay'] as num?)?.round() ?? 0,
    distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
    flightDurationHours: (json['flightDurationHours'] as num?)?.toDouble() ?? 0,
    dailyPassengers: (json['dailyPassengers'] as num?)?.round() ?? 0,
    dailyRevenue: (json['dailyRevenue'] as num?)?.toDouble() ?? 0,
    dailyCost: (json['dailyCost'] as num?)?.toDouble() ?? 0,
    dailyProfit: (json['dailyProfit'] as num?)?.toDouble() ?? 0,
    loadFactorEconomy: (json['loadFactorEconomy'] as num?)?.toDouble() ?? 0,
    loadFactorBusiness: (json['loadFactorBusiness'] as num?)?.toDouble() ?? 0,
  );
}

class DailySnapshot {
  const DailySnapshot({
    required this.gameDay,
    required this.revenue,
    required this.costs,
    required this.profit,
    required this.passengers,
    required this.cashEnd,
  });
  final int gameDay;
  final double revenue;
  final double costs;
  final double profit;
  final int passengers;
  final double cashEnd;
  Map<String, Object?> toJson() => {
    'gameDay': gameDay,
    'revenue': revenue,
    'costs': costs,
    'profit': profit,
    'passengers': passengers,
    'cashEnd': cashEnd,
  };
  factory DailySnapshot.fromJson(Map<String, Object?> json) => DailySnapshot(
    gameDay: (json['gameDay'] as num?)?.round() ?? 0,
    revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
    costs: (json['costs'] as num?)?.toDouble() ?? 0,
    profit: (json['profit'] as num?)?.toDouble() ?? 0,
    passengers: (json['passengers'] as num?)?.round() ?? 0,
    cashEnd: (json['cashEnd'] as num?)?.toDouble() ?? 0,
  );
}

class Loan {
  const Loan({
    required this.id,
    required this.principalUSD,
    required this.annualInterestRate,
    required this.termYears,
    required this.dailyPaymentUSD,
    required this.issuedGameDay,
  });
  final String id;
  final double principalUSD;
  final double annualInterestRate;
  final int termYears;
  final double dailyPaymentUSD;
  final int issuedGameDay;
  Map<String, Object?> toJson() => {
    'id': id,
    'principalUSD': principalUSD,
    'annualInterestRate': annualInterestRate,
    'termYears': termYears,
    'dailyPaymentUSD': dailyPaymentUSD,
    'issuedGameDay': issuedGameDay,
  };
  factory Loan.fromJson(Map<String, Object?> json) => Loan(
    id: json['id'] as String,
    principalUSD: (json['principalUSD'] as num?)?.toDouble() ?? 0,
    annualInterestRate: (json['annualInterestRate'] as num?)?.toDouble() ?? 0,
    termYears: (json['termYears'] as num?)?.round() ?? 5,
    dailyPaymentUSD: (json['dailyPaymentUSD'] as num?)?.toDouble() ?? 0,
    issuedGameDay: (json['issuedGameDay'] as num?)?.round() ?? 0,
  );
}

class MaintenancePolicy {
  const MaintenancePolicy({
    this.enabled = false,
    this.threshold = 40,
    this.tier = MaintenanceTier.standard,
    this.autoMaintainIssues = false,
  });
  final bool enabled;
  final double threshold;
  final MaintenanceTier tier;
  final bool autoMaintainIssues;
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'threshold': threshold,
    'tier': tier.name,
    'autoMaintainIssues': autoMaintainIssues,
  };
  factory MaintenancePolicy.fromJson(Map<String, Object?>? json) => json == null
      ? const MaintenancePolicy()
      : MaintenancePolicy(
          enabled: json['enabled'] == true,
          threshold: (json['threshold'] as num?)?.toDouble() ?? 40,
          tier: _enumValue(
            MaintenanceTier.values,
            json['tier'],
            MaintenanceTier.standard,
          ),
          autoMaintainIssues: json['autoMaintainIssues'] == true,
        );
}

class Airline {
  const Airline({
    required this.id,
    required this.name,
    required this.iataPrefix,
    required this.isPlayer,
    required this.color,
    required this.logoEmoji,
    required this.cashUSD,
    this.totalDebt = 0,
    this.hubIatas = const [],
    this.fleetIds = const [],
    this.routeIds = const [],
    this.personality = AirlinePersonality.balanced,
    this.foundedGameDay = 0,
    this.isInsolvent = false,
    this.canBeTakenOver = false,
    this.marketSharePercent = 0,
    this.reputationScore = 50,
    this.totalPassengersAllTime = 0,
    this.dailyStats = const [],
    this.crashPenaltyDaysLeft = 0,
    this.shareholders = const {},
    this.lastDailyProfit = 0,
    this.loans = const [],
    this.maintenancePolicy = const MaintenancePolicy(),
  });
  final String id;
  final String name;
  final String iataPrefix;
  final bool isPlayer;
  final String color;
  final String logoEmoji;
  final double cashUSD;
  final double totalDebt;
  final List<String> hubIatas;
  final List<String> fleetIds;
  final List<String> routeIds;
  final AirlinePersonality personality;
  final int foundedGameDay;
  final bool isInsolvent;
  final bool canBeTakenOver;
  final double marketSharePercent;
  final double reputationScore;
  final int totalPassengersAllTime;
  final List<DailySnapshot> dailyStats;
  final int crashPenaltyDaysLeft;
  final Map<String, double> shareholders;
  final double lastDailyProfit;
  final List<Loan> loans;
  final MaintenancePolicy maintenancePolicy;
  Airline copyWith({
    double? cashUSD,
    double? totalDebt,
    List<String>? fleetIds,
    List<String>? routeIds,
    double? marketSharePercent,
    double? reputationScore,
    int? totalPassengersAllTime,
    List<DailySnapshot>? dailyStats,
    double? lastDailyProfit,
    List<Loan>? loans,
  }) => Airline(
    id: id,
    name: name,
    iataPrefix: iataPrefix,
    isPlayer: isPlayer,
    color: color,
    logoEmoji: logoEmoji,
    cashUSD: cashUSD ?? this.cashUSD,
    totalDebt: totalDebt ?? this.totalDebt,
    hubIatas: hubIatas,
    fleetIds: fleetIds ?? this.fleetIds,
    routeIds: routeIds ?? this.routeIds,
    personality: personality,
    foundedGameDay: foundedGameDay,
    isInsolvent: isInsolvent,
    canBeTakenOver: canBeTakenOver,
    marketSharePercent: marketSharePercent ?? this.marketSharePercent,
    reputationScore: reputationScore ?? this.reputationScore,
    totalPassengersAllTime:
        totalPassengersAllTime ?? this.totalPassengersAllTime,
    dailyStats: dailyStats ?? this.dailyStats,
    crashPenaltyDaysLeft: crashPenaltyDaysLeft,
    shareholders: shareholders,
    lastDailyProfit: lastDailyProfit ?? this.lastDailyProfit,
    loans: loans ?? this.loans,
    maintenancePolicy: maintenancePolicy,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'iataPrefix': iataPrefix,
    'isPlayer': isPlayer,
    'color': color,
    'logoEmoji': logoEmoji,
    'cashUSD': cashUSD,
    'totalDebt': totalDebt,
    'hubIatas': hubIatas,
    'fleetIds': fleetIds,
    'routeIds': routeIds,
    'personality': personality.name,
    'foundedGameDay': foundedGameDay,
    'isInsolvent': isInsolvent,
    'canBeTakenOver': canBeTakenOver,
    'marketSharePercent': marketSharePercent,
    'reputationScore': reputationScore,
    'totalPassengersAllTime': totalPassengersAllTime,
    'dailyStats': dailyStats.map((s) => s.toJson()).toList(),
    'crashPenaltyDaysLeft': crashPenaltyDaysLeft,
    'shareholders': shareholders,
    'lastDailyProfit': lastDailyProfit,
    'loans': loans.map((l) => l.toJson()).toList(),
    'maintenancePolicy': maintenancePolicy.toJson(),
  };
  factory Airline.fromJson(Map<String, Object?> json) => Airline(
    id: json['id'] as String,
    name: json['name'] as String,
    iataPrefix: json['iataPrefix'] as String? ?? '',
    isPlayer: json['isPlayer'] == true,
    color: json['color'] as String? ?? '#3b82f6',
    logoEmoji: json['logoEmoji'] as String? ?? '✈️',
    cashUSD: (json['cashUSD'] as num?)?.toDouble() ?? 0,
    totalDebt: (json['totalDebt'] as num?)?.toDouble() ?? 0,
    hubIatas: List<String>.from(json['hubIatas'] as List? ?? const []),
    fleetIds: List<String>.from(json['fleetIds'] as List? ?? const []),
    routeIds: List<String>.from(json['routeIds'] as List? ?? const []),
    personality: _enumValue(
      AirlinePersonality.values,
      json['personality'],
      AirlinePersonality.balanced,
    ),
    foundedGameDay: (json['foundedGameDay'] as num?)?.round() ?? 0,
    isInsolvent: json['isInsolvent'] == true,
    canBeTakenOver: json['canBeTakenOver'] == true,
    marketSharePercent: (json['marketSharePercent'] as num?)?.toDouble() ?? 0,
    reputationScore: (json['reputationScore'] as num?)?.toDouble() ?? 50,
    totalPassengersAllTime:
        (json['totalPassengersAllTime'] as num?)?.round() ?? 0,
    dailyStats: (json['dailyStats'] as List? ?? const [])
        .map((e) => DailySnapshot.fromJson(Map<String, Object?>.from(e as Map)))
        .toList(),
    crashPenaltyDaysLeft: (json['crashPenaltyDaysLeft'] as num?)?.round() ?? 0,
    shareholders: Map<String, double>.from(
      (json['shareholders'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key as String, (value as num).toDouble()),
      ),
    ),
    lastDailyProfit: (json['lastDailyProfit'] as num?)?.toDouble() ?? 0,
    loans: (json['loans'] as List? ?? const [])
        .map((e) => Loan.fromJson(Map<String, Object?>.from(e as Map)))
        .toList(),
    maintenancePolicy: MaintenancePolicy.fromJson(
      json['maintenancePolicy'] == null
          ? null
          : Map<String, Object?>.from(json['maintenancePolicy'] as Map),
    ),
  );
}

class GameSettings {
  const GameSettings({
    this.playerAirlineName = 'My Airline',
    this.playerAirlineColor = '#3b82f6',
    this.playerAirlineEmoji = '✈️',
    this.startingCash = 30000000,
    this.difficulty = Difficulty.normal,
    this.aiCount = 6,
    this.startingYear = 1960,
    this.objective = GameObjective.lastAirlineStanding,
    this.targetMarketShare = 60,
    this.currency = 'USD',
  });
  final String playerAirlineName;
  final String playerAirlineColor;
  final String playerAirlineEmoji;
  final double startingCash;
  final Difficulty difficulty;
  final int aiCount;
  final int startingYear;
  final GameObjective objective;
  final double targetMarketShare;
  final String currency;
  Map<String, Object?> toJson() => {
    'playerAirlineName': playerAirlineName,
    'playerAirlineColor': playerAirlineColor,
    'playerAirlineEmoji': playerAirlineEmoji,
    'startingCash': startingCash,
    'difficulty': difficulty.name,
    'aiCount': aiCount,
    'startingYear': startingYear,
    'objective': objective.name,
    'targetMarketShare': targetMarketShare,
    'currency': currency,
  };
  factory GameSettings.fromJson(Map<String, Object?> json) => GameSettings(
    playerAirlineName: json['playerAirlineName'] as String? ?? 'My Airline',
    playerAirlineColor: json['playerAirlineColor'] as String? ?? '#3b82f6',
    playerAirlineEmoji: json['playerAirlineEmoji'] as String? ?? '✈️',
    startingCash: (json['startingCash'] as num?)?.toDouble() ?? 30000000,
    difficulty: _enumValue(
      Difficulty.values,
      json['difficulty'],
      Difficulty.normal,
    ),
    aiCount: (json['aiCount'] as num?)?.round() ?? 6,
    startingYear: (json['startingYear'] as num?)?.round() ?? 1960,
    objective: _enumValue(
      GameObjective.values,
      json['objective'],
      GameObjective.lastAirlineStanding,
    ),
    targetMarketShare: (json['targetMarketShare'] as num?)?.toDouble() ?? 60,
    currency: json['currency'] as String? ?? 'USD',
  );
}
