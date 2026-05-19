import '../models/models.dart';

const maxHubTerminalLevel = 3;
const maxFirstClassLoungeLevel = 3;

const _terminalBaseCost = {
  AirportSize.small: 60000000,
  AirportSize.medium: 140000000,
  AirportSize.large: 350000000,
  AirportSize.major: 800000000,
};

const _loungeBaseCost = {
  AirportSize.small: 18000000,
  AirportSize.medium: 45000000,
  AirportSize.large: 120000000,
  AirportSize.major: 260000000,
};

int getHubTerminalLevel(Airport airport) =>
    airport.hubTerminalLevel.clamp(0, maxHubTerminalLevel).toInt();

int getFirstClassLoungeLevel(Airport airport) =>
    airport.firstClassLoungeLevel.clamp(0, maxFirstClassLoungeLevel).toInt();

double getHubCapacityMultiplier(Airport airport) =>
    [1.0, 1.5, 2.0, 2.5][getHubTerminalLevel(airport)];

double getHubDemandMultiplier(Airport airport) =>
    [1.0, 1.06, 1.12, 1.2][getFirstClassLoungeLevel(airport)];

double? getHubTerminalUpgradeCost(Airport airport) {
  final nextLevel = getHubTerminalLevel(airport) + 1;
  if (nextLevel > maxHubTerminalLevel) return null;
  final base =
      _terminalBaseCost[airport.size] ?? _terminalBaseCost[AirportSize.medium]!;
  return (base * (1 + (nextLevel - 1) * 0.75)).roundToDouble();
}

double? getFirstClassLoungeUpgradeCost(Airport airport) {
  final nextLevel = getFirstClassLoungeLevel(airport) + 1;
  if (nextLevel > maxFirstClassLoungeLevel) return null;
  final base =
      _loungeBaseCost[airport.size] ?? _loungeBaseCost[AirportSize.medium]!;
  return (base * (1 + (nextLevel - 1) * 0.65)).roundToDouble();
}
