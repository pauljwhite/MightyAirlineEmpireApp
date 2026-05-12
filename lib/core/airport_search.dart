import '../models/models.dart';

String _normalise(String value) => value.trim().toLowerCase();

List<Airport> searchAirports(
  String query,
  List<Airport> source, {
  int limit = 8,
}) {
  final q = _normalise(query);
  if (q.isEmpty) return const [];
  int score(Airport airport) {
    final iata = airport.iata.toLowerCase();
    final icao = airport.icao?.toLowerCase() ?? '';
    final city = airport.city.toLowerCase();
    final name = airport.name.toLowerCase();
    final country = airport.country.toLowerCase();
    if (iata == q || icao == q) return 0;
    if (iata.startsWith(q) || icao.startsWith(q)) return 1;
    if (city.startsWith(q)) return 2;
    if (name.startsWith(q)) return 3;
    if (country.startsWith(q)) return 4;
    if (city.contains(q)) return 5;
    if (name.contains(q)) return 6;
    if (country.contains(q)) return 7;
    return 99;
  }

  final matches = source.where((airport) => score(airport) < 99).toList()
    ..sort((a, b) {
      final byScore = score(a).compareTo(score(b));
      if (byScore != 0) return byScore;
      return a.iata.compareTo(b.iata);
    });
  return matches.take(limit).toList(growable: false);
}
