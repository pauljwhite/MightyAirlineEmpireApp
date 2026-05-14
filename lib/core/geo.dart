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

double shortestLongitudeDelta(double fromLon, double toLon) =>
    ((toLon - fromLon) % 360 + 540) % 360 - 180;

double normalizeLongitude(double lon) => ((lon + 180) % 360 + 360) % 360 - 180;

({double lat, double lon}) visualRouteArcPoint(
  double originLat,
  double originLon,
  double destinationLat,
  double destinationLon,
  double progress, {
  double? lonDelta,
  bool normalize = true,
}) {
  final t = progress.clamp(0.0, 1.0);
  final delta = lonDelta ?? shortestLongitudeDelta(originLon, destinationLon);
  final averageLatRad = ((originLat + destinationLat) / 2) * math.pi / 180;
  final weightedLonDelta = delta * math.max(0.25, math.cos(averageLatRad));
  final planarDistance = math.sqrt(
    weightedLonDelta * weightedLonDelta +
        (destinationLat - originLat) * (destinationLat - originLat),
  );
  final hemisphere = ((originLat + destinationLat) / 2) >= 0 ? 1 : -1;
  final latBow =
      hemisphere * math.min(10.0, planarDistance * 0.065 + delta.abs() / 180);
  final point = (
    lat:
        (originLat +
                (destinationLat - originLat) * t +
                math.sin(math.pi * t) * latBow)
            .clamp(-85.0, 85.0),
    lon: originLon + delta * t,
  );
  return normalize
      ? (lat: point.lat, lon: normalizeLongitude(point.lon))
      : point;
}

({double lat, double lon, double bearingRadians}) roundTripRoutePosition({
  required double originLat,
  required double originLon,
  required double destinationLat,
  required double destinationLon,
  required double flightProgress,
  double lookAhead = 0.01,
}) {
  final cycle = flightProgress.clamp(0.0, 1.0);
  final outbound = cycle <= 0.5;
  final legProgress = outbound ? cycle * 2 : (cycle - 0.5) * 2;
  final fromLat = outbound ? originLat : destinationLat;
  final fromLon = outbound ? originLon : destinationLon;
  final toLat = outbound ? destinationLat : originLat;
  final toLon = outbound ? destinationLon : originLon;
  final point = visualRouteArcPoint(
    fromLat,
    fromLon,
    toLat,
    toLon,
    legProgress,
  );
  final ahead = visualRouteArcPoint(
    fromLat,
    fromLon,
    toLat,
    toLon,
    math.min(1, legProgress + lookAhead),
  );
  final bearing =
      math.atan2(
        -(ahead.lat - point.lat),
        shortestLongitudeDelta(point.lon, ahead.lon),
      ) +
      math.pi / 2;
  return (lat: point.lat, lon: point.lon, bearingRadians: bearing);
}
