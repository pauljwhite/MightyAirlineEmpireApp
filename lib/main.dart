import 'package:flutter/material.dart';

import 'core/airport_search.dart';
import 'core/format.dart';
import 'data/aircraft_types.dart';
import 'data/airports.dart';
import 'engine/demand_model.dart';
import 'models/models.dart';

void main() => runApp(const MightyAirlineEmpireApp());

class MightyAirlineEmpireApp extends StatefulWidget {
  const MightyAirlineEmpireApp({super.key});
  @override
  State<MightyAirlineEmpireApp> createState() => _MightyAirlineEmpireAppState();
}

class _MightyAirlineEmpireAppState extends State<MightyAirlineEmpireApp> {
  var currency = currencyOptions.first;
  var speed = 1;
  Airport? selectedAirport = airportsByIata['LHR'];
  var panel = _Panel.routes;
  var mobileSearchOpen = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mighty Airline Empire',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xff050915),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2f8cff),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 980;
              return Stack(
                children: [
                  Positioned.fill(
                    child: _WorldMap(
                      selectedAirport: selectedAirport,
                      onAirportSelected: (a) =>
                          setState(() => selectedAirport = a),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _TopBar(
                      compact: compact,
                      currency: currency,
                      speed: speed,
                      searchOpen: mobileSearchOpen,
                      onToggleSearch: () =>
                          setState(() => mobileSearchOpen = !mobileSearchOpen),
                      onCurrency: (v) => setState(() => currency = v),
                      onSpeed: (v) => setState(() => speed = v),
                      onAirport: (a) => setState(() {
                        selectedAirport = a;
                        mobileSearchOpen = false;
                      }),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOut,
                    top: compact ? 112 : 92,
                    bottom: 52,
                    right: 12,
                    width: compact ? constraints.maxWidth - 24 : 390,
                    child: _MainPanel(
                      panel: panel,
                      currency: currency,
                      onPanel: (p) => setState(() => panel = p),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOut,
                    left: selectedAirport == null ? -460 : 12,
                    top: compact ? 112 : 92,
                    bottom: 52,
                    width: compact ? constraints.maxWidth - 24 : 420,
                    child: selectedAirport == null
                        ? const SizedBox.shrink()
                        : _AirportPanel(
                            airport: selectedAirport!,
                            currency: currency,
                            onClose: () =>
                                setState(() => selectedAirport = null),
                          ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _Ticker(speed: speed),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _Panel { routes, fleet, finance, competitors }

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.compact,
    required this.currency,
    required this.speed,
    required this.searchOpen,
    required this.onToggleSearch,
    required this.onCurrency,
    required this.onSpeed,
    required this.onAirport,
  });
  final bool compact;
  final CurrencyOption currency;
  final int speed;
  final bool searchOpen;
  final VoidCallback onToggleSearch;
  final ValueChanged<CurrencyOption> onCurrency;
  final ValueChanged<int> onSpeed;
  final ValueChanged<Airport> onAirport;
  @override
  Widget build(BuildContext context) {
    final search = _SearchBox(onAirport: onAirport);
    return Container(
      color: const Color(0xee050915),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: [
              const _AirlineBadge(),
              const Spacer(),
              if (!compact) SizedBox(width: 320, child: search),
              if (compact)
                IconButton(
                  tooltip: 'Search airports',
                  onPressed: onToggleSearch,
                  icon: Icon(searchOpen ? Icons.close : Icons.search),
                ),
              const SizedBox(width: 8),
              DropdownButton<CurrencyOption>(
                value: currency,
                underline: const SizedBox.shrink(),
                items: currencyOptions
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.code)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onCurrency(v);
                },
              ),
              const SizedBox(width: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, icon: Icon(Icons.pause)),
                  ButtonSegment(value: 1, label: Text('1x')),
                  ButtonSegment(value: 3, label: Text('3x')),
                  ButtonSegment(value: 6, label: Text('6x')),
                ],
                selected: {speed},
                onSelectionChanged: (v) => onSpeed(v.first),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: compact && searchOpen
                ? Padding(padding: const EdgeInsets.only(top: 8), child: search)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _AirlineBadge extends StatelessWidget {
  const _AirlineBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xff111827),
      border: Border.all(color: const Color(0xff263247)),
      borderRadius: BorderRadius.circular(28),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.public, color: Color(0xff77c9ff)),
        SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mighty Airline Empire',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(r'$23.1M', style: TextStyle(color: Color(0xff3af083))),
          ],
        ),
      ],
    ),
  );
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onAirport});
  final ValueChanged<Airport> onAirport;
  @override
  Widget build(BuildContext context) => Autocomplete<Airport>(
    optionsBuilder: (value) => searchAirports(value.text, airports),
    displayStringForOption: (a) => '${a.iata} · ${a.city}',
    onSelected: onAirport,
    fieldViewBuilder: (context, controller, focus, submit) => TextField(
      controller: controller,
      focusNode: focus,
      decoration: InputDecoration(
        hintText: 'Search airports',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        filled: true,
        fillColor: const Color(0xff111827),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        color: const Color(0xff111827),
        borderRadius: BorderRadius.circular(12),
        elevation: 12,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340, maxHeight: 280),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final a = options.elementAt(index);
              return ListTile(
                dense: true,
                title: Text('${a.iata} · ${a.city}'),
                subtitle: Text('${a.name}, ${a.country}'),
                onTap: () => onSelected(a),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _WorldMap extends StatelessWidget {
  const _WorldMap({
    required this.selectedAirport,
    required this.onAirportSelected,
  });
  final Airport? selectedAirport;
  final ValueChanged<Airport> onAirportSelected;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (d) {
      final box = context.findRenderObject() as RenderBox;
      final airport = _nearestAirport(d.localPosition, box.size);
      if (airport != null) onAirportSelected(airport);
    },
    child: CustomPaint(
      painter: _MapPainter(selectedAirport: selectedAirport),
      child: const SizedBox.expand(),
    ),
  );
  Airport? _nearestAirport(Offset p, Size size) {
    Airport? best;
    var bestDistance = 999.0;
    for (final a in airports) {
      final d = (_airportPoint(a, size) - p).distance;
      final hit = a.size == AirportSize.small ? 8.0 : 14.0;
      if (d < hit && d < bestDistance) {
        best = a;
        bestDistance = d;
      }
    }
    return best;
  }
}

Offset _airportPoint(Airport a, Size size) => Offset(
  ((a.lon + 180) / 360) * size.width,
  ((85 - a.lat.clamp(-85.0, 85.0)) / 170) * size.height,
);

class _MapPainter extends CustomPainter {
  const _MapPainter({required this.selectedAirport});
  final Airport? selectedAirport;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff08111f),
    );
    final grid = Paint()
      ..color = const Color(0xff1f2b3d)
      ..strokeWidth = 1;
    for (var lon = -180; lon <= 180; lon += 30) {
      final x = ((lon + 180) / 360) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var lat = -60; lat <= 60; lat += 30) {
      final y = ((85 - lat) / 170) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (final a in airports) {
      final r = switch (a.size) {
        AirportSize.small => 1.5,
        AirportSize.medium => 2.1,
        AirportSize.large => 3.0,
        AirportSize.major => 4.2,
      };
      final selected = selectedAirport?.iata == a.iata;
      canvas.drawCircle(
        _airportPoint(a, size),
        selected ? r + 3 : r,
        Paint()
          ..color = selected
              ? const Color(0xffffd166)
              : const Color(0xff58a6ff),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.selectedAirport != selectedAirport;
}

class _AirportPanel extends StatelessWidget {
  const _AirportPanel({
    required this.airport,
    required this.currency,
    required this.onClose,
  });
  final Airport airport;
  final CurrencyOption currency;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final destinations =
        airports
            .where((a) => a.iata != airport.iata)
            .map(
              (a) => (airport: a, demand: baselineDailyPassengers(airport, a)),
            )
            .toList()
          ..sort((a, b) => b.demand.compareTo(a.demand));
    return _PanelShell(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        airport.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${airport.city}, ${airport.country}',
                        style: const TextStyle(color: Color(0xff9aa4b5)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  iconSize: 28,
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _InfoRow('IATA', airport.iata),
                _InfoRow('ICAO', airport.icao ?? '—'),
                _InfoRow('Size', airport.size.name),
                _InfoRow('Landing fee', money(airport.landingFee, currency)),
                _InfoRow(
                  'Runway',
                  airport.longestRunwayM == null
                      ? 'Unknown'
                      : '${airport.longestRunwayM} m',
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Passenger destinations',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  children: destinations
                      .take(15)
                      .map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${item.airport.iata} · ${item.airport.city}',
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${item.demand.round()} pax/d · ${item.airport.size.name}',
                          ),
                          trailing: const Icon(Icons.add_road),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.add),
                    label: const Text('New Route'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.apartment),
                    label: const Text('Set Hub'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MainPanel extends StatelessWidget {
  const _MainPanel({
    required this.panel,
    required this.currency,
    required this.onPanel,
  });
  final _Panel panel;
  final CurrencyOption currency;
  final ValueChanged<_Panel> onPanel;
  @override
  Widget build(BuildContext context) => _PanelShell(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<_Panel>(
            segments: const [
              ButtonSegment(value: _Panel.routes, label: Text('Routes')),
              ButtonSegment(value: _Panel.fleet, label: Text('Fleet')),
              ButtonSegment(value: _Panel.finance, label: Text('Finance')),
              ButtonSegment(value: _Panel.competitors, label: Text('Rivals')),
            ],
            selected: {panel},
            onSelectionChanged: (v) => onPanel(v.first),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: _cards(),
          ),
        ),
      ],
    ),
  );
  List<Widget> _cards() => switch (panel) {
    _Panel.routes => [
      _MetricCard('Active routes', '2', const Color(0xff77c9ff)),
      _MetricCard(
        'Optimiser status',
        'Dart engine scaffolded',
        const Color(0xff3af083),
      ),
    ],
    _Panel.fleet => [
      _MetricCard(
        'Aircraft catalogue',
        '${aircraftTypes.length} types',
        const Color(0xff77c9ff),
      ),
    ],
    _Panel.finance => [
      _MetricCard('Cash', money(23100000, currency), const Color(0xff3af083)),
      _MetricCard(
        '30-day profit',
        money(1840000, currency),
        const Color(0xff3af083),
      ),
    ],
    _Panel.competitors => [
      _MetricCard(
        'Competitors',
        'Ready for parity port',
        const Color(0xffffd166),
      ),
    ],
  };
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.title, this.value, this.accent);
  final String title;
  final String value;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xff151b2b),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xff273246)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Color(0xff9aa4b5))),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: accent,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xff9aa4b5))),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xee0b1020),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xff263247)),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 22)],
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
  );
}

class _Ticker extends StatelessWidget {
  const _Ticker({required this.speed});
  final int speed;
  @override
  Widget build(BuildContext context) => Container(
    height: 42,
    color: const Color(0xff050915),
    alignment: Alignment.centerLeft,
    child: TweenAnimationBuilder<double>(
      key: ValueKey(speed),
      tween: Tween(begin: 1, end: -1),
      duration: Duration(
        seconds: speed <= 1
            ? 24
            : speed == 3
            ? 16
            : 10,
      ),
      builder: (context, value, child) =>
          FractionalTranslation(translation: Offset(value, 0), child: child),
      child: const Text(
        '  ‼️ Native ticker sits above the map and below panels · Search airports from the main nav · Flutter parity port underway',
        maxLines: 1,
        style: TextStyle(color: Color(0xffc7d2e5), fontWeight: FontWeight.w700),
      ),
    ),
  );
}
