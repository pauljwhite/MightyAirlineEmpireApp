import 'package:flutter_test/flutter_test.dart';
import 'package:mighty_airline_empire_app/data/aircraft_types.dart';
import 'package:mighty_airline_empire_app/data/airports.dart';
import 'package:mighty_airline_empire_app/engine/economics_engine.dart';
import 'package:mighty_airline_empire_app/engine/finance.dart';
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
  });
}
