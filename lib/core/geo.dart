import 'dart:math' as math;

const earthRadiusKm = 6371.0;

double degreesToRadians(double degrees) => degrees * math.pi / 180;

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  final dLat = degreesToRadians(lat2 - lat1);
  final dLon = degreesToRadians(lon2 - lon1);
  final rLat1 = degreesToRadians(lat1);
  final rLat2 = degreesToRadians(lat2);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rLat1) *
          math.cos(rLat2) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
