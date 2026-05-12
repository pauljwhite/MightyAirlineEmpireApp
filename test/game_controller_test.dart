import 'package:flutter_test/flutter_test.dart';
import 'package:mighty_airline_empire_app/data/aircraft_types.dart';
import 'package:mighty_airline_empire_app/data/airports.dart';
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

    game.repayLoans(1000000);
    expect(game.player.cashUSD, greaterThan(0));
    expect(game.player.totalDebt, lessThan(loan.principalUSD));
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
  });

  test('new game settings are applied to the player and AI setup', () {
    final game = GameController();
    game.startNewGame(
      const GameSettings(
        playerAirlineName: 'Danube Airways',
        playerAirlineEmoji: '🛫',
        startingCash: 15000000,
        difficulty: Difficulty.hard,
        aiCount: 2,
        objective: GameObjective.marketShare,
        targetMarketShare: 80,
        currency: 'EUR',
      ),
    );

    expect(game.player.name, 'Danube Airways');
    expect(game.player.logoEmoji, '🛫');
    expect(game.player.cashUSD, 15000000);
    expect(game.competitors, hasLength(2));
    expect(game.settings.difficulty, Difficulty.hard);
    expect(game.settings.objective, GameObjective.marketShare);
    expect(game.settings.targetMarketShare, 80);
    expect(game.settings.currency, 'EUR');
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
    expect(game.newsTicker.last, contains('Read the article'));
    expect(game.aircraft[aircraftId]!.isGrounded, isTrue);

    final restored = GameController()..importJson(game.exportJson());
    expect(restored.latestArticleId, article.id);
    expect(restored.newsArticles[article.id]?.headline, article.headline);
  });
}
