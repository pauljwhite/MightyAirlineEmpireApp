import 'package:flutter_test/flutter_test.dart';
import 'package:mighty_airline_empire_app/core/constants.dart';
import 'package:mighty_airline_empire_app/data/aircraft_types.dart';
import 'package:mighty_airline_empire_app/data/airports.dart';
import 'package:mighty_airline_empire_app/engine/demand_model.dart';
import 'package:mighty_airline_empire_app/engine/economics_engine.dart';
import 'package:mighty_airline_empire_app/engine/finance.dart';
import 'package:mighty_airline_empire_app/models/models.dart';
import 'package:mighty_airline_empire_app/state/game_controller.dart';

void main() {
  test(
    'new game can buy aircraft, create a route, optimise it, and tick economics',
    () {
      final game = GameController();
      final initialCash = game.player.cashUSD;
      final type = aircraftTypesById['b707-120']!;

      final route = game.createRoute(
        originIata: 'LHR',
        destinationIata: 'JFK',
        aircraftTypeId: type.id,
        flightsPerWeek: 7,
        buyNewAircraft: true,
      );

      expect(game.playerFleet, hasLength(1));
      expect(game.playerRoutes, hasLength(1));
      expect(game.player.cashUSD, lessThan(initialCash));
      expect(route.aircraftId, isNotNull);

      final optimised = game.optimiseRoute(route.id);
      final optimisedRoute = game.routes[route.id]!;
      final assigned = game.aircraft[optimisedRoute.aircraftId]!;
      final costs = computeFlightCost(
        optimisedRoute,
        assigned,
        type,
        airportsByIata['LHR']!,
        airportsByIata['JFK']!,
        game.globalFuelPrice,
        currentGameDay: game.gameDay,
      );
      final cap =
          (costs.totalCost / (type.seatsEconomy + type.seatsBusiness) * 1.3 * 3)
              .round();

      expect(optimised.flightsPerWeek, inInclusiveRange(1, 21));
      expect(optimised.priceEconomy, lessThanOrEqualTo(cap + 100));
      expect(
        optimisedRoute.priceBusiness,
        type.seatsBusiness > 0 ? greaterThan(0) : 0,
      );

      final snapshot = game.runDailyTick();
      expect(snapshot.revenue, greaterThanOrEqualTo(0));
      expect(game.gameDay, 1);
      expect(game.player.dailyStats, hasLength(1));
    },
  );

  test('loans can be applied and repaid early', () {
    final game = GameController();
    final loan = game.applyForLoan(loanOffers.first);
    expect(game.player.loans.single.id, loan.id);
    expect(game.player.totalDebt, loan.principalUSD);

    game.repayLoan(loan.id, 1000000);
    expect(game.player.cashUSD, greaterThan(0));
    expect(game.player.totalDebt, lessThan(loan.principalUSD));
  });

  test('loan repayment only affects the selected loan and clamps to cash', () {
    final game = GameController();
    game.startNewGame(const GameSettings(startingCash: 30000000));
    final first = game.applyForLoan(loanOffers.first);
    final second = game.applyForLoan(loanOffers[1]);
    final cashBefore = game.player.cashUSD;

    game.repayLoan(first.id, first.principalUSD * 0.25);

    final updatedFirst = game.player.loans.firstWhere((l) => l.id == first.id);
    final updatedSecond = game.player.loans.firstWhere(
      (l) => l.id == second.id,
    );
    expect(updatedFirst.principalUSD, first.principalUSD * 0.75);
    expect(updatedSecond.principalUSD, second.principalUSD);
    expect(game.player.cashUSD, cashBefore - first.principalUSD * 0.25);

    game.repayLoan(first.id, double.infinity);
    expect(game.player.loans.any((loan) => loan.id == first.id), isFalse);
    expect(game.player.cashUSD, greaterThanOrEqualTo(0));
  });

  test('aircraft can be bought directly into the player fleet', () {
    final game = GameController();
    game.startNewGame(const GameSettings(startingCash: 100000000));
    final type = aircraftTypesById['b707-120']!;
    final cashBefore = game.player.cashUSD;

    final aircraft = game.buyAircraft(type.id);

    expect(game.playerFleet, contains(aircraft));
    expect(game.player.fleetIds, contains(aircraft.id));
    expect(aircraft.assignedRouteId, isNull);
    expect(aircraft.status, AircraftStatus.idle);
    expect(game.player.cashUSD, cashBefore - type.purchasePrice);
  });

  test('game clock advances time and runs daily ticks at speed', () {
    final game = GameController();
    game.setSpeed(300);

    game.advanceGameClock(const Duration(milliseconds: 288000));

    expect(game.gameDay, 1);
    expect(game.gameTimeMs, greaterThanOrEqualTo(gameDayMs));
    expect(game.player.dailyStats, hasLength(1));

    game.setSpeed(0);
    final pausedTime = game.gameTimeMs;
    game.advanceGameClock(const Duration(days: 1));
    expect(game.gameTimeMs, pausedTime);
  });

  test('game clock advances aircraft positions between daily ticks', () {
    final game = GameController();
    final type = aircraftTypesById['b707-120']!;
    final route = game.createRoute(
      originIata: 'LHR',
      destinationIata: 'JFK',
      aircraftTypeId: type.id,
      buyNewAircraft: true,
    );
    final aircraftId = game.routes[route.id]!.aircraftId!;
    final before = game.aircraft[aircraftId]!;

    game.setSpeed(300);
    game.advanceGameClock(const Duration(seconds: 10));

    final after = game.aircraft[aircraftId]!;
    expect(after.flightProgress, greaterThan(before.flightProgress));
    expect(after.currentLat, isNot(before.currentLat));
    expect(after.currentLon, isNot(before.currentLon));
    expect(after.status, AircraftStatus.flying);
  });

  test('airport closures persist and suspend route economics', () {
    final game = GameController();
    final type = aircraftTypesById['b707-120']!;
    final route = game.createRoute(
      originIata: 'LHR',
      destinationIata: 'JFK',
      aircraftTypeId: type.id,
      buyNewAircraft: true,
    );

    game.setAirportClosure('JFK', 2, 'Storm');
    final closedSnapshot = game.runDailyTick();

    expect(game.isAirportClosed('JFK'), isTrue);
    expect(game.routes[route.id]!.dailyRevenue, 0);
    expect(closedSnapshot.passengers, 0);

    final restored = GameController()..importJson(game.exportJson());
    expect(restored.airportByIata('JFK')!.closureReason, 'Storm');
    expect(restored.isAirportClosed('JFK'), isTrue);

    restored
      ..runDailyTick()
      ..runDailyTick();
    expect(restored.isAirportClosed('JFK'), isFalse);
  });

  test('player insolvency creates a game over state', () {
    final game = GameController();
    game.airlines['player'] = game.player.copyWith(cashUSD: -120000000);

    game.runDailyTick();

    expect(game.hasLost, isTrue);
    expect(game.hasWon, isFalse);

    game.dismissGameOutcome();
    expect(game.hasLost, isFalse);
  });

  test('last airline standing objective wins after competitors collapse', () {
    final game = GameController();
    game.startNewGame(
      const GameSettings(
        objective: GameObjective.lastAirlineStanding,
        aiCount: 2,
      ),
    );
    for (final competitor in game.competitors) {
      game.airlines[competitor.id] = competitor.copyWith(cashUSD: -120000000);
    }

    game.runDailyTick();

    expect(game.hasWon, isTrue);
    expect(game.competitors.every((airline) => airline.isInsolvent), isTrue);
  });

  test('export and import preserves a freeze-frame of progress', () {
    final game = GameController();
    game.startNewGame(
      const GameSettings(
        playerAirlineName: 'Soviet Airlines',
        playerAirlineEmoji: '🌐',
        startingCash: 50000000,
        difficulty: Difficulty.easy,
        aiCount: 4,
        objective: GameObjective.marketShare,
        targetMarketShare: 75,
        currency: 'GBP',
      ),
    );
    final type = aircraftTypesById['b707-120']!;
    game.createRoute(
      originIata: 'LHR',
      destinationIata: 'JFK',
      aircraftTypeId: type.id,
      buyNewAircraft: true,
    );
    game.setThemeMode(ThemeModeSetting.light);
    game.runDailyTick();
    final exported = game.exportJson();

    final restored = GameController()..importJson(exported);
    expect(restored.gameDay, game.gameDay);
    expect(restored.playerRoutes.length, game.playerRoutes.length);
    expect(restored.playerFleet.length, game.playerFleet.length);
    expect(restored.player.cashUSD, game.player.cashUSD);
    expect(restored.settings.playerAirlineName, 'Soviet Airlines');
    expect(restored.settings.aiCount, 4);
    expect(restored.settings.objective, GameObjective.marketShare);
    expect(restored.settings.targetMarketShare, 75);
    expect(restored.settings.currency, 'GBP');
    expect(restored.themeMode, ThemeModeSetting.light);
  });

  test('new game settings are applied to the player and AI setup', () {
    final game = GameController();
    game.startNewGame(
      const GameSettings(
        playerAirlineName: 'Danube Airways',
        playerAirlineColor: '#14b8a6',
        playerAirlineEmoji: '🛫',
        startingHubIata: 'VIE',
        startingCash: 15000000,
        difficulty: Difficulty.hard,
        aiCount: 2,
        startingYear: 1990,
        objective: GameObjective.marketShare,
        targetMarketShare: 80,
        currency: 'EUR',
      ),
    );

    expect(game.player.name, 'Danube Airways');
    expect(game.player.color, '#14b8a6');
    expect(game.player.logoEmoji, '🛫');
    expect(game.player.hubIatas, contains('VIE'));
    expect(game.airportByIata('VIE')!.isHub, isTrue);
    expect(game.player.cashUSD, 15000000);
    expect(game.competitors, hasLength(2));
    expect(game.settings.difficulty, Difficulty.hard);
    expect(game.settings.startingYear, 1990);
    expect(game.settings.objective, GameObjective.marketShare);
    expect(game.settings.targetMarketShare, 80);
    expect(game.settings.currency, 'EUR');
  });

  test('player airline can be rebranded for a calculated cost', () {
    final game = GameController();
    final cashBefore = game.player.cashUSD;
    final cost = game.rebrandCost(
      name: 'Mighty Test Air',
      color: '#14b8a6',
      logoEmoji: 'MT',
    );

    final charged = game.rebrandAirline(
      name: 'Mighty Test Air',
      color: '#14b8a6',
      logoEmoji: 'MT',
    );

    expect(charged, cost);
    expect(game.player.name, 'Mighty Test Air');
    expect(game.player.color, '#14b8a6');
    expect(game.player.logoEmoji, 'MT');
    expect(game.player.cashUSD, cashBefore - cost);

    final restored = GameController()..importJson(game.exportJson());
    expect(restored.player.name, 'Mighty Test Air');
    expect(restored.player.color, '#14b8a6');
    expect(restored.player.logoEmoji, 'MT');
  });

  test('custom image airline logos survive rebrand export and import', () {
    const imageLogo =
        'data:image/png;base64,'
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';
    final game = GameController();

    game.rebrandAirline(logoEmoji: imageLogo);

    expect(game.player.logoEmoji, imageLogo);

    final restored = GameController()..importJson(game.exportJson());
    expect(restored.player.logoEmoji, imageLogo);
  });

  test('hub upgrades charge cash, persist, and affect demand', () {
    final game = GameController();
    game.startNewGame(const GameSettings(startingCash: 2000000000));
    final beforeCash = game.player.cashUSD;
    final beforeDemand = baselineDailyPassengers(
      game.airportByIata('LHR')!,
      game.airportByIata('JFK')!,
    );

    expect(game.upgradeHubTerminal('LHR'), isTrue);
    expect(game.upgradeFirstClassLounge('LHR'), isTrue);

    final upgraded = game.airportByIata('LHR')!;
    expect(upgraded.isHub, isTrue);
    expect(upgraded.hubTerminalLevel, 1);
    expect(upgraded.firstClassLoungeLevel, 1);
    expect(game.player.cashUSD, lessThan(beforeCash));
    expect(
      baselineDailyPassengers(upgraded, game.airportByIata('JFK')!),
      greaterThan(beforeDemand),
    );

    final restored = GameController()..importJson(game.exportJson());
    expect(restored.airportByIata('LHR')!.hubTerminalLevel, 1);
    expect(restored.airportByIata('LHR')!.firstClassLoungeLevel, 1);
  });

  test('hub network can remove extra hubs and charges daily fees', () {
    final game = GameController();
    final startingCash = game.player.cashUSD;

    expect(game.setPlayerHub('JFK'), isTrue);
    expect(game.player.hubIatas, contains('JFK'));
    expect(game.removePlayerHub('JFK'), isTrue);
    expect(game.player.hubIatas, isNot(contains('JFK')));
    expect(game.removePlayerHub('LHR'), isFalse);

    game.runDailyTick();
    expect(
      game.player.cashUSD,
      closeTo(startingCash - hubAnnualFeeUsd / 365, 1),
    );
  });

  test(
    'AI airlines initialise, compete for market share, and expand over time',
    () {
      final game = GameController();
      expect(game.competitors, isNotEmpty);
      expect(
        game.routes.values.where(
          (route) => !route.airlineId.startsWith('player'),
        ),
        isNotEmpty,
      );

      for (var i = 0; i < 12; i += 1) {
        game.runDailyTick();
      }

      final totalShare = game.airlines.values.fold<double>(
        0,
        (sum, airline) => sum + airline.marketSharePercent,
      );
      expect(totalShare, closeTo(100, 0.01));
      expect(
        game.competitors.any((airline) => airline.dailyStats.isNotEmpty),
        isTrue,
      );
      expect(
        game.routes.values
            .where((route) => !route.airlineId.startsWith('player'))
            .length,
        greaterThanOrEqualTo(game.competitors.length),
      );
    },
  );

  test('new AI airlines can enter during long-running games', () {
    final game = GameController();
    game.startNewGame(const GameSettings(aiCount: 0));

    for (var i = 0; i < 16; i += 1) {
      game.runDailyTick();
    }

    expect(game.competitors, isNotEmpty);
    final entrant = game.competitors.first;
    expect(entrant.id, startsWith('ai-spawned-'));
    expect(entrant.hubIatas, isNotEmpty);
    expect(game.airportByIata(entrant.hubIatas.first)!.isHub, isTrue);

    final restored = GameController()..importJson(game.exportJson());
    expect(
      restored.competitors.any((airline) => airline.id == entrant.id),
      isTrue,
    );
  });

  test('distressed AI airlines suspend loss-making routes', () {
    final game = GameController();
    game.startNewGame(const GameSettings(aiCount: 1));
    final airline = game.competitors.single;
    final routeId = airline.routeIds.first;
    final route = game.routes[routeId]!;
    final aircraftId = route.aircraftId!;

    game.airlines[airline.id] = airline.copyWith(cashUSD: 10000000);
    game.routes[routeId] = route.copyWith(priceEconomy: 1, priceBusiness: 1);

    game.runDailyTick();

    expect(game.routes[routeId], isNull);
    expect(game.airlines[airline.id]!.routeIds, isNot(contains(routeId)));
    expect(game.aircraft[aircraftId]!.assignedRouteId, isNull);
    expect(game.aircraft[aircraftId]!.status, AircraftStatus.idle);
  });

  test('healthy AI airlines can acquire distressed competitors', () {
    final game = GameController();
    game.startNewGame(const GameSettings(aiCount: 2));
    final buyer = game.competitors.firstWhere(
      (airline) =>
          airline.personality == AirlinePersonality.aggressive ||
          airline.personality == AirlinePersonality.balanced,
    );
    final target = game.competitors.firstWhere(
      (airline) => airline.id != buyer.id,
    );
    final targetRouteIds = [...target.routeIds];
    final targetFleetIds = [...target.fleetIds];

    game.airlines[buyer.id] = buyer.copyWith(cashUSD: 150000000);
    game.airlines[target.id] = target.copyWith(
      cashUSD: 20000000,
      canBeTakenOver: true,
    );

    for (var i = 0; i < 91; i += 1) {
      game.runDailyTick();
    }

    expect(game.airlines[target.id], isNull);
    final updatedBuyer = game.airlines[buyer.id]!;
    expect(updatedBuyer.routeIds, containsAll(targetRouteIds));
    expect(updatedBuyer.fleetIds, containsAll(targetFleetIds));
    for (final routeId in targetRouteIds) {
      expect(game.routes[routeId]!.airlineId, buyer.id);
    }
    for (final aircraftId in targetFleetIds) {
      expect(game.aircraft[aircraftId]!.airlineId, buyer.id);
    }
  });

  test('hopeless insolvent AI airlines can be dissolved', () {
    final game = GameController();
    game.startNewGame(const GameSettings(aiCount: 1));
    final target = game.competitors.single;
    final targetRouteIds = [...target.routeIds];
    final targetFleetIds = [...target.fleetIds];
    game.airlines[target.id] = target.copyWith(
      cashUSD: -150000000,
      isInsolvent: true,
      canBeTakenOver: true,
    );

    for (var i = 0; i < 31; i += 1) {
      game.runDailyTick();
    }

    expect(game.airlines[target.id], isNull);
    for (final routeId in targetRouteIds) {
      expect(game.routes[routeId], isNull);
    }
    for (final aircraftId in targetFleetIds) {
      expect(game.aircraft[aircraftId], isNull);
    }
  });

  test(
    'share purchases fund competitors and majority stake enables takeover',
    () {
      final game = GameController();
      game.startNewGame(
        const GameSettings(startingCash: 500000000, aiCount: 1),
      );
      final target = game.competitors.single;
      final targetCashBefore = target.cashUSD;
      final playerCashBefore = game.player.cashUSD;

      final cost = game.buyShares(target.id, 50);
      final fundedTarget = game.airlines[target.id]!;
      expect(game.playerStakeIn(target.id), 50);
      expect(fundedTarget.cashUSD, targetCashBefore + cost);
      expect(game.player.cashUSD, playerCashBefore - cost);

      final targetRoutes = fundedTarget.routeIds.length;
      final targetFleet = fundedTarget.fleetIds.length;
      final takeoverCost = game.takeoverAirline(target.id);

      expect(takeoverCost, greaterThanOrEqualTo(0));
      expect(game.airlines[target.id], isNull);
      expect(game.playerRoutes.length, greaterThanOrEqualTo(targetRoutes));
      expect(game.playerFleet.length, greaterThanOrEqualTo(targetFleet));
      expect(
        game.playerRoutes.every((route) => route.airlineId == 'player'),
        isTrue,
      );
      expect(
        game.playerFleet.every((aircraft) => aircraft.airlineId == 'player'),
        isTrue,
      );
    },
  );

  test('route settings can be edited after creation', () {
    final game = GameController();
    final type = aircraftTypesById['b707-120']!;
    final route = game.createRoute(
      originIata: 'LHR',
      destinationIata: 'JFK',
      aircraftTypeId: type.id,
      buyNewAircraft: true,
    );

    game.updateRouteSettings(
      route.id,
      flightsPerWeek: 3,
      priceEconomy: 1234,
      priceBusiness: 5678,
      isActive: false,
    );

    final edited = game.routes[route.id]!;
    expect(edited.flightsPerWeek, 3);
    expect(edited.priceEconomy, 1234);
    expect(edited.priceBusiness, 5678);
    expect(edited.isActive, isFalse);
  });

  test('network optimiser charges only routes that can improve', () {
    final game = GameController();
    game.startNewGame(const GameSettings(startingCash: 250000000));
    final type = aircraftTypesById['b707-120']!;
    final route = game.createRoute(
      originIata: 'LHR',
      destinationIata: 'JFK',
      aircraftTypeId: type.id,
      buyNewAircraft: true,
    );
    game.updateRouteSettings(
      route.id,
      flightsPerWeek: 1,
      priceEconomy: 1,
      priceBusiness: 1,
    );

    final preview = game.previewNetworkOptimisation();
    expect(preview.eligibleCount, 1);
    expect(preview.optimisableCount, 1);
    expect(
      preview.costUSD,
      optimiseAllBaseCostUSD + optimiseAllCostPerRouteUSD,
    );

    final cashBefore = game.player.cashUSD;
    final changed = game.optimiseAllPlayerRoutes();
    expect(changed, isTrue);
    expect(game.player.cashUSD, cashBefore - preview.costUSD);
    expect(game.routes[route.id]!.priceEconomy, greaterThan(1));

    final after = game.previewNetworkOptimisation();
    expect(after.eligibleCount, 1);
    expect(after.optimisableCount, 0);
    final cashAfterFirstOptimise = game.player.cashUSD;
    expect(game.optimiseAllPlayerRoutes(), isFalse);
    expect(game.player.cashUSD, cashAfterFirstOptimise);
  });

  test(
    'route aircraft can be assigned, bought for route, and sold cleanly',
    () {
      final game = GameController();
      final type = aircraftTypesById['b707-120']!;
      final route = game.createRoute(
        originIata: 'LHR',
        destinationIata: 'JFK',
        aircraftTypeId: type.id,
        buyNewAircraft: false,
      );

      expect(game.routes[route.id]!.aircraftId, isNull);
      final bought = game.buyAircraftForRoute(type.id, route.id);
      expect(game.routes[route.id]!.aircraftId, bought.id);
      expect(game.aircraft[bought.id]!.assignedRouteId, route.id);
      expect(game.routes[route.id]!.isActive, isTrue);

      game.assignAircraftToRoute(bought.id, null);
      expect(game.routes[route.id]!.aircraftId, isNull);
      expect(game.routes[route.id]!.isActive, isFalse);
      expect(game.aircraft[bought.id]!.assignedRouteId, isNull);

      game.assignAircraftToRoute(bought.id, route.id);
      final cashBeforeSale = game.player.cashUSD;
      final saleValue = game.sellAircraft(bought.id);
      expect(saleValue, greaterThan(0));
      expect(game.aircraft[bought.id], isNull);
      expect(game.routes[route.id]!.aircraftId, isNull);
      expect(game.routes[route.id]!.isActive, isFalse);
      expect(game.player.cashUSD, cashBeforeSale + saleValue);
    },
  );

  test('deleting a route removes it and returns aircraft to idle', () {
    final game = GameController();
    final type = aircraftTypesById['b707-120']!;
    final route = game.createRoute(
      originIata: 'LHR',
      destinationIata: 'JFK',
      aircraftTypeId: type.id,
      buyNewAircraft: true,
    );
    final aircraftId = game.routes[route.id]!.aircraftId!;

    expect(game.deleteRoute(route.id), isTrue);

    expect(game.routes[route.id], isNull);
    expect(game.player.routeIds, isNot(contains(route.id)));
    expect(game.aircraft[aircraftId]!.assignedRouteId, isNull);
    expect(game.aircraft[aircraftId]!.status, AircraftStatus.idle);
    expect(game.deleteRoute(route.id), isFalse);
  });

  test('aircraft can enter and complete maintenance', () {
    final game = GameController();
    final type = aircraftTypesById['b707-120']!;
    final route = game.createRoute(
      originIata: 'LHR',
      destinationIata: 'JFK',
      aircraftTypeId: type.id,
      buyNewAircraft: true,
    );
    game.runDailyTick();
    final aircraftId = game.routes[route.id]!.aircraftId!;
    game.updateRouteSettings(route.id, isActive: false);
    final beforeCash = game.player.cashUSD;
    final cost = game.maintenanceCost(aircraftId, MaintenanceTier.light);

    game.startMaintenance(aircraftId, MaintenanceTier.light);
    expect(game.aircraft[aircraftId]!.status, AircraftStatus.maintenance);
    expect(game.player.cashUSD, beforeCash - cost);

    game.runDailyTick();
    game.runDailyTick();
    expect(game.aircraft[aircraftId]!.status, AircraftStatus.idle);
    expect(game.aircraft[aircraftId]!.maintenanceHoursOwed, 0);
  });

  test('fleet maintenance policy auto-sends eligible aircraft', () {
    final game = GameController();
    final type = aircraftTypesById['b707-120']!;
    final route = game.createRoute(
      originIata: 'LHR',
      destinationIata: 'JFK',
      aircraftTypeId: type.id,
      buyNewAircraft: true,
    );
    final aircraftId = game.routes[route.id]!.aircraftId!;
    game.aircraft[aircraftId] = game.aircraft[aircraftId]!.copyWith(
      condition: 35,
      maintenanceHoursOwed: 12,
    );
    game.updateMaintenancePolicy(
      const MaintenancePolicy(
        enabled: true,
        threshold: 40,
        tier: MaintenanceTier.standard,
        autoMaintainIssues: true,
      ),
    );

    game.runDailyTick();

    expect(game.aircraft[aircraftId]!.status, AircraftStatus.maintenance);
    expect(game.routes[route.id]!.isActive, isFalse);
    expect(game.player.maintenancePolicy.autoMaintainIssues, isTrue);
  });

  test('fleet incidents create persisted herald articles', () {
    final game = GameController();
    final type = aircraftTypesById['b707-120']!;
    final route = game.createRoute(
      originIata: 'LHR',
      destinationIata: 'JFK',
      aircraftTypeId: type.id,
      buyNewAircraft: true,
    );
    final aircraftId = game.routes[route.id]!.aircraftId!;

    final article = game.triggerAircraftIncident(aircraftId);
    expect(game.latestArticleId, article.id);
    expect(game.newsArticles[article.id], isNotNull);
    expect(game.newsTicker.first.articleId, article.id);
    expect(game.newsTicker.first.playerRelated, isTrue);
    expect(game.aircraft[aircraftId]!.isGrounded, isTrue);

    final restored = GameController()..importJson(game.exportJson());
    expect(restored.latestArticleId, article.id);
    expect(restored.newsArticles[article.id]?.headline, article.headline);
  });

  test(
    'grounded incident aircraft can be kept flying with fault risk logged',
    () {
      final game = GameController();
      final type = aircraftTypesById['b707-120']!;
      final route = game.createRoute(
        originIata: 'LHR',
        destinationIata: 'JFK',
        aircraftTypeId: type.id,
        buyNewAircraft: true,
      );
      final aircraftId = game.routes[route.id]!.aircraftId!;

      game.triggerAircraftIncident(aircraftId);
      game.keepIssueAircraftFlying(aircraftId);

      final aircraft = game.aircraft[aircraftId]!;
      expect(aircraft.isGrounded, isFalse);
      expect(aircraft.groundedReason, isNull);
      expect(aircraft.status, AircraftStatus.flying);
      expect(aircraft.knownFaultRiskMod, greaterThanOrEqualTo(3));
      expect(aircraft.maintenanceHoursOwed, greaterThan(0));
      expect(game.routes[route.id]!.isActive, isTrue);
    },
  );
}
