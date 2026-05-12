import '../data/aircraft_types.dart';
import '../models/models.dart';

class BuyoutValuation {
  const BuyoutValuation({
    required this.fleetValue,
    required this.routeValue,
    required this.cashValue,
    required this.debtValue,
    required this.controlPremium,
    required this.totalPrice,
  });

  final double fleetValue;
  final double routeValue;
  final double cashValue;
  final double debtValue;
  final double controlPremium;
  final double totalPrice;
}

double computeAircraftValue(Aircraft aircraft, int currentGameDay) {
  final type = aircraftTypesById[aircraft.typeId];
  if (type == null) return 0;
  final ageYears =
      (currentGameDay - aircraft.purchasedGameDay).clamp(0, 36500) / 365;
  final ageFactor = (1 - ageYears / 20).clamp(0.2, 1.0);
  final conditionFactor = 0.2 + 0.8 * (aircraft.condition / 100);
  final hoursFactor = (1 - aircraft.totalFlightHours / 100000).clamp(0.8, 1.0);
  return type.purchasePrice * 0.75 * ageFactor * conditionFactor * hoursFactor;
}

double rawCompanyValue({
  required Airline airline,
  required Map<String, Aircraft> aircraft,
  required Map<String, RoutePlan> routes,
  required int currentGameDay,
}) {
  final fleetValue = airline.fleetIds.fold<double>(0, (sum, id) {
    final ac = aircraft[id];
    return ac == null ? sum : sum + computeAircraftValue(ac, currentGameDay);
  });
  final annualProfit = airline.routeIds.fold<double>(0, (sum, id) {
    final route = routes[id];
    return sum +
        (route == null ? 0 : route.dailyProfit.clamp(0, double.infinity) * 365);
  });
  final routeValue = annualProfit * 2;
  return (fleetValue + routeValue + airline.cashUSD - airline.totalDebt).clamp(
    1000000,
    double.infinity,
  );
}

BuyoutValuation calculateBuyoutPrice({
  required Airline airline,
  required Map<String, Aircraft> aircraft,
  required Map<String, RoutePlan> routes,
  required int currentGameDay,
}) {
  final fleetValue = airline.fleetIds.fold<double>(0, (sum, id) {
    final ac = aircraft[id];
    return ac == null ? sum : sum + computeAircraftValue(ac, currentGameDay);
  });
  final annualProfit = airline.routeIds.fold<double>(0, (sum, id) {
    final route = routes[id];
    return sum +
        (route == null ? 0 : route.dailyProfit.clamp(0, double.infinity) * 365);
  });
  final routeValue = annualProfit * 2;
  final cashValue = airline.cashUSD.clamp(0, double.infinity).toDouble();
  final debtValue =
      airline.totalDebt +
      (-airline.cashUSD).clamp(0, double.infinity).toDouble();
  final raw = fleetValue + routeValue + cashValue - debtValue;
  final controlPremium = (raw * 0.2).clamp(0, double.infinity).toDouble();
  final totalPrice =
      ((raw + controlPremium).clamp(1000000, double.infinity) / 500000)
          .round() *
      500000.0;
  return BuyoutValuation(
    fleetValue: fleetValue,
    routeValue: routeValue,
    cashValue: cashValue,
    debtValue: debtValue,
    controlPremium: controlPremium,
    totalPrice: totalPrice,
  );
}

double calculateSharePrice({
  required double percentToBuy,
  required double currentPlayerPercent,
  required Airline airline,
  required Map<String, Aircraft> aircraft,
  required Map<String, RoutePlan> routes,
  required int currentGameDay,
  bool fromSecondaryMarket = false,
}) {
  final baseValue = rawCompanyValue(
    airline: airline,
    aircraft: aircraft,
    routes: routes,
    currentGameDay: currentGameDay,
  );
  final willCrossMajority =
      currentPlayerPercent < 50 && currentPlayerPercent + percentToBuy >= 50;
  final blockMultiplier = willCrossMajority
      ? 1.25
      : percentToBuy > 25
      ? 1.1
      : percentToBuy > 10
      ? 1.05
      : 1.0;
  final secondaryPremium = fromSecondaryMarket ? 1.15 : 1.0;
  return ((baseValue / 100) *
              percentToBuy *
              blockMultiplier *
              secondaryPremium /
              100000)
          .round() *
      100000.0;
}
