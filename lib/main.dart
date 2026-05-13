import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'core/airport_search.dart';
import 'core/constants.dart';
import 'core/format.dart';
import 'core/geo.dart';
import 'data/aircraft_types.dart';
import 'data/airports.dart';
import 'engine/demand_model.dart';
import 'engine/economics_engine.dart';
import 'engine/finance.dart';
import 'engine/hub_upgrades.dart';
import 'engine/route_optimizer.dart'
    show RouteOptimisationInput, optimiseRouteSettings;
import 'engine/valuation.dart';
import 'models/models.dart';
import 'state/game_controller.dart';

void main() => runApp(const MightyAirlineEmpireApp());

class MightyAirlineEmpireApp extends StatefulWidget {
  const MightyAirlineEmpireApp({super.key});
  @override
  State<MightyAirlineEmpireApp> createState() => _MightyAirlineEmpireAppState();
}

class _MightyAirlineEmpireAppState extends State<MightyAirlineEmpireApp> {
  late final GameController game;
  Timer? _gameLoop;
  DateTime? _lastTickAt;
  var currency = currencyOptions.first;
  Airport? selectedAirport = airportsByIata['LHR'];
  var panel = _Panel.routes;
  var mobileSearchOpen = false;
  var showAiOnMap = true;
  final _autoOpenedArticleIds = <String>{};

  @override
  void initState() {
    super.initState();
    game = GameController();
    _lastTickAt = DateTime.now();
    _gameLoop = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final now = DateTime.now();
      final previous = _lastTickAt ?? now;
      _lastTickAt = now;
      final delta = now.difference(previous);
      game.advanceGameClock(
        delta > const Duration(milliseconds: 500)
            ? const Duration(milliseconds: 500)
            : delta,
      );
    });
  }

  @override
  void dispose() {
    _gameLoop?.cancel();
    game.dispose();
    super.dispose();
  }

  void _openCreateRoute({Airport? origin, Airport? destination}) {
    showDialog<void>(
      context: context,
      builder: (context) => _CreateRouteDialog(
        game: game,
        currency: currency,
        origin: origin ?? selectedAirport,
        destination: destination,
      ),
    );
  }

  void _openRouteDetail(RoutePlan route) {
    if (game.airlines[route.airlineId]?.isPlayer == true) {
      showDialog<void>(
        context: context,
        builder: (context) =>
            _RouteEditDialog(game: game, route: route, currency: currency),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) =>
          _RouteSummaryDialog(game: game, route: route, currency: currency),
    );
  }

  void _scheduleHeraldAutoOpen(BuildContext context) {
    final article = game.nextAutoOpenArticle;
    if (article == null) {
      if (game.newspaperQueue.isEmpty) _autoOpenedArticleIds.clear();
      return;
    }
    if (_autoOpenedArticleIds.contains(article.id)) return;
    if (article.actionAircraftId == null) return;
    if (game.player.maintenancePolicy.autoMaintainIssues) return;
    _autoOpenedArticleIds.add(article.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !game.newsArticles.containsKey(article.id)) return;
      _showHeraldArticle(context, game, article);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: game,
      builder: (context, _) {
        final lightMode = game.themeMode == ThemeModeSetting.light;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Mighty Airline Empire',
          theme:
              (lightMode
                      ? ThemeData.light(useMaterial3: true)
                      : ThemeData.dark(useMaterial3: true))
                  .copyWith(
                    scaffoldBackgroundColor: lightMode
                        ? const Color(0xffeef2f7)
                        : const Color(0xff050915),
                    colorScheme: ColorScheme.fromSeed(
                      seedColor: const Color(0xff2f8cff),
                      brightness: lightMode
                          ? Brightness.light
                          : Brightness.dark,
                    ),
                  ),
          home: Scaffold(
            body: SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 980;
                  _scheduleHeraldAutoOpen(context);
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: _WorldMap(
                          game: game,
                          showAiOnMap: showAiOnMap,
                          selectedAirport: selectedAirport,
                          onAirportSelected: (a) =>
                              setState(() => selectedAirport = a),
                          onRouteSelected: _openRouteDetail,
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _TopBar(
                          game: game,
                          compact: compact,
                          currency: currency,
                          searchOpen: mobileSearchOpen,
                          onToggleSearch: () => setState(
                            () => mobileSearchOpen = !mobileSearchOpen,
                          ),
                          onCurrency: (v) => setState(() => currency = v),
                          onSpeed: (v) => game.setSpeed(v == 0 ? 0 : v * 300),
                          onAirport: (a) => setState(() {
                            selectedAirport = a;
                            mobileSearchOpen = false;
                          }),
                        ),
                      ),
                      Positioned(
                        top: compact ? 112 : 92,
                        left: 12,
                        child: _MapToggle(
                          showAi: showAiOnMap,
                          onChanged: (value) =>
                              setState(() => showAiOnMap = value),
                        ),
                      ),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeInOut,
                        top: compact ? 112 : 92,
                        bottom: 52,
                        right: 12,
                        width: compact ? constraints.maxWidth - 24 : 430,
                        child: _MainPanel(
                          game: game,
                          panel: panel,
                          currency: currency,
                          onPanel: (p) => setState(() => panel = p),
                          onCreateRoute: () => _openCreateRoute(),
                        ),
                      ),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeInOut,
                        left: selectedAirport == null ? -460 : 12,
                        top: compact ? 112 : 92,
                        bottom: 52,
                        width: compact ? constraints.maxWidth - 24 : 430,
                        child: selectedAirport == null
                            ? const SizedBox.shrink()
                            : _AirportPanel(
                                game: game,
                                airport: selectedAirport!,
                                currency: currency,
                                onClose: () =>
                                    setState(() => selectedAirport = null),
                                onCreateRoute: (origin, destination) =>
                                    _openCreateRoute(
                                      origin: origin,
                                      destination: destination,
                                    ),
                              ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _Ticker(game: game),
                      ),
                      if (game.hasWon || game.hasLost)
                        Positioned.fill(
                          child: _GameOutcomeOverlay(
                            game: game,
                            currency: currency,
                            onNewGame: () => _showNewGameDialog(
                              context,
                              game,
                              currency,
                              (v) => setState(() => currency = v),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _Panel { routes, fleet, finance, competitors, hubs }

class _GameOutcomeOverlay extends StatelessWidget {
  const _GameOutcomeOverlay({
    required this.game,
    required this.currency,
    required this.onNewGame,
  });

  final GameController game;
  final CurrencyOption currency;
  final VoidCallback onNewGame;

  @override
  Widget build(BuildContext context) {
    final won = game.hasWon;
    final player = game.player;
    final last = player.dailyStats.lastOrNull;
    final title = won ? 'Victory' : 'Game over';
    final currentYear = game.settings.startingYear + game.gameDay ~/ 365;
    final yearsOfOperation = math.max(
      0,
      currentYear - game.settings.startingYear,
    );
    final totalPassengers =
        player.totalPassengersAllTime +
        game.competitors.fold<int>(
          0,
          (sum, airline) => sum + airline.totalPassengersAllTime,
        );
    final allTimeMarketShare = totalPassengers <= 0
        ? 0.0
        : player.totalPassengersAllTime / totalPassengers * 100;
    final message = won
        ? game.settings.objective == GameObjective.marketShare
              ? 'You reached ${allTimeMarketShare.toStringAsFixed(1)}% all-time market share, beating the ${game.settings.targetMarketShare.round()}% target.'
              : 'Every rival airline has collapsed. You are the last airline standing.'
        : '${player.name} accumulated more than ${money(100000000, currency)} in debt and became insolvent.';
    return Material(
      color: Colors.black.withValues(alpha: 0.56),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.96, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) => Transform.scale(
            scale: scale,
            child: Opacity(opacity: scale.clamp(0, 1), child: child),
          ),
          child: Container(
            width: math.min(520, MediaQuery.sizeOf(context).width - 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xff0b1020),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 36,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      Icon(
                        won ? Icons.emoji_events : Icons.money_off,
                        size: 54,
                        color: won
                            ? const Color(0xffffd166)
                            : const Color(0xffff6b6b),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: won
                                  ? const Color(0xffffd166)
                                  : const Color(0xffff6b6b),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(
                        'Day ${game.gameDay} · $currentYear',
                        style: const TextStyle(color: Color(0xff9aa4b5)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _OutcomeStat(
                      label: 'Cash',
                      value: money(player.cashUSD, currency),
                      accent: player.cashUSD >= 0
                          ? const Color(0xff3af083)
                          : const Color(0xffff6b6b),
                    ),
                    _OutcomeStat(
                      label: 'Routes',
                      value: player.routeIds.length.toString(),
                    ),
                    _OutcomeStat(
                      label: 'Fleet',
                      value: player.fleetIds.length.toString(),
                    ),
                    _OutcomeStat(
                      label: 'Passengers',
                      value: _formatCount(player.totalPassengersAllTime),
                    ),
                    _OutcomeStat(
                      label: 'Market share',
                      value: '${allTimeMarketShare.toStringAsFixed(1)}%',
                    ),
                    _OutcomeStat(
                      label: 'Reputation',
                      value: '${player.reputationScore.toStringAsFixed(0)}/100',
                    ),
                    _OutcomeStat(
                      label: 'Years',
                      value:
                          '$yearsOfOperation yr${yearsOfOperation == 1 ? '' : 's'}',
                    ),
                    _OutcomeStat(
                      label: 'Last day',
                      value: money(
                        last?.profit ?? player.lastDailyProfit,
                        currency,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (won) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: game.dismissGameOutcome,
                          child: const Text('Continue Playing'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed: onNewGame,
                        child: const Text('Play Again'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutcomeStat extends StatelessWidget {
  const _OutcomeStat({required this.label, required this.value, this.accent});

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final muted = _mutedText(context);
    return SizedBox(
      width: 140,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _subtleSurface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hairline(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: muted)),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.game,
    required this.compact,
    required this.currency,
    required this.searchOpen,
    required this.onToggleSearch,
    required this.onCurrency,
    required this.onSpeed,
    required this.onAirport,
  });
  final GameController game;
  final bool compact;
  final CurrencyOption currency;
  final bool searchOpen;
  final VoidCallback onToggleSearch;
  final ValueChanged<CurrencyOption> onCurrency;
  final ValueChanged<int> onSpeed;
  final ValueChanged<Airport> onAirport;
  @override
  Widget build(BuildContext context) {
    final search = _SearchBox(onAirport: onAirport);
    final speedValue = game.speed == 0
        ? 0
        : (game.speed / 300).round().clamp(1, 6);
    return Container(
      decoration: BoxDecoration(
        color: _chromeSurface(context),
        border: Border(bottom: BorderSide(color: _hairline(context))),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: [
              _AirlineBadge(
                game: game,
                currency: currency,
                onCurrency: onCurrency,
              ),
              const SizedBox(width: 6),
              _GameMenu(game: game, currency: currency, onCurrency: onCurrency),
              const SizedBox(width: 12),
              _DateBadge(game: game),
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
                selected: {speedValue},
                onSelectionChanged: (v) => onSpeed(v.first),
              ),
              IconButton(
                tooltip: 'Advance day',
                onPressed: game.runDailyTick,
                icon: const Icon(Icons.skip_next),
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
  const _AirlineBadge({
    required this.game,
    required this.currency,
    required this.onCurrency,
  });
  final GameController game;
  final CurrencyOption currency;
  final ValueChanged<CurrencyOption> onCurrency;
  @override
  Widget build(BuildContext context) {
    final muted = _mutedText(context);
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () =>
          _showAirlineProfileDialog(context, game, currency, onCurrency),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _cardSurface(context),
          border: Border.all(color: _hairline(context)),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AirlineLogo(logo: game.player.logoEmoji, size: 34),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.player.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  money(game.player.cashUSD, currency),
                  style: TextStyle(
                    color: game.player.cashUSD >= 0
                        ? const Color(0xff25c96b)
                        : const Color(0xffff6b6b),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            Icon(Icons.expand_more, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}

void _showAirlineProfileDialog(
  BuildContext context,
  GameController game,
  CurrencyOption currency,
  ValueChanged<CurrencyOption> onCurrency,
) {
  final player = game.player;
  final fleet = game.playerFleet;
  final routes = game.playerRoutes;
  final activeRoutes = routes.where((route) => route.isActive).length;
  final inactiveRoutes = math.max(0, routes.length - activeRoutes);
  final idleAircraft = fleet
      .where((ac) => ac.status == AircraftStatus.idle)
      .length;
  final maintenanceAircraft = fleet
      .where((ac) => ac.status == AircraftStatus.maintenance)
      .length;
  final today = player.dailyStats.lastOrNull;
  final totalPassengers =
      player.totalPassengersAllTime +
      game.competitors.fold<int>(
        0,
        (sum, airline) => sum + airline.totalPassengersAllTime,
      );
  final allTimeShare = totalPassengers <= 0
      ? 0.0
      : player.totalPassengersAllTime / totalPassengers * 100;

  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          _AirlineLogo(logo: player.logoEmoji, size: 38),
          const SizedBox(width: 10),
          Expanded(child: Text(player.name)),
        ],
      ),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow('Cash', money(player.cashUSD, currency)),
                    if (player.totalDebt > 0)
                      _InfoRow('Debt', money(player.totalDebt, currency)),
                    _InfoRow(
                      'Reputation',
                      '${player.reputationScore.toStringAsFixed(0)}/100',
                    ),
                    _InfoRow(
                      'Market share',
                      '${player.marketSharePercent.toStringAsFixed(1)}%',
                    ),
                    _InfoRow(
                      'All-time share',
                      '${allTimeShare.toStringAsFixed(1)}%',
                    ),
                    _InfoRow(
                      'Passengers',
                      _formatCount(player.totalPassengersAllTime),
                    ),
                  ],
                ),
              ),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow('Fleet', '${fleet.length} aircraft'),
                    if (idleAircraft > 0)
                      _InfoRow('Idle aircraft', idleAircraft.toString()),
                    if (maintenanceAircraft > 0)
                      _InfoRow(
                        'In maintenance',
                        maintenanceAircraft.toString(),
                      ),
                    _InfoRow('Routes', '${routes.length} total'),
                    _InfoRow('Active routes', activeRoutes.toString()),
                    if (inactiveRoutes > 0)
                      _InfoRow('Inactive routes', inactiveRoutes.toString()),
                    _InfoRow(
                      'Hubs',
                      player.hubIatas.isEmpty
                          ? 'None'
                          : player.hubIatas.join(', '),
                    ),
                  ],
                ),
              ),
              if (today != null)
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Today's P&L",
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      _InfoRow('Revenue', money(today.revenue, currency)),
                      _InfoRow('Costs', money(today.costs, currency)),
                      _InfoRow('Profit', money(today.profit, currency)),
                      _InfoRow('Passengers', _formatCount(today.passengers)),
                    ],
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _showRebrandDialog(context, game, currency);
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Rebrand'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _showExportDialog(context, game);
                    },
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Export'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _showImportDialog(context, game, onCurrency);
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('Import'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _showSettingsDialog(context, game);
                    },
                    icon: const Icon(Icons.palette),
                    label: const Text('Theme'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _showNewGameDialog(context, game, currency, onCurrency);
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Start again'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

const _airlineLogoOptions = [
  '✈️',
  '🛫',
  '🛬',
  '🌍',
  '🌎',
  '🌏',
  '🌐',
  '⭐',
  '🌟',
  '🌙',
  '☀️',
  '⚡',
  '🔥',
  '💎',
  '🛡️',
  '🏔️',
  '🌊',
  '❄️',
  '🍁',
  '🚀',
];

bool _isImageLogo(String? logo) =>
    logo != null && logo.trim().startsWith('data:image/');

({String mimeType, Uint8List bytes})? _decodeImageLogo(String value) {
  final comma = value.indexOf(',');
  if (comma < 0) return null;
  final header = value.substring(5, comma).toLowerCase();
  final payload = value.substring(comma + 1);
  final mimeType = header.split(';').first;
  try {
    final bytes = header.contains(';base64')
        ? base64Decode(payload)
        : Uint8List.fromList(utf8.encode(Uri.decodeFull(payload)));
    return (mimeType: mimeType, bytes: bytes);
  } catch (_) {
    return null;
  }
}

String _mimeTypeForLogoFile(String name) {
  final extension = name.split('.').last.toLowerCase();
  return switch (extension) {
    'svg' => 'image/svg+xml',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => 'image/png',
  };
}

Future<String?> _pickAirlineLogoImage() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Images',
        extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'svg'],
        mimeTypes: [
          'image/png',
          'image/jpeg',
          'image/webp',
          'image/gif',
          'image/svg+xml',
        ],
      ),
    ],
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.lengthInBytes > 1500000) {
    throw StateError('Logo image must be smaller than 1.5 MB.');
  }
  return 'data:${_mimeTypeForLogoFile(file.name)};base64,${base64Encode(bytes)}';
}

class _AirlineLogo extends StatelessWidget {
  const _AirlineLogo({required this.logo, this.size = 28});

  final String? logo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = logo?.trim();
    if (_isImageLogo(value)) {
      final decoded = _decodeImageLogo(value!);
      if (decoded != null) {
        if (decoded.mimeType == 'image/svg+xml') {
          return ClipRRect(
            borderRadius: BorderRadius.circular(size / 4),
            child: SvgPicture.memory(
              decoded.bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 4),
          child: Image.memory(
            decoded.bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _TextLogo(value: '✈️', size: size),
          ),
        );
      }
    }
    return _TextLogo(
      value: value?.isEmpty == false ? value! : '✈️',
      size: size,
    );
  }
}

class _TextLogo extends StatelessWidget {
  const _TextLogo({required this.value, required this.size});

  final String value;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Center(
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(fontSize: size * 0.72, height: 1),
      ),
    ),
  );
}

class _LogoPicker extends StatelessWidget {
  const _LogoPicker({
    required this.value,
    required this.onChanged,
    required this.onUploadLogo,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onUploadLogo;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _airlineLogoOptions
            .map(
              (option) => InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(option),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: value == option
                        ? const Color(0xff2f8cff).withValues(alpha: 0.22)
                        : _subtleSurface(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: value == option
                          ? const Color(0xff77c9ff)
                          : _hairline(context),
                    ),
                  ),
                  child: Center(
                    child: Text(option, style: const TextStyle(fontSize: 20)),
                  ),
                ),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: onUploadLogo,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload logo'),
      ),
      const SizedBox(height: 8),
      Text(
        _isImageLogo(value)
            ? 'Custom image logo detected from imported save.'
            : 'Pick an emoji, type a short mark, or paste a data:image logo.',
        style: const TextStyle(color: Color(0xff9aa4b5), fontSize: 12),
      ),
    ],
  );
}

class _GameMenu extends StatelessWidget {
  const _GameMenu({
    required this.game,
    required this.currency,
    required this.onCurrency,
  });
  final GameController game;
  final CurrencyOption currency;
  final ValueChanged<CurrencyOption> onCurrency;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Game menu',
    icon: const Icon(Icons.more_horiz),
    onSelected: (value) {
      switch (value) {
        case 'export':
          _showExportDialog(context, game);
        case 'import':
          _showImportDialog(context, game, onCurrency);
        case 'rebrand':
          _showRebrandDialog(context, game, currency);
        case 'theme':
          _showSettingsDialog(context, game);
        case 'new':
          _showNewGameDialog(context, game, currency, onCurrency);
      }
    },
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'rebrand', child: Text('Rebrand airline')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'export', child: Text('Export progress')),
      PopupMenuItem(value: 'import', child: Text('Import progress')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'theme', child: Text('Theme')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'new', child: Text('Start again')),
    ],
  );
}

void _showSettingsDialog(BuildContext context, GameController game) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Appearance',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            _ThemeOption(
              label: 'Dark',
              description: 'Low-glare cockpit style for long play sessions.',
              selected: game.themeMode == ThemeModeSetting.dark,
              onTap: () {
                game.setThemeMode(ThemeModeSetting.dark);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 10),
            _ThemeOption(
              label: 'Light',
              description:
                  'Brighter interface for daylight and mobile screens.',
              selected: game.themeMode == ThemeModeSetting.light,
              onTap: () {
                game.setThemeMode(ThemeModeSetting.light);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xff2f8cff).withValues(alpha: 0.16)
            : _subtleSurface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? const Color(0xff77c9ff) : _hairline(context),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(color: Color(0xff9aa4b5)),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? const Color(0xff77c9ff) : null,
            ),
          ],
        ),
      ),
    ),
  );
}

const _brandColours = [
  '#3b82f6',
  '#14b8a6',
  '#ef4444',
  '#f59e0b',
  '#22c55e',
  '#8b5cf6',
  '#ec4899',
  '#64748b',
];

void _showRebrandDialog(
  BuildContext context,
  GameController game,
  CurrencyOption currency,
) {
  final nameController = TextEditingController(text: game.player.name);
  final logoController = TextEditingController(text: game.player.logoEmoji);
  var colour = game.player.color;
  String? error;

  showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final name = nameController.text.trim();
        final logo = logoController.text.trim();
        final cost = game.rebrandCost(
          name: name,
          color: colour,
          logoEmoji: logo,
        );
        final hasChange = cost > 0;
        return AlertDialog(
          title: const Text('Rebrand airline'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Card(
                    child: Row(
                      children: [
                        _AirlineLogo(
                          logo: logo.isEmpty ? game.player.logoEmoji : logo,
                          size: 46,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.isEmpty ? game.player.name : name,
                                style: TextStyle(
                                  color: _MapPainter._colorFromHex(colour),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                'Company value ${money(game.playerCompanyValue(), currency)}',
                                style: const TextStyle(
                                  color: Color(0xff9aa4b5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Airline name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() => error = null),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: logoController,
                    decoration: const InputDecoration(
                      labelText: 'Logo emoji, short mark, or data:image',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() => error = null),
                  ),
                  const SizedBox(height: 8),
                  _LogoPicker(
                    value: logo,
                    onChanged: (value) {
                      logoController.text = value;
                      setState(() => error = null);
                    },
                    onUploadLogo: () async {
                      try {
                        final uploaded = await _pickAirlineLogoImage();
                        if (!context.mounted || uploaded == null) return;
                        logoController.text = uploaded;
                        setState(() => error = null);
                      } catch (e) {
                        if (!context.mounted) return;
                        setState(() => error = e.toString());
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _brandColours
                        .map(
                          (candidate) => Tooltip(
                            message: candidate,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => setState(() => colour = candidate),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _MapPainter._colorFromHex(candidate),
                                  border: Border.all(
                                    color: colour == candidate
                                        ? Colors.white
                                        : const Color(0xff263247),
                                    width: colour == candidate ? 3 : 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    hasChange ? 'Cost: ${money(cost, currency)}' : 'No changes',
                    style: TextStyle(
                      color: hasChange
                          ? const Color(0xffffd166)
                          : const Color(0xff9aa4b5),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Color(0xffff6b6b)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: !hasChange || game.player.cashUSD < cost
                  ? null
                  : () {
                      try {
                        game.rebrandAirline(
                          name: name,
                          color: colour,
                          logoEmoji: logo,
                        );
                        Navigator.pop(context);
                      } catch (e) {
                        setState(() => error = e.toString());
                      }
                    },
              child: Text(
                hasChange ? 'Confirm ${money(cost, currency)}' : 'No changes',
              ),
            ),
          ],
        );
      },
    ),
  );
}

void _showNewGameDialog(
  BuildContext context,
  GameController game,
  CurrencyOption currentCurrency,
  ValueChanged<CurrencyOption> onCurrency,
) {
  final nameController = TextEditingController(
    text: game.settings.playerAirlineName,
  );
  final emojiController = TextEditingController(
    text: game.settings.playerAirlineEmoji,
  );
  final colorController = TextEditingController(
    text: game.settings.playerAirlineColor,
  );
  var startingHub =
      game.airportByIata(game.settings.startingHubIata) ??
      airportsByIata['LHR']!;
  var startingYear = game.settings.startingYear;
  var difficulty = game.settings.difficulty;
  var aiCount = game.settings.aiCount.clamp(0, 12).toInt();
  var objective = game.settings.objective;
  var targetMarketShare = game.settings.targetMarketShare
      .clamp(60, 100)
      .toDouble();
  var selectedCurrency = currencyOptions.firstWhere(
    (option) => option.code == game.settings.currency,
    orElse: () => currentCurrency,
  );
  String? error;
  final startingCashByDifficulty = {
    Difficulty.easy: 50000000.0,
    Difficulty.normal: 30000000.0,
    Difficulty.hard: 15000000.0,
  };

  showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final startingCash = startingCashByDifficulty[difficulty]!;
        final availableAircraft = aircraftTypes
            .where((type) => type.yearIntroduced <= startingYear)
            .length;
        final era = _newGameEras.firstWhere(
          (era) => era.year == startingYear,
          orElse: () => _newGameEras.first,
        );
        final selectedColor = _normaliseHexColor(colorController.text);
        return AlertDialog(
          title: const Text('Start new airline'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Airline name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Airline colour',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _airlineColorOptions
                        .map(
                          (color) => InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () {
                              colorController.text = color;
                              setState(() {});
                            },
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: _MapPainter._colorFromHex(color),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selectedColor == color.toLowerCase()
                                      ? Theme.of(context).colorScheme.primary
                                      : _hairline(context),
                                  width: selectedColor == color.toLowerCase()
                                      ? 3
                                      : 1,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: colorController,
                    decoration: const InputDecoration(
                      labelText: 'Custom colour',
                      hintText: '#3b82f6',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _AirlineLogo(
                        logo: emojiController.text.trim().isEmpty
                            ? '✈️'
                            : emojiController.text.trim(),
                        size: 46,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: emojiController,
                          decoration: const InputDecoration(
                            labelText: 'Logo emoji, short mark, or data:image',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _LogoPicker(
                    value: emojiController.text.trim(),
                    onChanged: (value) {
                      emojiController.text = value;
                      setState(() {});
                    },
                    onUploadLogo: () async {
                      try {
                        final uploaded = await _pickAirlineLogoImage();
                        if (!context.mounted || uploaded == null) return;
                        emojiController.text = uploaded;
                        setState(() => error = null);
                      } catch (e) {
                        if (!context.mounted) return;
                        setState(() => error = e.toString());
                      }
                    },
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Color(0xffff6b6b)),
                      ),
                    ),
                  const SizedBox(height: 16),
                  _AirportDropdown(
                    label: 'Starting hub',
                    value: startingHub,
                    onChanged: (airport) =>
                        setState(() => startingHub = airport),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Starting era',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _newGameEras
                        .map(
                          (option) => ChoiceChip(
                            label: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  option.year.toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  option.label,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                            selected: startingYear == option.year,
                            onSelected: (_) =>
                                setState(() => startingYear = option.year),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$availableAircraft aircraft available · ${era.flagship}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: _mutedText(context)),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Difficulty>(
                    initialValue: difficulty,
                    decoration: const InputDecoration(
                      labelText: 'Difficulty',
                      border: OutlineInputBorder(),
                    ),
                    items: Difficulty.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              '${value.name[0].toUpperCase()}${value.name.substring(1)} · ${money(startingCashByDifficulty[value]!, selectedCurrency)}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => difficulty = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('AI airlines: $aiCount'),
                  Slider(
                    value: aiCount.toDouble(),
                    min: 0,
                    max: 12,
                    divisions: 12,
                    label: '$aiCount',
                    onChanged: (value) =>
                        setState(() => aiCount = value.round()),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<GameObjective>(
                    segments: const [
                      ButtonSegment(
                        value: GameObjective.lastAirlineStanding,
                        label: Text('Last airline standing'),
                      ),
                      ButtonSegment(
                        value: GameObjective.marketShare,
                        label: Text('Market share'),
                      ),
                    ],
                    selected: {objective},
                    onSelectionChanged: (value) =>
                        setState(() => objective = value.first),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: objective == GameObjective.marketShare
                        ? Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Target market share: ${targetMarketShare.round()}%',
                                ),
                                Slider(
                                  value: targetMarketShare.toDouble(),
                                  min: 60,
                                  max: 100,
                                  divisions: 40,
                                  label: '${targetMarketShare.round()}%',
                                  onChanged: (value) => setState(
                                    () => targetMarketShare = value
                                        .roundToDouble(),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<CurrencyOption>(
                    initialValue: selectedCurrency,
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      border: OutlineInputBorder(),
                    ),
                    items: currencyOptions
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('${value.code} · ${value.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedCurrency = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Starting cash: ${money(startingCash, selectedCurrency)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final name = nameController.text.trim();
                final emoji = emojiController.text.trim();
                game.startNewGame(
                  game.settings.copyWith(
                    playerAirlineName: name.isEmpty ? 'My Airline' : name,
                    playerAirlineColor:
                        _normaliseHexColor(colorController.text) ?? '#3b82f6',
                    playerAirlineEmoji: emoji.isEmpty ? '✈️' : emoji,
                    startingHubIata: startingHub.iata,
                    difficulty: difficulty,
                    startingCash: startingCash,
                    aiCount: aiCount,
                    startingYear: startingYear,
                    objective: objective,
                    targetMarketShare: targetMarketShare,
                    currency: selectedCurrency.code,
                  ),
                );
                onCurrency(selectedCurrency);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.flight_takeoff),
              label: const Text('Start'),
            ),
          ],
        );
      },
    ),
  );
}

class _NewGameEra {
  const _NewGameEra(this.year, this.label, this.flagship);
  final int year;
  final String label;
  final String flagship;
}

const _newGameEras = [
  _NewGameEra(1960, 'Jet Age', '707, DC-8, Il-18'),
  _NewGameEra(1970, 'Wide-body', '747, DC-10, Il-62'),
  _NewGameEra(1980, 'Glass cockpit', '757, 767, A300'),
  _NewGameEra(1990, 'FBW era', 'A320, 777, A330'),
  _NewGameEra(2000, 'Low-cost boom', '737NG, A319/320/321'),
  _NewGameEra(2010, 'Composite', '787, A380, A350'),
  _NewGameEra(2020, 'New gen', 'MAX, NEO, 777X'),
];

const _airlineColorOptions = [
  '#3b82f6',
  '#14b8a6',
  '#22c55e',
  '#f59e0b',
  '#ef4444',
  '#ec4899',
  '#8b5cf6',
  '#06b6d4',
  '#84cc16',
  '#f97316',
  '#64748b',
  '#111827',
];

String? _normaliseHexColor(String value) {
  final trimmed = value.trim();
  final match = RegExp(r'^#?[0-9a-fA-F]{6}$').firstMatch(trimmed);
  if (match == null) return null;
  final withHash = trimmed.startsWith('#') ? trimmed : '#$trimmed';
  return withHash.toLowerCase();
}

String _fileSafeName(String name) {
  final safe = name
      .trim()
      .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '')
      .toLowerCase();
  return safe.isEmpty ? 'airline' : safe;
}

const _jsonTypeGroup = XTypeGroup(
  label: 'JSON',
  extensions: ['json'],
  mimeTypes: ['application/json'],
);

Future<void> _saveProgressFile(
  BuildContext context,
  GameController game,
) async {
  final fileName =
      '${_fileSafeName(game.player.name)}-day-${game.gameDay}-progress.json';
  final location = await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: const [_jsonTypeGroup],
  );
  if (location == null) return;
  final file = XFile.fromData(
    Uint8List.fromList(utf8.encode(game.exportProgressJson())),
    mimeType: 'application/json',
    name: fileName,
  );
  await file.saveTo(location.path);
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Progress saved to $fileName')));
}

Future<String?> _openProgressFile() async {
  final file = await openFile(acceptedTypeGroups: const [_jsonTypeGroup]);
  if (file == null) return null;
  return file.readAsString();
}

void _applyImportedJson(
  GameController game,
  String rawJson,
  ValueChanged<CurrencyOption> onCurrency,
) {
  game.importJson(rawJson);
  final importedCurrency = currencyOptions.firstWhere(
    (option) => option.code == game.settings.currency,
    orElse: () => currencyOptions.first,
  );
  onCurrency(importedCurrency);
}

void _showExportDialog(BuildContext context, GameController game) {
  final json = game.exportProgressJson();
  final controller = TextEditingController(text: json);
  var saving = false;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Export progress'),
        content: SizedBox(
          width: 620,
          child: TextField(
            controller: controller,
            readOnly: true,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          OutlinedButton.icon(
            onPressed: saving
                ? null
                : () async {
                    setState(() => saving = true);
                    try {
                      await _saveProgressFile(context, game);
                    } finally {
                      if (dialogContext.mounted) {
                        setState(() => saving = false);
                      }
                    }
                  },
            icon: const Icon(Icons.save_alt),
            label: Text(saving ? 'Saving...' : 'Save file'),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Progress JSON copied')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
        ],
      ),
    ),
  );
}

void _showImportDialog(
  BuildContext context,
  GameController game,
  ValueChanged<CurrencyOption> onCurrency,
) {
  final controller = TextEditingController();
  String? error;
  var openingFile = false;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Import progress'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                minLines: 8,
                maxLines: 14,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Paste exported JSON',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xffff6b6b)),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          OutlinedButton.icon(
            onPressed: openingFile
                ? null
                : () async {
                    setState(() {
                      openingFile = true;
                      error = null;
                    });
                    try {
                      final rawJson = await _openProgressFile();
                      if (rawJson == null) return;
                      _applyImportedJson(game, rawJson, onCurrency);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } catch (_) {
                      if (dialogContext.mounted) {
                        setState(
                          () => error = 'Could not import that save file.',
                        );
                      }
                    } finally {
                      if (dialogContext.mounted) {
                        setState(() => openingFile = false);
                      }
                    }
                  },
            icon: const Icon(Icons.folder_open),
            label: Text(openingFile ? 'Opening...' : 'Open file'),
          ),
          FilledButton(
            onPressed: () {
              try {
                _applyImportedJson(game, controller.text, onCurrency);
                Navigator.pop(dialogContext);
              } catch (_) {
                setState(() => error = 'Could not import that save JSON.');
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    ),
  );
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.game});
  final GameController game;
  @override
  Widget build(BuildContext context) {
    final year = game.settings.startingYear + game.gameDay ~/ 365;
    final day = game.gameDay % 365 + 1;
    final dayMs = game.gameTimeMs % gameDayMs;
    final hour = (dayMs ~/ 3600000).toString().padLeft(2, '0');
    final minute = ((dayMs % 3600000) ~/ 60000).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xff111827),
        border: Border.all(color: const Color(0xff263247)),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        'Day $day, $year · $hour:$minute',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
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

class _MapToggle extends StatelessWidget {
  const _MapToggle({required this.showAi, required this.onChanged});
  final bool showAi;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xee0b1020),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xff263247)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Show AI on map',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          Switch(value: showAi, onChanged: onChanged),
        ],
      ),
    ),
  );
}

class _WorldMap extends StatelessWidget {
  const _WorldMap({
    required this.game,
    required this.showAiOnMap,
    required this.selectedAirport,
    required this.onAirportSelected,
    required this.onRouteSelected,
  });
  final GameController game;
  final bool showAiOnMap;
  final Airport? selectedAirport;
  final ValueChanged<Airport> onAirportSelected;
  final ValueChanged<RoutePlan> onRouteSelected;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (d) {
      final box = context.findRenderObject() as RenderBox;
      final airport = _nearestAirport(d.localPosition, box.size);
      if (airport != null) {
        onAirportSelected(airport);
        return;
      }
      final route = _nearestRoute(d.localPosition, box.size);
      if (route != null) onRouteSelected(route);
    },
    child: CustomPaint(
      painter: _MapPainter(
        game: game,
        showAiOnMap: showAiOnMap,
        selectedAirport: selectedAirport,
      ),
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

  RoutePlan? _nearestRoute(Offset p, Size size) {
    RoutePlan? best;
    var bestDistance = 999.0;
    final drawableRoutes = game.routes.values.where((route) {
      if (!route.isActive || route.aircraftId == null) return false;
      if (showAiOnMap) return true;
      return game.airlines[route.airlineId]?.isPlayer == true;
    });
    for (final route in drawableRoutes) {
      final origin = airportsByIata[route.originIata];
      final dest = airportsByIata[route.destinationIata];
      if (origin == null || dest == null) continue;
      final start = _airportPoint(origin, size);
      final end = _airportPoint(dest, size);
      final control = _routeControlPoint(start, end);
      var routeDistance = 999.0;
      var previous = start;
      for (var i = 1; i <= 24; i++) {
        final point = _quadraticPoint(start, control, end, i / 24);
        routeDistance = math.min(
          routeDistance,
          _distanceToSegment(p, previous, point),
        );
        previous = point;
      }
      if (routeDistance < 18 && routeDistance < bestDistance) {
        best = route;
        bestDistance = routeDistance;
      }
    }
    return best;
  }
}

Offset _airportPoint(Airport a, Size size) => Offset(
  ((a.lon + 180) / 360) * size.width,
  ((85 - a.lat.clamp(-85.0, 85.0)) / 170) * size.height,
);

Offset _routeControlPoint(Offset start, Offset end) {
  final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
  final lift = ((end - start).distance * 0.12).clamp(16, 80).toDouble();
  return Offset(mid.dx, mid.dy - lift);
}

Offset _quadraticPoint(Offset a, Offset b, Offset c, double t) {
  final u = 1 - t;
  return Offset(
    u * u * a.dx + 2 * u * t * b.dx + t * t * c.dx,
    u * u * a.dy + 2 * u * t * b.dy + t * t * c.dy,
  );
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSquared)
      .clamp(0.0, 1.0);
  final projection = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  return (p - projection).distance;
}

class _MapPainter extends CustomPainter {
  const _MapPainter({
    required this.game,
    required this.showAiOnMap,
    required this.selectedAirport,
  });
  final GameController game;
  final bool showAiOnMap;
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
    final routePaint = Paint()
      ..color = const Color(0xff2f8cff).withValues(alpha: 0.45)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final drawableRoutes = game.routes.values.where((route) {
      if (!route.isActive || route.aircraftId == null) return false;
      if (showAiOnMap) return true;
      return game.airlines[route.airlineId]?.isPlayer == true;
    }).toList();
    for (final route in drawableRoutes) {
      final origin = airportsByIata[route.originIata];
      final dest = airportsByIata[route.destinationIata];
      if (origin == null || dest == null) continue;
      final start = _airportPoint(origin, size);
      final end = _airportPoint(dest, size);
      final control = _routeControlPoint(start, end);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      final airline = game.airlines[route.airlineId];
      canvas.drawPath(
        path,
        routePaint
          ..color = _colorFromHex(
            airline?.color ?? '#2f8cff',
          ).withValues(alpha: airline?.isPlayer == true ? 0.62 : 0.32),
      );
    }
    for (final route in drawableRoutes) {
      _drawPlane(canvas, size, route);
    }
    for (final a in airports) {
      final airport = game.airportByIata(a.iata) ?? a;
      final closedUntil = airport.closedUntilGameDay;
      final isClosed = closedUntil != null && closedUntil >= game.gameDay;
      final r = switch (a.size) {
        AirportSize.small => 1.5,
        AirportSize.medium => 2.1,
        AirportSize.large => 3.0,
        AirportSize.major => 4.2,
      };
      final selected = selectedAirport?.iata == a.iata;
      final point = _airportPoint(a, size);
      if (isClosed) {
        canvas.drawCircle(
          point,
          r + 4,
          Paint()
            ..color = const Color(0xffff6b6b).withValues(alpha: 0.88)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      canvas.drawCircle(
        point,
        selected ? r + 3 : r,
        Paint()
          ..color = selected
              ? const Color(0xffffd166)
              : isClosed
              ? const Color(0xffff6b6b)
              : const Color(0xff58a6ff),
      );
    }
  }

  void _drawPlane(Canvas canvas, Size size, RoutePlan route) {
    final ac = game.aircraft[route.aircraftId];
    if (ac == null ||
        ac.isGrounded ||
        ac.status == AircraftStatus.maintenance ||
        ac.status == AircraftStatus.crashed)
      return;
    final origin = airportsByIata[route.originIata];
    final dest = airportsByIata[route.destinationIata];
    if (origin == null || dest == null) return;
    final start = _airportPoint(origin, size);
    final end = _airportPoint(dest, size);
    final control = _routeControlPoint(start, end);
    final cycle = (ac.flightProgress * 2).clamp(0, 2).toDouble();
    final t = cycle <= 1 ? cycle : 2 - cycle;
    final from = cycle <= 1 ? start : end;
    final to = cycle <= 1 ? end : start;
    final controlPoint = control;
    final point = _quadraticPoint(from, controlPoint, to, t);
    final tangent = _quadraticTangent(from, controlPoint, to, t);
    final angle = math.atan2(tangent.dy, tangent.dx);
    final airline = game.airlines[route.airlineId];
    final color = _colorFromHex(airline?.color ?? '#ffffff');
    final type = aircraftTypesById[ac.typeId];
    final sizePx = switch (type?.category) {
      AircraftCategory.regional => 8.0,
      AircraftCategory.narrowbody => 10.0,
      AircraftCategory.widebody => 13.0,
      AircraftCategory.sst => 12.0,
      null => 10.0,
    };
    canvas.save();
    canvas.translate(point.dx, point.dy);
    canvas.rotate(angle);
    final paint = Paint()..color = color;
    final outline = Paint()
      ..color = const Color(0xff050915)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final plane = Path()
      ..moveTo(sizePx, 0)
      ..lineTo(-sizePx * 0.75, -sizePx * 0.45)
      ..lineTo(-sizePx * 0.35, 0)
      ..lineTo(-sizePx * 0.75, sizePx * 0.45)
      ..close();
    canvas.drawPath(plane, outline);
    canvas.drawPath(plane, paint);
    canvas.restore();
  }

  Offset _quadraticPoint(Offset a, Offset b, Offset c, double t) {
    final u = 1 - t;
    return Offset(
      u * u * a.dx + 2 * u * t * b.dx + t * t * c.dx,
      u * u * a.dy + 2 * u * t * b.dy + t * t * c.dy,
    );
  }

  Offset _quadraticTangent(Offset a, Offset b, Offset c, double t) => Offset(
    2 * (1 - t) * (b.dx - a.dx) + 2 * t * (c.dx - b.dx),
    2 * (1 - t) * (b.dy - a.dy) + 2 * t * (c.dy - b.dy),
  );

  static Color _colorFromHex(String hex) {
    final clean = hex.replaceFirst('#', '');
    final value =
        int.tryParse(clean.length == 6 ? 'ff$clean' : clean, radix: 16) ??
        0xffffffff;
    return Color(value);
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
}

class _AirportPanel extends StatelessWidget {
  const _AirportPanel({
    required this.game,
    required this.airport,
    required this.currency,
    required this.onClose,
    required this.onCreateRoute,
  });
  final GameController game;
  final Airport airport;
  final CurrencyOption currency;
  final VoidCallback onClose;
  final void Function(Airport origin, Airport? destination) onCreateRoute;
  @override
  Widget build(BuildContext context) {
    final airport = game.airportByIata(this.airport.iata) ?? this.airport;
    final isPlayerHub = game.player.hubIatas.contains(airport.iata);
    final terminalCost = getHubTerminalUpgradeCost(airport);
    final loungeCost = getFirstClassLoungeUpgradeCost(airport);
    final currentYear = game.settings.startingYear + game.gameDay ~/ 365;
    final dailyPax = game.routes.values
        .where(
          (route) =>
              route.isActive &&
              (route.originIata == airport.iata ||
                  route.destinationIata == airport.iata),
        )
        .fold<int>(0, (total, route) => total + route.dailyPassengers);
    final capacity = getAirportCapacity(airport, currentYear);
    final utilization = capacity <= 0 ? 0.0 : dailyPax / capacity;
    final demandPct = (airportSaturationMod(utilization) * 100).round();
    final utilizationPct = (utilization * 100).round();
    final closedUntil = airport.closedUntilGameDay;
    final isClosed = closedUntil != null && closedUntil >= game.gameDay;
    final destinations =
        game.airportList
            .where((a) => a.iata != airport.iata)
            .map((a) {
              final demand = baselineDailyPassengers(airport, a);
              final distanceKm = haversineKm(
                airport.lat,
                airport.lon,
                a.lat,
                a.lon,
              );
              final bestRoute = game.routes.values
                  .where(
                    (route) =>
                        route.isActive &&
                        ((route.originIata == airport.iata &&
                                route.destinationIata == a.iata) ||
                            (route.originIata == a.iata &&
                                route.destinationIata == airport.iata)),
                  )
                  .fold<RoutePlan?>(
                    null,
                    (best, route) =>
                        best == null || route.dailyProfit > best.dailyProfit
                        ? route
                        : best,
                  );
              final distanceYield =
                  150 + math.sqrt(math.max(250, distanceKm)) * 18;
              final potentialValue = demand * distanceYield;
              return (
                airport: a,
                demand: demand,
                distanceKm: distanceKm,
                bestRoute: bestRoute,
                potentialValue: potentialValue,
                score: bestRoute?.dailyProfit ?? potentialValue,
              );
            })
            .where((item) => item.demand >= 1)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
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
                _InfoRow('ICAO', airport.icao ?? '-'),
                _InfoRow('Size', airport.size.name),
                _InfoRow(
                  'Status',
                  isClosed
                      ? 'Closed: ${airport.closureReason ?? 'Operational disruption'} until day $closedUntil'
                      : 'Open',
                ),
                _InfoRow('Hub', isPlayerHub ? 'Yes' : 'No'),
                if (isClosed) ...[
                  const SizedBox(height: 10),
                  _Card(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          color: Color(0xffffb020),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Routes using ${airport.iata} will earn no revenue until operations reopen.',
                            style: const TextStyle(
                              color: Color(0xffffd166),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isPlayerHub)
                  _InfoRow(
                    'Terminal',
                    '${getHubTerminalLevel(airport)}/$maxHubTerminalLevel',
                  ),
                if (isPlayerHub)
                  _InfoRow(
                    'First class lounges',
                    '${getFirstClassLoungeLevel(airport)}/$maxFirstClassLoungeLevel',
                  ),
                _InfoRow('Landing fee', money(airport.landingFee, currency)),
                _InfoRow(
                  'Runway',
                  airport.longestRunwayM == null
                      ? 'Unknown'
                      : '${airport.longestRunwayM} m',
                ),
                const SizedBox(height: 14),
                _AirportMetricBar(
                  label: 'Demand strength',
                  percent: demandPct,
                  color: const Color(0xff2bd46f),
                ),
                const SizedBox(height: 14),
                _AirportMetricBar(
                  label: 'Airport utilisation',
                  percent: utilizationPct,
                  color: utilizationPct > 100
                      ? const Color(0xffff6b6b)
                      : const Color(0xff2bd46f),
                ),
                if (isPlayerHub) ...[
                  const SizedBox(height: 12),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Hub upgrades',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Terminals increase airport capacity. Lounges increase route demand.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xff9aa4b5)),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed:
                              terminalCost == null ||
                                  game.player.cashUSD < terminalCost
                              ? null
                              : () => game.upgradeHubTerminal(airport.iata),
                          icon: const Icon(Icons.apartment),
                          label: Text(
                            terminalCost == null
                                ? 'Terminal maxed'
                                : 'Upgrade terminal ${money(terminalCost, currency)}',
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed:
                              loungeCost == null ||
                                  game.player.cashUSD < loungeCost
                              ? null
                              : () =>
                                    game.upgradeFirstClassLounge(airport.iata),
                          icon: const Icon(Icons.airline_seat_recline_extra),
                          label: Text(
                            loungeCost == null
                                ? 'Lounges maxed'
                                : 'Upgrade lounges ${money(loungeCost, currency)}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Passenger destinations',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 620 ? 2 : 1;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 10) /
                            columns;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: destinations
                              .take(15)
                              .map(
                                (item) => SizedBox(
                                  width: width,
                                  child: _AirportDestinationCard(
                                    airport: item.airport,
                                    demand: item.demand,
                                    distanceKm: item.distanceKm,
                                    value:
                                        item.bestRoute?.dailyProfit ??
                                        item.potentialValue,
                                    isLiveRoute: item.bestRoute != null,
                                    currency: currency,
                                    onTap: () =>
                                        onCreateRoute(airport, item.airport),
                                  ),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ],
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
                    onPressed: () => onCreateRoute(airport, null),
                    icon: const Icon(Icons.add),
                    label: const Text('New Route'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isPlayerHub
                        ? game.player.hubIatas.length <= 1
                              ? null
                              : () => game.removePlayerHub(airport.iata)
                        : () => game.setPlayerHub(airport.iata),
                    icon: Icon(
                      isPlayerHub
                          ? Icons.remove_circle_outline
                          : Icons.apartment,
                    ),
                    label: Text(isPlayerHub ? 'Remove Hub' : 'Set Hub'),
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

class _AirportMetricBar extends StatelessWidget {
  const _AirportMetricBar({
    required this.label,
    required this.percent,
    required this.color,
  });

  final String label;
  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final shown = percent.clamp(0, 160);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xff9aa4b5),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$percent%',
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 9,
            value: math.min(1, shown / 100),
            color: color,
            backgroundColor: const Color(0xff293244),
          ),
        ),
      ],
    );
  }
}

class _AirportDestinationCard extends StatelessWidget {
  const _AirportDestinationCard({
    required this.airport,
    required this.demand,
    required this.distanceKm,
    required this.value,
    required this.isLiveRoute,
    required this.currency,
    required this.onTap,
  });

  final Airport airport;
  final double demand;
  final double distanceKm;
  final double value;
  final bool isLiveRoute;
  final CurrencyOption currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff151b2b),
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${airport.iata} · ${airport.city}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${demand.round()} pax/d',
                  style: const TextStyle(
                    color: Color(0xff6ed4ff),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_distanceLabel(distanceKm)} · ${airport.size.name}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xff8b95a8)),
                  ),
                ),
                Text(
                  '${money(value, currency)}/d ${isLiveRoute ? 'live' : 'potential'}',
                  style: const TextStyle(
                    color: Color(0xff8b95a8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

String _distanceLabel(double km) =>
    km >= 1000 ? '${(km / 1000).toStringAsFixed(1)}k km' : '${km.round()} km';

class _MainPanel extends StatelessWidget {
  const _MainPanel({
    required this.game,
    required this.panel,
    required this.currency,
    required this.onPanel,
    required this.onCreateRoute,
  });
  final GameController game;
  final _Panel panel;
  final CurrencyOption currency;
  final ValueChanged<_Panel> onPanel;
  final VoidCallback onCreateRoute;
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
              ButtonSegment(value: _Panel.hubs, label: Text('Hubs')),
            ],
            selected: {panel},
            onSelectionChanged: (v) => onPanel(v.first),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (panel) {
            _Panel.routes => _RoutesView(
              game: game,
              currency: currency,
              onCreateRoute: onCreateRoute,
            ),
            _Panel.fleet => _FleetView(game: game, currency: currency),
            _Panel.finance => _FinanceView(game: game, currency: currency),
            _Panel.competitors => _CompetitorsView(
              game: game,
              currency: currency,
            ),
            _Panel.hubs => _HubsView(game: game, currency: currency),
          },
        ),
      ],
    ),
  );
}

class _RoutesView extends StatelessWidget {
  const _RoutesView({
    required this.game,
    required this.currency,
    required this.onCreateRoute,
  });
  final GameController game;
  final CurrencyOption currency;
  final VoidCallback onCreateRoute;
  @override
  Widget build(BuildContext context) {
    final routes = game.playerRoutes;
    final optimisation = game.previewNetworkOptimisation();
    final canOptimiseAll =
        optimisation.hasChanges && game.player.cashUSD >= optimisation.costUSD;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onCreateRoute,
                icon: const Icon(Icons.add_road),
                label: const Text('New Route'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _MetricCard(
          'Daily route profit',
          money(
            routes.fold<double>(0, (sum, route) => sum + route.dailyProfit),
            currency,
          ),
          const Color(0xff3af083),
        ),
        if (routes.isNotEmpty)
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Network optimiser',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: 4),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: canOptimiseAll
                          ? game.optimiseAllPlayerRoutes
                          : null,
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Optimise all'),
                    ),
                  ],
                ),
                Text(
                  optimisation.eligibleCount == 0
                      ? 'Assign aircraft to routes before optimising.'
                      : optimisation.optimisableCount == 0
                      ? 'All eligible routes are already optimised.'
                      : '${optimisation.optimisableCount} routes can improve · ${money(optimisation.costUSD, currency)} consulting fee',
                  style: const TextStyle(color: Color(0xff9aa4b5)),
                ),
                if (optimisation.hasChanges &&
                    game.player.cashUSD < optimisation.costUSD)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Need ${money(optimisation.costUSD - game.player.cashUSD, currency)} more cash.',
                      style: const TextStyle(color: Color(0xffff6b6b)),
                    ),
                  ),
              ],
            ),
          ),
        if (routes.isEmpty)
          const _EmptyState(
            'No routes yet. Create one from this panel or from an airport destination.',
          ),
        ...routes.map(
          (route) => _RouteCard(game: game, route: route, currency: currency),
        ),
      ],
    );
  }
}

class _RouteCard extends StatefulWidget {
  const _RouteCard({
    required this.game,
    required this.route,
    required this.currency,
  });
  final GameController game;
  final RoutePlan route;
  final CurrencyOption currency;

  @override
  State<_RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<_RouteCard> {
  var confirmingDelete = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final route = widget.game.routes[widget.route.id] ?? widget.route;
    final currency = widget.currency;
    final ac = route.aircraftId == null
        ? null
        : game.aircraft[route.aircraftId!];
    final type = ac == null ? null : aircraftTypesById[ac.typeId];
    final optimisation = game.previewRouteOptimisation(route.id);
    final inactiveReason = route.isActive
        ? null
        : route.aircraftId == null
        ? 'No aircraft'
        : ac?.status == AircraftStatus.crashed
        ? 'Crashed'
        : ac?.status == AircraftStatus.maintenance
        ? 'Maintenance'
        : ac?.isGrounded == true
        ? 'Grounded'
        : 'Inactive';
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: route.isActive
                      ? const Color(0xff3af083)
                      : const Color(0xff8b95a8),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${route.originIata} -> ${route.destinationIata}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                money(route.dailyProfit, currency),
                style: TextStyle(
                  color: route.dailyProfit >= 0
                      ? const Color(0xff3af083)
                      : const Color(0xffff6b6b),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (inactiveReason != null) ...[
            const SizedBox(height: 6),
            _FleetStatusChip(
              label: inactiveReason.toUpperCase(),
              color: const Color(0xffffd166),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            type == null
                ? 'No aircraft assigned · ${route.flightsPerWeek}/week'
                : '${type.displayName} · ${route.flightsPerWeek}/week',
            style: const TextStyle(color: Color(0xff9aa4b5)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RouteMiniStat('Eco fare', money(route.priceEconomy, currency)),
              _RouteMiniStat('Biz fare', money(route.priceBusiness, currency)),
              _RouteMiniStat('Revenue', money(route.dailyRevenue, currency)),
              _RouteMiniStat('Cost', money(route.dailyCost, currency)),
            ],
          ),
          const SizedBox(height: 10),
          _LoadFactorLine(
            label: 'Eco',
            value: route.loadFactorEconomy,
            color: const Color(0xff3af083),
          ),
          if (route.priceBusiness > 0 || route.loadFactorBusiness > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _LoadFactorLine(
                label: 'Biz',
                value: route.loadFactorBusiness,
                color: const Color(0xff77c9ff),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: optimisation == null
                    ? null
                    : () => game.optimiseRoute(route.id),
                icon: const Icon(Icons.auto_fix_high),
                label: Text(optimisation == null ? 'Optimised' : 'Optimise'),
              ),
              OutlinedButton.icon(
                onPressed: game.runDailyTick,
                icon: const Icon(Icons.skip_next),
                label: const Text('Run day'),
              ),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => _RouteEditDialog(
                    game: game,
                    route: route,
                    currency: currency,
                  ),
                ),
                icon: const Icon(Icons.tune),
                label: const Text('Details'),
              ),
              confirmingDelete
                  ? FilledButton.tonalIcon(
                      onPressed: () {
                        game.deleteRoute(route.id);
                        setState(() => confirmingDelete = false);
                      },
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Confirm delete'),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => setState(() => confirmingDelete = true),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
              if (confirmingDelete)
                IconButton(
                  tooltip: 'Cancel delete',
                  onPressed: () => setState(() => confirmingDelete = false),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteMiniStat extends StatelessWidget {
  const _RouteMiniStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: 126,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: _subtleSurface(context),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _hairline(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xff8b95a8))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    ),
  );
}

class _LoadFactorLine extends StatelessWidget {
  const _LoadFactorLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(label, style: const TextStyle(color: Color(0xff9aa4b5))),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value.clamp(0, 1),
              minHeight: 8,
              color: color,
              backgroundColor: const Color(0xff293244),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 42,
          child: Text(
            '$pct%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _RoutePreviewCard extends StatelessWidget {
  const _RoutePreviewCard({
    required this.current,
    required this.preview,
    required this.currency,
  });

  final RoutePlan current;
  final RoutePlan? preview;
  final CurrencyOption currency;

  @override
  Widget build(BuildContext context) {
    final route = preview;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Estimated daily P&L',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (route == null)
            const Text(
              'Assign a compatible aircraft to preview this route.',
              style: TextStyle(color: Color(0xff9aa4b5)),
            )
          else ...[
            _LoadFactorLine(
              label: 'Eco',
              value: route.loadFactorEconomy,
              color: const Color(0xff3af083),
            ),
            if (route.priceBusiness > 0 || route.loadFactorBusiness > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _LoadFactorLine(
                  label: 'Biz',
                  value: route.loadFactorBusiness,
                  color: const Color(0xff77c9ff),
                ),
              ),
            const Divider(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _PreviewMoneyStat(
                  label: 'Revenue',
                  value: route.dailyRevenue,
                  previous: current.dailyRevenue,
                  currency: currency,
                  color: const Color(0xff3af083),
                ),
                _PreviewMoneyStat(
                  label: 'Cost',
                  value: route.dailyCost,
                  previous: current.dailyCost,
                  currency: currency,
                  color: const Color(0xffff6b6b),
                ),
                _PreviewMoneyStat(
                  label: 'Profit',
                  value: route.dailyProfit,
                  previous: current.dailyProfit,
                  currency: currency,
                  color: route.dailyProfit >= 0
                      ? const Color(0xff3af083)
                      : const Color(0xffff6b6b),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${route.dailyPassengers} pax/day · ${(route.flightDurationHours).toStringAsFixed(1)}h flight',
              style: const TextStyle(color: Color(0xff9aa4b5)),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewMoneyStat extends StatelessWidget {
  const _PreviewMoneyStat({
    required this.label,
    required this.value,
    required this.previous,
    required this.currency,
    required this.color,
  });

  final String label;
  final double value;
  final double previous;
  final CurrencyOption currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final delta = value - previous;
    final deltaColor = delta >= 0
        ? const Color(0xff3af083)
        : const Color(0xffff6b6b);
    return SizedBox(
      width: 136,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xff8b95a8))),
          Text(
            money(value, currency),
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
          if (delta.abs() >= 1)
            Text(
              '${delta >= 0 ? '+' : ''}${money(delta, currency)}/day',
              style: TextStyle(color: deltaColor, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _HubsView extends StatelessWidget {
  const _HubsView({required this.game, required this.currency});

  final GameController game;
  final CurrencyOption currency;

  @override
  Widget build(BuildContext context) {
    final hubs = game.player.hubIatas
        .map(game.airportByIata)
        .whereType<Airport>()
        .toList(growable: false);
    final dailyFee = hubs.length * hubAnnualFeeUsd / 365;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetricCard('Hubs', '${hubs.length}', const Color(0xff77c9ff)),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hub network',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Annual fee ${money(hubAnnualFeeUsd, currency)}/hub · total ${money(dailyFee, currency)}/day',
                style: const TextStyle(color: Color(0xff9aa4b5)),
              ),
              const SizedBox(height: 6),
              const Text(
                'Terminals raise capacity. First class lounges raise demand.',
                style: TextStyle(color: Color(0xff9aa4b5)),
              ),
            ],
          ),
        ),
        if (hubs.isEmpty)
          const _EmptyState(
            'No hubs yet. Click an airport on the map to designate one.',
          ),
        ...hubs.map((airport) {
          final terminalLevel = getHubTerminalLevel(airport);
          final loungeLevel = getFirstClassLoungeLevel(airport);
          final terminalCost = getHubTerminalUpgradeCost(airport);
          final loungeCost = getFirstClassLoungeUpgradeCost(airport);
          return _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${airport.city}, ${airport.country} · ${airport.iata}',
                            style: const TextStyle(color: Color(0xff9aa4b5)),
                          ),
                          Text(
                            '${money(hubAnnualFeeUsd / 365, currency)}/day',
                            style: const TextStyle(color: Color(0xffffd166)),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: hubs.length <= 1
                          ? null
                          : () => game.removePlayerHub(airport.iata),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Remove'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _HubUpgradeRow(
                  icon: Icons.apartment,
                  title: 'Terminal capacity',
                  level: '$terminalLevel/$maxHubTerminalLevel',
                  detail:
                      'Capacity x${getHubCapacityMultiplier(airport).toStringAsFixed(2)}',
                  cost: terminalCost,
                  currency: currency,
                  canAfford:
                      terminalCost != null &&
                      game.player.cashUSD >= terminalCost,
                  onPressed: terminalCost == null
                      ? null
                      : () => game.upgradeHubTerminal(airport.iata),
                ),
                const SizedBox(height: 10),
                _HubUpgradeRow(
                  icon: Icons.airline_seat_recline_extra,
                  title: 'First class lounges',
                  level: '$loungeLevel/$maxFirstClassLoungeLevel',
                  detail:
                      'Demand x${getHubDemandMultiplier(airport).toStringAsFixed(2)}',
                  cost: loungeCost,
                  currency: currency,
                  canAfford:
                      loungeCost != null && game.player.cashUSD >= loungeCost,
                  onPressed: loungeCost == null
                      ? null
                      : () => game.upgradeFirstClassLounge(airport.iata),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _HubUpgradeRow extends StatelessWidget {
  const _HubUpgradeRow({
    required this.icon,
    required this.title,
    required this.level,
    required this.detail,
    required this.cost,
    required this.currency,
    required this.canAfford,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String level;
  final String detail;
  final double? cost;
  final CurrencyOption currency;
  final bool canAfford;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _subtleSurface(context),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _hairline(context)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xff77c9ff)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title $level',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(detail, style: const TextStyle(color: Color(0xff9aa4b5))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: canAfford ? onPressed : null,
            child: Text(cost == null ? 'Max' : money(cost!, currency)),
          ),
        ],
      ),
    ),
  );
}

class _FleetView extends StatefulWidget {
  const _FleetView({required this.game, required this.currency});
  final GameController game;
  final CurrencyOption currency;

  @override
  State<_FleetView> createState() => _FleetViewState();
}

class _FleetViewState extends State<_FleetView> {
  var manufacturer = 'All';
  String? confirmingSaleId;

  String _categoryLabel(AircraftCategory category) =>
      category == AircraftCategory.sst
      ? 'SST'
      : category.name[0].toUpperCase() + category.name.substring(1);

  Color _conditionColor(double condition) => condition >= 60
      ? const Color(0xff3af083)
      : condition >= 30
      ? const Color(0xffffd166)
      : const Color(0xffff6b6b);

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final currency = widget.currency;
    final fleet = game.playerFleet;
    final policy = game.player.maintenancePolicy;
    final gameYear = game.settings.startingYear + game.gameDay ~/ 365;
    final manufacturers = [
      'All',
      ...aircraftTypes.map((type) => type.manufacturer).toSet().toList()
        ..sort(),
    ];
    final visibleTypes = aircraftTypes
        .where(
          (type) => manufacturer == 'All' || type.manufacturer == manufacturer,
        )
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetricCard('Fleet size', '${fleet.length}', const Color(0xff77c9ff)),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Buy aircraft · Year $gameYear',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    money(game.player.cashUSD, currency),
                    style: const TextStyle(
                      color: Color(0xff3af083),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: manufacturer,
                decoration: const InputDecoration(labelText: 'Manufacturer'),
                items: manufacturers
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => manufacturer = value);
                },
              ),
              const SizedBox(height: 12),
              ...visibleTypes.take(40).map((type) {
                final unavailable = type.yearIntroduced > gameYear;
                final canAfford = game.player.cashUSD >= type.purchasePrice;
                final canBuy = !unavailable && canAfford;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.035),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              type.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${_categoryLabel(type.category)} · ${type.seatsEconomy}Y/${type.seatsBusiness}J · ${type.rangeKm} km range',
                              style: const TextStyle(color: Color(0xff9aa4b5)),
                            ),
                            Text(
                              'Runway ${type.minRunwayM} m · ${type.cruiseSpeedKmh} km/h · ${money(type.maintenanceCostPerHourUSD, currency)}/hr maint.',
                              style: const TextStyle(color: Color(0xff9aa4b5)),
                            ),
                            if (unavailable)
                              Text(
                                'Available ${type.yearIntroduced}',
                                style: const TextStyle(
                                  color: Color(0xffffd166),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            money(type.purchasePrice, currency),
                            style: TextStyle(
                              color: !unavailable && !canAfford
                                  ? const Color(0xffff6b6b)
                                  : null,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          FilledButton.tonal(
                            onPressed: canBuy
                                ? () => game.buyAircraft(type.id)
                                : null,
                            child: Text(canAfford ? 'Buy' : 'No funds'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Maintenance policy',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Switch(
                    value: policy.enabled,
                    onChanged: (enabled) => game.updateMaintenancePolicy(
                      policy.copyWith(enabled: enabled),
                    ),
                  ),
                ],
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: policy.enabled ? 1 : 0.45,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Trigger below ${policy.threshold.round()}% condition',
                      style: const TextStyle(color: Color(0xff9aa4b5)),
                    ),
                    Slider(
                      value: policy.threshold.clamp(20, 80).toDouble(),
                      min: 20,
                      max: 80,
                      divisions: 12,
                      label: '${policy.threshold.round()}%',
                      onChanged: policy.enabled
                          ? (value) => game.updateMaintenancePolicy(
                              policy.copyWith(
                                enabled: true,
                                threshold: value.roundToDouble(),
                              ),
                            )
                          : null,
                    ),
                    SegmentedButton<MaintenanceTier>(
                      segments: const [
                        ButtonSegment(
                          value: MaintenanceTier.light,
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: MaintenanceTier.standard,
                          label: Text('Standard'),
                        ),
                        ButtonSegment(
                          value: MaintenanceTier.full,
                          label: Text('Full'),
                        ),
                      ],
                      selected: {policy.tier},
                      onSelectionChanged: policy.enabled
                          ? (value) => game.updateMaintenancePolicy(
                              policy.copyWith(tier: value.first),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: policy.autoMaintainIssues,
                onChanged: (value) => game.updateMaintenancePolicy(
                  policy.copyWith(autoMaintainIssues: value ?? false),
                ),
                title: const Text(
                  'Automatically maintain aircraft with issues',
                ),
              ),
            ],
          ),
        ),
        if (fleet.isEmpty)
          const _EmptyState(
            'No aircraft owned yet. Buying a route with a new aircraft will add one.',
          ),
        ...fleet.map((ac) {
          final type = aircraftTypesById[ac.typeId];
          final route = ac.assignedRouteId == null
              ? null
              : game.routes[ac.assignedRouteId!];
          final value = computeAircraftValue(ac, game.gameDay);
          final conditionColor = _conditionColor(ac.condition);
          final inMaintenance = ac.status == AircraftStatus.maintenance;
          final isCrashed = ac.status == AircraftStatus.crashed;
          final canSell = !inMaintenance;
          final isConfirmingSale = confirmingSaleId == ac.id;
          final routeLabel = route == null
              ? isCrashed
                    ? 'Lost in accident'
                    : inMaintenance
                    ? 'In maintenance'
                    : ac.isGrounded
                    ? 'Grounded'
                    : 'Unassigned'
              : 'Route ${route.originIata} -> ${route.destinationIata}';
          return _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: conditionColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ac.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _FleetStatusChip(
                      label: isCrashed
                          ? 'LOST'
                          : inMaintenance
                          ? 'MAINT'
                          : ac.isGrounded
                          ? 'GROUNDED'
                          : ac.autoMaintenanceEnabled
                          ? 'AUTO'
                          : ac.status.name.toUpperCase(),
                      color: isCrashed || ac.isGrounded
                          ? const Color(0xffff6b6b)
                          : inMaintenance
                          ? const Color(0xffffd166)
                          : ac.autoMaintenanceEnabled
                          ? const Color(0xff77c9ff)
                          : const Color(0xff8b95a8),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        type?.displayName ?? ac.typeId,
                        style: const TextStyle(color: Color(0xff9aa4b5)),
                      ),
                    ),
                    Text(
                      money(value, currency),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                if (type != null)
                  Text(
                    '${_categoryLabel(type.category)} · ${type.seatsEconomy}Y/${type.seatsBusiness}J · ${_formatCount(type.rangeKm)} km range · ${type.cruiseSpeedKmh} km/h',
                    style: const TextStyle(color: Color(0xff9aa4b5)),
                  ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: ac.condition / 100,
                  color: conditionColor,
                  backgroundColor: const Color(0xff293244),
                ),
                const SizedBox(height: 8),
                _InfoRow('Condition', '${ac.condition.toStringAsFixed(0)}%'),
                _InfoRow('Assignment', routeLabel),
                _InfoRow(
                  'Flight hours',
                  '${_formatCount(ac.totalFlightHours)}h',
                ),
                _InfoRow(
                  'Crash risk',
                  '${(ac.crashRisk * 100).toStringAsFixed(2)}%',
                ),
                Text(
                  inMaintenance
                      ? 'In ${ac.activeMaintTier?.name ?? 'standard'} maintenance since day ${ac.lastMaintenanceGameDay}'
                      : 'Maintenance owed ${ac.maintenanceHoursOwed.toStringAsFixed(1)}h',
                  style: const TextStyle(color: Color(0xff9aa4b5)),
                ),
                if (ac.isGrounded || isCrashed) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xffff6b6b).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xffff6b6b).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      ac.groundedReason ??
                          (isCrashed
                              ? 'Aircraft lost and unavailable.'
                              : 'Aircraft grounded until maintenance is completed.'),
                      style: const TextStyle(color: Color(0xffffb4b4)),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (route != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (context) => _RouteEditDialog(
                              game: game,
                              route: route,
                              currency: currency,
                            ),
                          ),
                          icon: const Icon(Icons.alt_route),
                          label: const Text('View Route'),
                        ),
                      ),
                    if (route != null) const SizedBox(width: 8),
                    Expanded(
                      child: isConfirmingSale
                          ? Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    onPressed: canSell
                                        ? () {
                                            game.sellAircraft(ac.id);
                                            setState(
                                              () => confirmingSaleId = null,
                                            );
                                          }
                                        : null,
                                    icon: const Icon(Icons.check),
                                    label: Text(
                                      isCrashed ? 'Write off' : 'Confirm',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: 'Cancel',
                                  onPressed: () =>
                                      setState(() => confirmingSaleId = null),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            )
                          : OutlinedButton.icon(
                              onPressed: canSell
                                  ? () =>
                                        setState(() => confirmingSaleId = ac.id)
                                  : null,
                              icon: Icon(
                                isCrashed ? Icons.delete_forever : Icons.sell,
                              ),
                              label: Text(
                                isCrashed ? 'Write Off' : 'Sell Aircraft',
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (type != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: MaintenanceTier.values.map((tier) {
                      final cost = game.maintenanceCost(ac.id, tier);
                      return OutlinedButton(
                        onPressed: ac.status == AircraftStatus.maintenance
                            ? null
                            : () => game.startMaintenance(ac.id, tier),
                        child: Text('${tier.name} · ${money(cost, currency)}'),
                      );
                    }).toList(),
                  ),
                if (!ac.excludedFromPolicy)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Fleet policy ${policy.enabled ? 'ON' : 'OFF'}',
                      style: const TextStyle(color: Color(0xff9aa4b5)),
                    ),
                  ),
                if (ac.excludedFromPolicy) ...[
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _subtleSurface(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _hairline(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Custom auto-maintenance',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: ac.autoMaintenanceEnabled,
                                    onChanged: (enabled) =>
                                        game.setAutoMaintenance(
                                          ac.id,
                                          enabled,
                                          ac.autoMaintenanceThreshold,
                                          ac.autoMaintenanceTier,
                                        ),
                                  ),
                                ],
                              ),
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 180),
                                opacity: ac.autoMaintenanceEnabled ? 1 : 0.45,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Trigger below ${ac.autoMaintenanceThreshold.round()}% condition',
                                      style: const TextStyle(
                                        color: Color(0xff9aa4b5),
                                      ),
                                    ),
                                    Slider(
                                      value: ac.autoMaintenanceThreshold
                                          .clamp(20, 80)
                                          .toDouble(),
                                      min: 20,
                                      max: 80,
                                      divisions: 12,
                                      label:
                                          '${ac.autoMaintenanceThreshold.round()}%',
                                      onChanged: ac.autoMaintenanceEnabled
                                          ? (value) => game.setAutoMaintenance(
                                              ac.id,
                                              true,
                                              value.roundToDouble(),
                                              ac.autoMaintenanceTier,
                                            )
                                          : null,
                                    ),
                                    SegmentedButton<MaintenanceTier>(
                                      segments: const [
                                        ButtonSegment(
                                          value: MaintenanceTier.light,
                                          label: Text('Light'),
                                        ),
                                        ButtonSegment(
                                          value: MaintenanceTier.standard,
                                          label: Text('Standard'),
                                        ),
                                        ButtonSegment(
                                          value: MaintenanceTier.full,
                                          label: Text('Full'),
                                        ),
                                      ],
                                      selected: {ac.autoMaintenanceTier},
                                      onSelectionChanged:
                                          ac.autoMaintenanceEnabled
                                          ? (value) => game.setAutoMaintenance(
                                              ac.id,
                                              true,
                                              ac.autoMaintenanceThreshold,
                                              value.first,
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: ac.excludedFromPolicy,
                  onChanged: (value) =>
                      game.setAircraftPolicyExclusion(ac.id, value),
                  title: const Text('Exclude from fleet policy'),
                ),
                if (ac.status == AircraftStatus.maintenance)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => game.completeMaintenance(ac.id),
                      icon: const Icon(Icons.build_circle),
                      label: const Text('Complete now'),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _FleetStatusChip extends StatelessWidget {
  const _FleetStatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
    ),
  );
}

class _FinanceView extends StatelessWidget {
  const _FinanceView({required this.game, required this.currency});
  final GameController game;
  final CurrencyOption currency;
  @override
  Widget build(BuildContext context) {
    final player = game.player;
    final routes = game.playerRoutes;
    final fleet = game.playerFleet;
    final last = player.dailyStats.lastOrNull;
    final lastProfit = last?.profit ?? player.lastDailyProfit;
    final revenue30 = player.dailyStats.fold<double>(
      0,
      (sum, stat) => sum + stat.revenue,
    );
    final costs30 = player.dailyStats.fold<double>(
      0,
      (sum, stat) => sum + stat.costs,
    );
    final profit30 = player.dailyStats.fold<double>(
      0,
      (sum, stat) => sum + stat.profit,
    );
    final passengers30 = player.dailyStats.fold<int>(
      0,
      (sum, stat) => sum + stat.passengers,
    );
    final profitMargin = revenue30 <= 0 ? 0 : (profit30 / revenue30) * 100;
    final debtService = calculateDailyDebtService(player);
    final debtInterest = calculateDailyDebtInterest(player);
    final companyValue = game.companyValue(player.id);
    final creditLimit = game.playerLoanCreditLimit();
    final creditRemaining = math.max(0, creditLimit - player.totalDebt);
    final activeRoutes = routes.where((route) => route.isActive).toList();
    final profitableRoutes = activeRoutes
        .where((route) => route.dailyProfit > 0)
        .length;
    final losingRoutes = activeRoutes
        .where((route) => route.dailyProfit < 0)
        .length;
    final averageLoadFactor = activeRoutes.isEmpty
        ? 0.0
        : activeRoutes.fold<double>(
                0,
                (sum, route) => sum + route.loadFactorEconomy,
              ) /
              activeRoutes.length;
    final averageCondition = fleet.isEmpty
        ? 0.0
        : fleet.fold<double>(0, (sum, ac) => sum + ac.condition) / fleet.length;
    final groundedAircraft = fleet
        .where(
          (ac) =>
              ac.status == AircraftStatus.maintenance ||
              ac.status == AircraftStatus.crashed,
        )
        .length;
    final dailyPassengers = last?.passengers ?? 0;
    final totalDailyRevenue = routes.fold<double>(
      0,
      (sum, route) => sum + route.dailyRevenue,
    );
    final totalDailyCost = routes.fold<double>(
      0,
      (sum, route) => sum + route.dailyCost,
    );
    final topRoutes = [...routes]
      ..sort((a, b) => b.dailyProfit.compareTo(a.dailyProfit));
    final shareholdingsValue = game.competitors.fold<double>(
      0,
      (sum, airline) =>
          sum +
          game.companyValue(airline.id) * game.playerStakeIn(airline.id) / 100,
    );
    final projectedDividends = game.competitors.fold<double>(0, (sum, airline) {
      final stake = game.playerStakeIn(airline.id);
      return stake <= 0 || airline.lastDailyProfit <= 0
          ? sum
          : sum + airline.lastDailyProfit * stake / 100;
    });
    final dividendSources =
        game.competitors
            .map(
              (airline) => (
                airline: airline,
                stake: game.playerStakeIn(airline.id),
                dividend:
                    math.max(0, airline.lastDailyProfit) *
                    game.playerStakeIn(airline.id) /
                    100,
              ),
            )
            .where((item) => item.stake > 0)
            .toList()
          ..sort((a, b) => b.dividend.compareTo(a.dividend));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _FinanceMetric(
              label: 'Cash',
              value: money(player.cashUSD, currency),
              accent: const Color(0xff3af083),
            ),
            _FinanceMetric(
              label: 'Last daily profit',
              value: money(lastProfit, currency),
              accent: lastProfit >= 0
                  ? const Color(0xff3af083)
                  : const Color(0xffff6b6b),
            ),
            _FinanceMetric(
              label: 'Company value',
              value: money(companyValue, currency),
              accent: const Color(0xff77c9ff),
            ),
            _FinanceMetric(
              label: 'Debt',
              value: money(player.totalDebt, currency),
              accent: const Color(0xffffd166),
            ),
          ],
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '30-day profit trend',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 150,
                child: player.dailyStats.length < 2
                    ? const Center(
                        child: Text(
                          'Run a few days to build a trend.',
                          style: TextStyle(color: Color(0xff9aa4b5)),
                        ),
                      )
                    : CustomPaint(
                        painter: _ProfitTrendPainter(player.dailyStats),
                        child: const SizedBox.expand(),
                      ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  _MiniFinanceStat('Revenue', money(revenue30, currency)),
                  _MiniFinanceStat('Costs', money(costs30, currency)),
                  _MiniFinanceStat('Net', money(profit30, currency)),
                  _MiniFinanceStat(
                    'Margin',
                    '${profitMargin.toStringAsFixed(1)}%',
                  ),
                ],
              ),
            ],
          ),
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Operating performance',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              _InfoRow('Routes', '${activeRoutes.length} active'),
              _InfoRow(
                'Route health',
                '$profitableRoutes profitable · $losingRoutes losing',
              ),
              _InfoRow('Fleet', '${fleet.length} aircraft'),
              _InfoRow(
                'Average condition',
                '${averageCondition.toStringAsFixed(1)}%',
              ),
              _InfoRow('Grounded', groundedAircraft.toString()),
              _InfoRow(
                'Load factor',
                '${(averageLoadFactor * 100).toStringAsFixed(1)}%',
              ),
              _InfoRow('Daily passengers', _formatCount(dailyPassengers)),
              _InfoRow('30-day passengers', _formatCount(passengers30)),
              _InfoRow(
                'Market share',
                '${player.marketSharePercent.toStringAsFixed(1)}%',
              ),
              _InfoRow('Reputation', player.reputationScore.toStringAsFixed(0)),
            ],
          ),
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Public company information',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              _InfoRow('Company value', money(companyValue, currency)),
              _InfoRow('Price per 1%', money(companyValue / 100, currency)),
              _InfoRow(
                'Shareholdings value',
                money(shareholdingsValue, currency),
              ),
              _InfoRow(
                'Projected dividends',
                '${money(projectedDividends, currency)}/day',
              ),
              _InfoRow('Cash runway', _cashRunway(player.cashUSD, lastProfit)),
              _InfoRow(
                'All-time passengers',
                _formatCount(player.totalPassengersAllTime),
              ),
            ],
          ),
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ownership',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(height: 12, color: const Color(0xff2dd4bf)),
              ),
              const SizedBox(height: 8),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _OwnershipChip(label: 'You 100%', accent: Color(0xff2dd4bf)),
                  _OwnershipChip(label: 'Float 0%', accent: Color(0xff64748b)),
                ],
              ),
            ],
          ),
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Route performance',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                '$profitableRoutes profitable · $losingRoutes losing',
                style: const TextStyle(color: Color(0xff8b95a8)),
              ),
              const SizedBox(height: 10),
              if (topRoutes.isEmpty)
                const _EmptyState('No route data available.')
              else
                ...topRoutes.take(4).map((route) {
                  final origin = game.airportByIata(route.originIata);
                  final dest = game.airportByIata(route.destinationIata);
                  final label = origin != null && dest != null
                      ? '${origin.city} -> ${dest.city}'
                      : '${route.originIata} -> ${route.destinationIata}';
                  return _FinanceRouteRow(
                    label: label,
                    detail: '${route.flightsPerWeek} flights/week',
                    value: '${money(route.dailyProfit, currency)}/day',
                    positive: route.dailyProfit >= 0,
                  );
                }),
            ],
          ),
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Daily breakdown',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              _FinanceBreakdownRow(
                label: 'Revenue',
                value: totalDailyRevenue,
                color: const Color(0xff3af083),
                currency: currency,
              ),
              _FinanceBreakdownRow(
                label: 'Fuel',
                value: -totalDailyCost * 0.35,
                color: const Color(0xffff6b6b),
                currency: currency,
              ),
              _FinanceBreakdownRow(
                label: 'Maintenance',
                value: -totalDailyCost * 0.25,
                color: const Color(0xffffa94d),
                currency: currency,
              ),
              _FinanceBreakdownRow(
                label: 'Crew',
                value: -totalDailyCost * 0.25,
                color: const Color(0xffffd166),
                currency: currency,
              ),
              _FinanceBreakdownRow(
                label: 'Airport fees',
                value: -totalDailyCost * 0.15,
                color: const Color(0xff77c9ff),
                currency: currency,
              ),
              _FinanceBreakdownRow(
                label: 'Debt service',
                value: -debtService,
                color: const Color(0xffff8fab),
                currency: currency,
              ),
              if (projectedDividends > 0)
                _FinanceBreakdownRow(
                  label: 'Dividends',
                  value: projectedDividends,
                  color: const Color(0xff2dd4bf),
                  currency: currency,
                ),
              const Divider(height: 20),
              _FinanceBreakdownRow(
                label: 'Net',
                value: lastProfit + projectedDividends,
                color: lastProfit + projectedDividends >= 0
                    ? const Color(0xff3af083)
                    : const Color(0xffff6b6b),
                currency: currency,
                strong: true,
              ),
            ],
          ),
        ),
        if (dividendSources.isNotEmpty)
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Investment holdings',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                ...dividendSources.map(
                  (item) => _InfoRow(
                    '${item.airline.name} (${item.stake.toStringAsFixed(0)}%)',
                    item.dividend > 0
                        ? '+${money(item.dividend, currency)}/day'
                        : item.airline.lastDailyProfit < 0
                        ? 'Losing'
                        : '-',
                  ),
                ),
              ],
            ),
          ),
        _Card(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text(
              'Loans',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            initiallyExpanded: true,
            children: [
              _InfoRow('Total debt', money(player.totalDebt, currency)),
              _InfoRow('Credit remaining', money(creditRemaining, currency)),
              _InfoRow('Daily payment', money(debtService, currency)),
              _InfoRow('Daily interest', money(debtInterest, currency)),
              const SizedBox(height: 8),
              if (player.loans.isEmpty)
                const _EmptyState('No active loans.')
              else
                ...player.loans.map(
                  (loan) => _LoanAccordionTile(
                    game: game,
                    loan: loan,
                    currency: currency,
                  ),
                ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Apply for finance',
                  style: TextStyle(color: Color(0xff9aa4b5)),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: loanOffers
                    .map(
                      (offer) => OutlinedButton(
                        onPressed: game.canApplyForLoan(offer)
                            ? () => game.applyForLoan(offer)
                            : null,
                        child: Text(
                          '${money(offer.amountUSD, currency)} · ${formatInterestRate(offer.annualInterestRate)}',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _cashRunway(double cash, double lastProfit) {
    if (lastProfit >= 0) return 'Profitable';
    if (cash <= 0) return 'Critical';
    final days = cash / lastProfit.abs();
    if (days > 365) return '365+ days';
    return '${days.floor()} days';
  }
}

class _LoanAccordionTile extends StatelessWidget {
  const _LoanAccordionTile({
    required this.game,
    required this.loan,
    required this.currency,
  });

  final GameController game;
  final Loan loan;
  final CurrencyOption currency;

  @override
  Widget build(BuildContext context) {
    final cash = game.player.cashUSD;
    final affordable = math.min(cash, loan.principalUSD);
    final repaymentOptions = [
      (label: '10%', amount: loan.principalUSD * 0.10),
      (label: '25%', amount: loan.principalUSD * 0.25),
      (label: '50%', amount: loan.principalUSD * 0.50),
      (label: 'Clear loan', amount: loan.principalUSD),
    ];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 10),
      title: Text(money(loan.principalUSD, currency)),
      subtitle: Text(
        '${formatInterestRate(loan.annualInterestRate)} · ${loan.termYears} years · ${money(loan.dailyPaymentUSD, currency)}/day',
      ),
      children: [
        _InfoRow('Principal remaining', money(loan.principalUSD, currency)),
        _InfoRow(
          'Daily interest',
          money((loan.principalUSD * loan.annualInterestRate) / 365, currency),
        ),
        _InfoRow('Issued day', loan.issuedGameDay.toString()),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...repaymentOptions.map((option) {
                final canPay = cash >= option.amount;
                return OutlinedButton(
                  onPressed: canPay
                      ? () => game.repayLoan(loan.id, option.amount)
                      : null,
                  child: Text(
                    '${option.label} · ${money(option.amount, currency)}',
                  ),
                );
              }),
              FilledButton.tonal(
                onPressed: affordable <= 0
                    ? null
                    : () => game.repayLoan(loan.id, affordable),
                child: Text(
                  'What I can afford · ${money(affordable, currency)}',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OwnershipChip extends StatelessWidget {
  const _OwnershipChip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: accent.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: accent,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _FinanceRouteRow extends StatelessWidget {
  const _FinanceRouteRow({
    required this.label,
    required this.detail,
    required this.value,
    required this.positive,
  });

  final String label;
  final String detail;
  final String value;
  final bool positive;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(detail, style: const TextStyle(color: Color(0xff8b95a8))),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: TextStyle(
            color: positive ? const Color(0xff3af083) : const Color(0xffff6b6b),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _FinanceBreakdownRow extends StatelessWidget {
  const _FinanceBreakdownRow({
    required this.label,
    required this.value,
    required this.color,
    required this.currency,
    this.strong = false,
  });

  final String label;
  final double value;
  final Color color;
  final CurrencyOption currency;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: strong ? const Color(0xffdbe4f3) : const Color(0xff9aa4b5),
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
        Text(
          money(value, currency),
          style: TextStyle(
            color: color,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

String _formatCount(num value) {
  final sign = value < 0 ? '-' : '';
  final abs = value.abs();
  if (abs >= 1000000000) {
    return '$sign${(abs / 1000000000).toStringAsFixed(1)}B';
  }
  if (abs >= 1000000) return '$sign${(abs / 1000000).toStringAsFixed(1)}M';
  if (abs >= 1000) return '$sign${(abs / 1000).toStringAsFixed(1)}K';
  return value.round().toString();
}

class _FinanceMetric extends StatelessWidget {
  const _FinanceMetric({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xff9aa4b5))),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MiniFinanceStat extends StatelessWidget {
  const _MiniFinanceStat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 90,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xff9aa4b5))),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _ProfitTrendPainter extends CustomPainter {
  const _ProfitTrendPainter(this.stats);
  final List<DailySnapshot> stats;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final values = stats.map((stat) => stat.profit).toList();
    final maxValue = values.fold<double>(
      0,
      (max, value) => math.max(max, value.abs()),
    );
    if (maxValue <= 0) return;
    final zeroY = size.height / 2;
    final zeroPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : size.width * i / (values.length - 1);
      final y = zeroY - (values[i] / maxValue) * (size.height * 0.42);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final line = Paint()
      ..color = const Color(0xff77c9ff)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _ProfitTrendPainter oldDelegate) =>
      oldDelegate.stats != stats;
}

class _CompetitorsView extends StatefulWidget {
  const _CompetitorsView({required this.game, required this.currency});
  final GameController game;
  final CurrencyOption currency;
  @override
  State<_CompetitorsView> createState() => _CompetitorsViewState();
}

class _CompetitorsViewState extends State<_CompetitorsView> {
  Airline? selected;

  @override
  Widget build(BuildContext context) {
    if (selected != null) {
      final airline = widget.game.airlines[selected!.id] ?? selected!;
      final routes = widget.game.routesForAirline(airline.id);
      final fleet = widget.game.fleetForAirline(airline.id);
      final activeRoutes = routes.where((route) => route.isActive).toList();
      final profitableRoutes = activeRoutes
          .where((route) => route.dailyProfit > 0)
          .length;
      final losingRoutes = activeRoutes
          .where((route) => route.dailyProfit < 0)
          .length;
      final latestSnapshot = airline.dailyStats.lastOrNull;
      final routeProfit = routes.fold<double>(
        0,
        (sum, route) => sum + route.dailyProfit,
      );
      final routeRevenue = routes.fold<double>(
        0,
        (sum, route) => sum + route.dailyRevenue,
      );
      final routeCosts = routes.fold<double>(
        0,
        (sum, route) => sum + route.dailyCost,
      );
      final dailyProfit =
          latestSnapshot?.profit ??
          (airline.lastDailyProfit != 0
              ? airline.lastDailyProfit
              : routeProfit);
      final dailyRevenue = latestSnapshot?.revenue ?? routeRevenue;
      final dailyCosts = latestSnapshot?.costs ?? routeCosts;
      final margin = dailyRevenue <= 0 ? 0.0 : dailyProfit / dailyRevenue * 100;
      final averageLoadFactor = activeRoutes.isEmpty
          ? 0.0
          : activeRoutes.fold<double>(
                  0,
                  (sum, route) => sum + route.loadFactorEconomy,
                ) /
                activeRoutes.length;
      final averageCondition = fleet.isEmpty
          ? 0.0
          : fleet.fold<double>(0, (sum, ac) => sum + ac.condition) /
                fleet.length;
      final groundedAircraft = fleet
          .where(
            (ac) =>
                ac.isGrounded ||
                ac.status == AircraftStatus.maintenance ||
                ac.status == AircraftStatus.crashed,
          )
          .length;
      final snapshots = airline.dailyStats.length <= 30
          ? airline.dailyStats
          : airline.dailyStats.sublist(airline.dailyStats.length - 30);
      final thirtyDayProfit = snapshots.fold<double>(
        0,
        (sum, day) => sum + day.profit,
      );
      final thirtyDayRevenue = snapshots.fold<double>(
        0,
        (sum, day) => sum + day.revenue,
      );
      final thirtyDayCosts = snapshots.fold<double>(
        0,
        (sum, day) => sum + day.costs,
      );
      final dailyPassengers = latestSnapshot?.passengers ?? 0;
      final topRoutes = [...routes]
        ..sort((a, b) => b.dailyProfit.compareTo(a.dailyProfit));
      final playerStake = airline.isPlayer
          ? 100.0
          : widget.game.playerStakeIn(airline.id);
      final marketFloat = airline.isPlayer
          ? 0.0
          : widget.game.marketFloatForAirline(airline.id);
      final companyValue = widget.game.companyValue(airline.id);
      final buyout = widget.game.buyoutPrice(airline.id);
      final takeoverCost =
          (buyout.totalPrice - companyValue * (playerStake / 100))
              .clamp(0, double.infinity)
              .toDouble();
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => selected = null),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          ),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _AirlineLogo(logo: airline.logoEmoji, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        airline.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoRow('Cash', money(airline.cashUSD, widget.currency)),
                _InfoRow('Debt', money(airline.totalDebt, widget.currency)),
                _InfoRow(
                  'Daily profit/loss',
                  money(dailyProfit, widget.currency),
                ),
                _InfoRow('Daily revenue', money(dailyRevenue, widget.currency)),
                _InfoRow('Daily costs', money(dailyCosts, widget.currency)),
                _InfoRow('Profit margin', '${margin.toStringAsFixed(1)}%'),
                _InfoRow('Company value', money(companyValue, widget.currency)),
                _InfoRow(
                  'Price per 1%',
                  money(companyValue / 100, widget.currency),
                ),
                _InfoRow(
                  'Market share',
                  '${airline.marketSharePercent.toStringAsFixed(1)}%',
                ),
                _InfoRow('Your stake', '${playerStake.toStringAsFixed(0)}%'),
                if (!airline.isPlayer)
                  _InfoRow(
                    'Market float',
                    '${marketFloat.toStringAsFixed(0)}%',
                  ),
                _InfoRow(
                  'Reputation',
                  airline.reputationScore.toStringAsFixed(0),
                ),
                _InfoRow('Fleet', '${fleet.length} aircraft'),
                _InfoRow(
                  'Routes',
                  '${activeRoutes.length} active · $profitableRoutes profitable',
                ),
                _InfoRow(
                  'Average condition',
                  '${averageCondition.toStringAsFixed(1)}%',
                ),
                _InfoRow(
                  'Load factor',
                  '${(averageLoadFactor * 100).toStringAsFixed(1)}%',
                ),
                _InfoRow('Grounded', groundedAircraft.toString()),
                _InfoRow('Daily passengers', _formatCount(dailyPassengers)),
                _InfoRow(
                  'All-time passengers',
                  _formatCount(airline.totalPassengersAllTime),
                ),
              ],
            ),
          ),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Public valuation',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                _InfoRow(
                  '30-day revenue',
                  money(thirtyDayRevenue, widget.currency),
                ),
                _InfoRow(
                  '30-day costs',
                  money(thirtyDayCosts, widget.currency),
                ),
                _InfoRow('30-day net', money(thirtyDayProfit, widget.currency)),
              ],
            ),
          ),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Route performance',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '$profitableRoutes profitable · $losingRoutes losing',
                  style: const TextStyle(color: Color(0xff8b95a8)),
                ),
                const SizedBox(height: 10),
                if (topRoutes.isEmpty)
                  const _EmptyState('No active route data available.')
                else
                  ...topRoutes.take(4).map((route) {
                    final origin = widget.game.airportByIata(route.originIata);
                    final dest = widget.game.airportByIata(
                      route.destinationIata,
                    );
                    final label = origin != null && dest != null
                        ? '${origin.city} -> ${dest.city}'
                        : '${route.originIata} -> ${route.destinationIata}';
                    return _FinanceRouteRow(
                      label: label,
                      detail:
                          '${route.originIata} -> ${route.destinationIata} · ${(route.loadFactorEconomy * 100).round()}% LF',
                      value: '${money(route.dailyProfit, widget.currency)}/day',
                      positive: route.dailyProfit >= 0,
                    );
                  }),
              ],
            ),
          ),
          if (!airline.isPlayer)
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Ownership',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 12,
                      child: Row(
                        children: [
                          if (playerStake > 0)
                            Expanded(
                              flex: playerStake.round().clamp(1, 100),
                              child: Container(color: const Color(0xff2dd4bf)),
                            ),
                          if (marketFloat > 0)
                            Expanded(
                              flex: marketFloat.round().clamp(1, 100),
                              child: Container(color: const Color(0xff334155)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: marketFloat < 1
                            ? null
                            : () => _showShareTradeDialog(
                                context,
                                widget.game,
                                airline.id,
                                widget.currency,
                              ),
                        icon: const Icon(Icons.pie_chart),
                        label: const Text('Buy / sell shares'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed:
                            playerStake < 50 ||
                                widget.game.player.cashUSD < takeoverCost
                            ? null
                            : () => _showTakeoverDialog(
                                context,
                                widget.game,
                                airline.id,
                                widget.currency,
                                onAcquired: () =>
                                    setState(() => selected = null),
                              ),
                        icon: const Icon(Icons.handshake),
                        label: Text(
                          'Takeover ${money(takeoverCost, widget.currency)}',
                        ),
                      ),
                    ],
                  ),
                  if (playerStake < 50)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Majority stake required for takeover.',
                        style: TextStyle(color: Color(0xff9aa4b5)),
                      ),
                    ),
                ],
              ),
            ),
          ExpansionTile(
            title: const Text('Fleet'),
            initiallyExpanded: true,
            children: fleet.map((ac) {
              final type = aircraftTypesById[ac.typeId];
              return ListTile(
                title: Text(ac.name),
                subtitle: Text(
                  '${type?.displayName ?? ac.typeId} · ${ac.condition.toStringAsFixed(0)}% condition',
                ),
              );
            }).toList(),
          ),
          ExpansionTile(
            title: const Text('Routes'),
            children: routes
                .map(
                  (route) => ListTile(
                    title: Text(
                      '${route.originIata} -> ${route.destinationIata}',
                    ),
                    subtitle: Text(
                      '${route.flightsPerWeek}/week · ${money(route.dailyProfit, widget.currency)}/day',
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      );
    }

    final airlines = [widget.game.player, ...widget.game.competitors]
      ..sort((a, b) => b.marketSharePercent.compareTo(a.marketSharePercent));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetricCard('Airlines', '${airlines.length}', const Color(0xff77c9ff)),
        ...airlines.map(
          (airline) => _Card(
            child: InkWell(
              onTap: () => setState(() => selected = airline),
              child: Row(
                children: [
                  _AirlineLogo(logo: airline.logoEmoji, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          airline.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '${airline.routeIds.length} routes · ${airline.fleetIds.length} aircraft',
                          style: const TextStyle(color: Color(0xff9aa4b5)),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${airline.marketSharePercent.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Color(0xffffd166),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        money(airline.lastDailyProfit, widget.currency),
                        style: TextStyle(
                          color: airline.lastDailyProfit >= 0
                              ? const Color(0xff3af083)
                              : const Color(0xffff6b6b),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void _showShareTradeDialog(
  BuildContext context,
  GameController game,
  String airlineId,
  CurrencyOption currency,
) {
  var percent = 5.0;
  var selling = false;
  String? error;
  showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final airline = game.airlines[airlineId];
        if (airline == null) return const SizedBox.shrink();
        final owned = game.playerStakeIn(airlineId);
        final float = game.marketFloatForAirline(airlineId);
        final max = selling ? owned : math.min(50, float);
        final clampedPercent = max < 1 ? 0.0 : percent.clamp(1, max).toDouble();
        final value = game.companyValue(airlineId);
        final buyPrice = clampedPercent <= 0
            ? 0.0
            : game.sharePurchasePrice(airlineId, clampedPercent);
        final sellPrice = clampedPercent <= 0
            ? 0.0
            : (value / 100 * clampedPercent / 100000).round() * 100000.0;
        final price = selling ? sellPrice : buyPrice;
        return AlertDialog(
          title: Text('${selling ? 'Sell' : 'Buy'} ${airline.name} shares'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Buy')),
                    ButtonSegment(value: true, label: Text('Sell')),
                  ],
                  selected: {selling},
                  onSelectionChanged: (value) {
                    setState(() {
                      selling = value.first;
                      percent = 5;
                      error = null;
                    });
                  },
                ),
                const SizedBox(height: 14),
                _InfoRow('Company value', money(value, currency)),
                _InfoRow('You own', '${owned.toStringAsFixed(0)}%'),
                _InfoRow('Market float', '${float.toStringAsFixed(0)}%'),
                const SizedBox(height: 14),
                Text('Amount: ${clampedPercent.toStringAsFixed(0)}%'),
                Slider(
                  value: max < 1 ? 1 : clampedPercent,
                  min: 1,
                  max: math.max(1, max).toDouble(),
                  divisions: math.max(1, max.round()),
                  label: '${clampedPercent.toStringAsFixed(0)}%',
                  onChanged: max < 1
                      ? null
                      : (value) => setState(() => percent = value),
                ),
                _InfoRow(selling ? 'Proceeds' : 'Cost', money(price, currency)),
                if (!selling)
                  _InfoRow(
                    'Rival cash after',
                    money(airline.cashUSD + price, currency),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Color(0xffff6b6b)),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  clampedPercent <= 0 ||
                      (!selling && game.player.cashUSD < price)
                  ? null
                  : () {
                      try {
                        if (selling) {
                          game.sellShares(airlineId, clampedPercent);
                        } else {
                          game.buyShares(airlineId, clampedPercent);
                        }
                        Navigator.pop(context);
                      } catch (e) {
                        setState(() => error = e.toString());
                      }
                    },
              child: Text(selling ? 'Sell shares' : 'Buy shares'),
            ),
          ],
        );
      },
    ),
  );
}

void _showTakeoverDialog(
  BuildContext context,
  GameController game,
  String airlineId,
  CurrencyOption currency, {
  VoidCallback? onAcquired,
}) {
  String? error;
  showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final airline = game.airlines[airlineId];
        if (airline == null) return const SizedBox.shrink();
        final stake = game.playerStakeIn(airlineId);
        final value = game.companyValue(airlineId);
        final valuation = game.buyoutPrice(airlineId);
        final price = (valuation.totalPrice - value * (stake / 100))
            .clamp(0, double.infinity)
            .toDouble();
        return AlertDialog(
          title: Text('Acquire ${airline.name}'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _InfoRow('Fleet', money(valuation.fleetValue, currency)),
                _InfoRow('Routes', money(valuation.routeValue, currency)),
                _InfoRow('Cash', money(valuation.cashValue, currency)),
                _InfoRow('Debt', money(valuation.debtValue, currency)),
                _InfoRow(
                  'Control premium',
                  money(valuation.controlPremium, currency),
                ),
                const Divider(),
                _InfoRow('Your stake', '${stake.toStringAsFixed(0)}%'),
                _InfoRow('Price to pay', money(price, currency)),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Color(0xffff6b6b)),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: stake < 50 || game.player.cashUSD < price
                  ? null
                  : () {
                      try {
                        game.takeoverAirline(airlineId);
                        onAcquired?.call();
                        Navigator.pop(context);
                      } catch (e) {
                        setState(() => error = e.toString());
                      }
                    },
              icon: const Icon(Icons.handshake),
              label: const Text('Acquire'),
            ),
          ],
        );
      },
    ),
  );
}

class _RouteSummaryDialog extends StatelessWidget {
  const _RouteSummaryDialog({
    required this.game,
    required this.route,
    required this.currency,
  });

  final GameController game;
  final RoutePlan route;
  final CurrencyOption currency;

  @override
  Widget build(BuildContext context) {
    final latestRoute = game.routes[route.id] ?? route;
    final airline = game.airlines[latestRoute.airlineId];
    final ac = latestRoute.aircraftId == null
        ? null
        : game.aircraft[latestRoute.aircraftId!];
    final type = ac == null ? null : aircraftTypesById[ac.typeId];
    return AlertDialog(
      title: Text(
        '${latestRoute.originIata} -> ${latestRoute.destinationIata}',
      ),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (airline != null)
              Row(
                children: [
                  _AirlineLogo(logo: airline.logoEmoji, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      airline.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            _InfoRow('Daily profit', money(latestRoute.dailyProfit, currency)),
            _InfoRow(
              'Daily revenue',
              money(latestRoute.dailyRevenue, currency),
            ),
            _InfoRow('Daily cost', money(latestRoute.dailyCost, currency)),
            _InfoRow('Flights', '${latestRoute.flightsPerWeek}/week'),
            _InfoRow(
              'Load factor',
              '${(latestRoute.loadFactorEconomy * 100).round()}%',
            ),
            _InfoRow(
              'Aircraft',
              type == null ? 'No aircraft assigned' : type.displayName,
            ),
            if (ac != null)
              _InfoRow('Condition', '${ac.condition.toStringAsFixed(0)}%'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _FareGuide {
  const _FareGuide({
    required this.suggestedEconomy,
    required this.suggestedBusiness,
    required this.maxEconomy,
    required this.maxBusiness,
  });

  factory _FareGuide.fromCurrent(int economy, int business) {
    final suggestedEconomy = math.max(1, economy);
    final suggestedBusiness = math.max(1, business);
    return _FareGuide(
      suggestedEconomy: suggestedEconomy,
      suggestedBusiness: suggestedBusiness,
      maxEconomy:
          math.max(suggestedEconomy, economy) * maxReasonableFareMultiplier,
      maxBusiness:
          math.max(suggestedBusiness, business) * maxReasonableFareMultiplier,
    );
  }

  final int suggestedEconomy;
  final int suggestedBusiness;
  final double maxEconomy;
  final double maxBusiness;
}

_FareGuide _fareGuideForRoute({
  required RoutePlan route,
  required Aircraft aircraft,
  required AircraftType type,
  required Airport origin,
  required Airport destination,
  required double fuelPrice,
  required int gameDay,
}) {
  final costs = computeFlightCost(
    route,
    aircraft,
    type,
    origin,
    destination,
    fuelPrice,
    currentGameDay: gameDay,
  );
  final seats = math.max(1, type.seatsEconomy + type.seatsBusiness);
  final suggestedEconomy = math.max(1, (costs.totalCost / seats * 1.3).round());
  final suggestedBusiness = type.seatsBusiness > 0 ? suggestedEconomy * 4 : 0;
  return _FareGuide(
    suggestedEconomy: suggestedEconomy,
    suggestedBusiness: suggestedBusiness,
    maxEconomy: suggestedEconomy * maxReasonableFareMultiplier,
    maxBusiness: math.max(1, suggestedBusiness) * maxReasonableFareMultiplier,
  );
}

int _clampedFare(String raw, double maxFare) {
  final value = int.tryParse(raw.trim()) ?? 0;
  return value.clamp(0, math.max(0, maxFare.round())).toInt();
}

class _FareSliderField extends StatelessWidget {
  const _FareSliderField({
    required this.controller,
    required this.label,
    required this.suggested,
    required this.maxFare,
    required this.currency,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final int suggested;
  final double maxFare;
  final CurrencyOption currency;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final maxValue = math.max(1.0, maxFare);
    final current = (int.tryParse(controller.text.trim()) ?? 0)
        .clamp(0, maxValue.round())
        .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.payments),
            helperText: enabled
                ? 'Suggested ${suggested == 0 ? '-' : money(suggested.toDouble(), currency)} · max ${money(maxValue, currency)}'
                : 'Selected aircraft has no business cabin.',
          ),
          onChanged: (_) => onChanged(),
        ),
        Slider(
          value: enabled ? current : 0,
          min: 0,
          max: maxValue,
          divisions: math.min(maxValue.round(), 200),
          label: money(current, currency),
          onChanged: !enabled
              ? null
              : (value) {
                  controller.text = value.round().toString();
                  onChanged();
                },
        ),
      ],
    );
  }
}

class _RouteEditDialog extends StatefulWidget {
  const _RouteEditDialog({
    required this.game,
    required this.route,
    required this.currency,
  });
  final GameController game;
  final RoutePlan route;
  final CurrencyOption currency;

  @override
  State<_RouteEditDialog> createState() => _RouteEditDialogState();
}

class _RouteEditDialogState extends State<_RouteEditDialog> {
  late int flights = widget.route.flightsPerWeek;
  late final ecoController = TextEditingController(
    text: widget.route.priceEconomy.toString(),
  );
  late final bizController = TextEditingController(
    text: widget.route.priceBusiness.toString(),
  );
  var buyManufacturer = 'All';
  String? aircraftError;
  var confirmDelete = false;

  @override
  void dispose() {
    ecoController.dispose();
    bizController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.game.routes[widget.route.id] ?? widget.route;
    final origin = widget.game.airportByIata(route.originIata);
    final destination = widget.game.airportByIata(route.destinationIata);
    final ac = route.aircraftId == null
        ? null
        : widget.game.aircraft[route.aircraftId!];
    final type = ac == null ? null : aircraftTypesById[ac.typeId];
    final hasBusiness = (type?.seatsBusiness ?? 0) > 0;
    final fareGuide =
        type == null || ac == null || origin == null || destination == null
        ? _FareGuide.fromCurrent(route.priceEconomy, route.priceBusiness)
        : _fareGuideForRoute(
            route: route.copyWith(flightsPerWeek: flights),
            aircraft: ac,
            type: type,
            origin: origin,
            destination: destination,
            fuelPrice: widget.game.globalFuelPrice,
            gameDay: widget.game.gameDay,
          );
    final previewRoute = route.copyWith(
      flightsPerWeek: flights,
      priceEconomy: _clampedFare(ecoController.text, fareGuide.maxEconomy),
      priceBusiness: hasBusiness
          ? _clampedFare(bizController.text, fareGuide.maxBusiness)
          : 0,
    );
    final previewEconomics =
        type == null || ac == null || origin == null || destination == null
        ? null
        : calculateRouteEconomics(
            route: previewRoute,
            aircraft: ac,
            type: type,
            origin: origin,
            destination: destination,
            airline: widget.game.player,
            allRoutes: widget.game.routes.values.toList(growable: false),
            allAirlines: widget.game.airlines.values.toList(growable: false),
            globalFuelPrice: widget.game.globalFuelPrice,
            gameDay: widget.game.gameDay,
          );
    final eligibleAircraft = widget.game.playerFleet.where((candidate) {
      if (candidate.id == route.aircraftId) return false;
      if (candidate.status == AircraftStatus.maintenance) return false;
      final candidateType = aircraftTypesById[candidate.typeId];
      if (candidateType == null || origin == null || destination == null) {
        return false;
      }
      return candidateType.rangeKm >= route.distanceKm &&
          canAirportHandleAircraft(origin, candidateType) &&
          canAirportHandleAircraft(destination, candidateType);
    }).toList();
    final manufacturers = [
      'All',
      ...aircraftTypes.map((type) => type.manufacturer).toSet().toList()
        ..sort(),
    ];
    final shopTypes = aircraftTypes
        .where((candidateType) {
          final byManufacturer =
              buyManufacturer == 'All' ||
              candidateType.manufacturer == buyManufacturer;
          final fits =
              origin != null &&
              destination != null &&
              candidateType.rangeKm >= route.distanceKm &&
              canAirportHandleAircraft(origin, candidateType) &&
              canAirportHandleAircraft(destination, candidateType);
          return byManufacturer && fits;
        })
        .take(80)
        .toList();
    return AlertDialog(
      title: Text('${route.originIata} -> ${route.destinationIata}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Flights per week: $flights'),
              Slider(
                value: flights.toDouble(),
                min: 1,
                max: 21,
                divisions: 20,
                label: '$flights/week',
                onChanged: (value) => setState(() => flights = value.round()),
              ),
              _FareSliderField(
                controller: ecoController,
                label: 'Economy fare (${widget.currency.code})',
                suggested: fareGuide.suggestedEconomy,
                maxFare: fareGuide.maxEconomy,
                currency: widget.currency,
                enabled: true,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 10),
              _FareSliderField(
                controller: bizController,
                label: hasBusiness
                    ? 'Business fare (${widget.currency.code})'
                    : 'No business cabin',
                suggested: fareGuide.suggestedBusiness,
                maxFare: fareGuide.maxBusiness,
                currency: widget.currency,
                enabled: hasBusiness,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
              _RoutePreviewCard(
                current: route,
                preview: previewEconomics?.route,
                currency: widget.currency,
              ),
              const SizedBox(height: 12),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Assigned aircraft',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    if (ac == null)
                      const Text(
                        'No aircraft assigned. The route is inactive until one is assigned.',
                        style: TextStyle(color: Color(0xff9aa4b5)),
                      )
                    else ...[
                      Text(
                        '${ac.name} · ${type?.displayName ?? ac.typeId}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${ac.condition.toStringAsFixed(0)}% condition · ${type == null ? '' : '${type.rangeKm} km range'}',
                        style: const TextStyle(color: Color(0xff9aa4b5)),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              widget.game.assignAircraftToRoute(ac.id, null);
                              setState(() => aircraftError = null);
                            },
                            icon: const Icon(Icons.link_off),
                            label: const Text('Unassign'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              try {
                                widget.game.sellAircraft(ac.id);
                                setState(() => aircraftError = null);
                              } catch (e) {
                                setState(() => aircraftError = e.toString());
                              }
                            },
                            icon: const Icon(Icons.sell),
                            label: const Text('Sell aircraft'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: null,
                      decoration: const InputDecoration(
                        labelText: 'Assign existing aircraft',
                      ),
                      items: eligibleAircraft.map((candidate) {
                        final candidateType =
                            aircraftTypesById[candidate.typeId];
                        return DropdownMenuItem(
                          value: candidate.id,
                          child: Text(
                            '${candidate.name} · ${candidateType?.model ?? candidate.typeId}',
                          ),
                        );
                      }).toList(),
                      onChanged: eligibleAircraft.isEmpty
                          ? null
                          : (id) {
                              if (id == null) return;
                              try {
                                widget.game.assignAircraftToRoute(id, route.id);
                                setState(() => aircraftError = null);
                              } catch (e) {
                                setState(() => aircraftError = e.toString());
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: buyManufacturer,
                      decoration: const InputDecoration(
                        labelText: 'Manufacturer',
                      ),
                      items: manufacturers
                          .map(
                            (manufacturer) => DropdownMenuItem(
                              value: manufacturer,
                              child: Text(manufacturer),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => buyManufacturer = value);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: null,
                      decoration: const InputDecoration(
                        labelText: 'Buy new and assign',
                      ),
                      items: shopTypes
                          .map(
                            (candidateType) => DropdownMenuItem(
                              value: candidateType.id,
                              enabled:
                                  widget.game.player.cashUSD >=
                                  candidateType.purchasePrice,
                              child: Text(
                                '${candidateType.displayName} · ${money(candidateType.purchasePrice, widget.currency)}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: shopTypes.isEmpty
                          ? null
                          : (typeId) {
                              if (typeId == null) return;
                              try {
                                widget.game.buyAircraftForRoute(
                                  typeId,
                                  route.id,
                                );
                                setState(() => aircraftError = null);
                              } catch (e) {
                                setState(() => aircraftError = e.toString());
                              }
                            },
                    ),
                    if (aircraftError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          aircraftError!,
                          style: const TextStyle(color: Color(0xffff6b6b)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final result = widget.game.optimiseRoute(route.id);
                        setState(() {
                          flights = result.flightsPerWeek;
                          ecoController.text = result.priceEconomy.toString();
                          bizController.text = result.priceBusiness.toString();
                        });
                      },
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Optimise'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => widget.game.updateRouteSettings(
                        route.id,
                        isActive: !route.isActive,
                      ),
                      icon: Icon(
                        route.isActive ? Icons.pause_circle : Icons.play_circle,
                      ),
                      label: Text(route.isActive ? 'Suspend' : 'Resume'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  if (!confirmDelete) {
                    setState(() => confirmDelete = true);
                    return;
                  }
                  widget.game.deleteRoute(route.id);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.delete_outline),
                label: Text(
                  confirmDelete ? 'Confirm delete route' : 'Delete route',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xffff6b6b),
                ),
              ),
              if (confirmDelete)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'This removes the route and returns its aircraft to idle.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xffffb4b4)),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.game.updateRouteSettings(
              route.id,
              flightsPerWeek: flights,
              priceEconomy: _clampedFare(
                ecoController.text,
                fareGuide.maxEconomy,
              ),
              priceBusiness: hasBusiness
                  ? _clampedFare(bizController.text, fareGuide.maxBusiness)
                  : 0,
            );
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _CreateRouteDialog extends StatefulWidget {
  const _CreateRouteDialog({
    required this.game,
    required this.currency,
    this.origin,
    this.destination,
  });
  final GameController game;
  final CurrencyOption currency;
  final Airport? origin;
  final Airport? destination;
  @override
  State<_CreateRouteDialog> createState() => _CreateRouteDialogState();
}

class _CreateRouteDialogState extends State<_CreateRouteDialog> {
  late Airport origin = widget.origin ?? airportsByIata['LHR']!;
  late Airport destination = widget.destination ?? airportsByIata['JFK']!;
  late AircraftType type = aircraftTypesById['b707-120'] ?? aircraftTypes.first;
  late final ecoController = TextEditingController();
  late final bizController = TextEditingController();
  int flights = 7;
  bool optimise = true;
  String? error;

  @override
  void dispose() {
    ecoController.dispose();
    bizController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distance = haversineKm(
      origin.lat,
      origin.lon,
      destination.lat,
      destination.lon,
    );
    final gameYear =
        widget.game.settings.startingYear + widget.game.gameDay ~/ 365;
    final viableAircraft = aircraftTypes
        .where(
          (t) =>
              t.yearIntroduced <= gameYear &&
              t.rangeKm >= distance &&
              canAirportHandleAircraft(origin, t) &&
              canAirportHandleAircraft(destination, t),
        )
        .take(90)
        .toList();
    if (!viableAircraft.contains(type) && viableAircraft.isNotEmpty)
      type = viableAircraft.first;
    final fareGuide = _currentFareGuide(distance);
    final previewRoute = _previewRoute(distance, fareGuide);
    final previewAircraft = Aircraft(
      id: 'preview',
      typeId: type.id,
      name: type.displayName,
      airlineId: 'player',
      purchasedGameDay: widget.game.gameDay,
    );
    final previewEconomics = viableAircraft.isEmpty
        ? null
        : calculateRouteEconomics(
            route: previewRoute,
            aircraft: previewAircraft,
            type: type,
            origin: origin,
            destination: destination,
            airline: widget.game.player,
            allRoutes: widget.game.routes.values.toList(growable: false),
            allAirlines: widget.game.airlines.values.toList(growable: false),
            globalFuelPrice: widget.game.globalFuelPrice,
            gameDay: widget.game.gameDay,
          );
    return AlertDialog(
      title: const Text('Create route'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AirportDropdown(
              label: 'Origin',
              value: origin,
              onChanged: (a) => setState(() => origin = a),
            ),
            const SizedBox(height: 10),
            _AirportDropdown(
              label: 'Destination',
              value: destination,
              onChanged: (a) => setState(() => destination = a),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<AircraftType>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Aircraft'),
              items: viableAircraft
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Text(
                        '${t.displayName} · ${money(t.purchasePrice, widget.currency)}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => type = v);
              },
            ),
            const SizedBox(height: 10),
            Text('Flights per week: $flights'),
            Slider(
              value: flights.toDouble(),
              min: 1,
              max: 21,
              divisions: 20,
              label: '$flights/week',
              onChanged: (v) => setState(() => flights = v.round()),
            ),
            _FareSliderField(
              controller: ecoController,
              label: 'Economy fare (${widget.currency.code})',
              suggested: fareGuide.suggestedEconomy,
              maxFare: fareGuide.maxEconomy,
              currency: widget.currency,
              enabled: true,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 10),
            _FareSliderField(
              controller: bizController,
              label: type.seatsBusiness > 0
                  ? 'Business fare (${widget.currency.code})'
                  : 'No business cabin',
              suggested: fareGuide.suggestedBusiness,
              maxFare: fareGuide.maxBusiness,
              currency: widget.currency,
              enabled: type.seatsBusiness > 0,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 12),
            _RoutePreviewCard(
              current: previewRoute,
              preview: previewEconomics?.route,
              currency: widget.currency,
            ),
            const SizedBox(height: 12),
            _Card(
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Route optimiser',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Finds the best frequency and fares before creation.',
                          style: TextStyle(color: Color(0xff9aa4b5)),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: viableAircraft.isEmpty ? null : _optimiseSetup,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Optimise'),
                  ),
                ],
              ),
            ),
            CheckboxListTile(
              value: optimise,
              onChanged: (v) => setState(() => optimise = v ?? true),
              title: const Text('Optimise after creation'),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Color(0xffff6b6b))),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: viableAircraft.isEmpty ? null : _create,
          child: Text('Create + buy ${type.model}'),
        ),
      ],
    );
  }

  _FareGuide _currentFareGuide(double distance) {
    final previewRoute = RoutePlan(
      id: 'preview',
      airlineId: 'player',
      originIata: origin.iata,
      destinationIata: destination.iata,
      flightsPerWeek: flights,
      priceEconomy: 0,
      priceBusiness: 0,
      createdGameDay: widget.game.gameDay,
      distanceKm: distance,
    );
    final previewAircraft = Aircraft(
      id: 'preview',
      typeId: type.id,
      name: type.displayName,
      airlineId: 'player',
      purchasedGameDay: widget.game.gameDay,
    );
    return _fareGuideForRoute(
      route: previewRoute,
      aircraft: previewAircraft,
      type: type,
      origin: origin,
      destination: destination,
      fuelPrice: widget.game.globalFuelPrice,
      gameDay: widget.game.gameDay,
    );
  }

  RoutePlan _previewRoute(double distance, _FareGuide fareGuide) => RoutePlan(
    id: 'preview',
    airlineId: 'player',
    originIata: origin.iata,
    destinationIata: destination.iata,
    flightsPerWeek: flights,
    priceEconomy: ecoController.text.trim().isEmpty
        ? fareGuide.suggestedEconomy
        : _clampedFare(ecoController.text, fareGuide.maxEconomy),
    priceBusiness: type.seatsBusiness <= 0 || bizController.text.trim().isEmpty
        ? 0
        : _clampedFare(bizController.text, fareGuide.maxBusiness),
    createdGameDay: widget.game.gameDay,
    distanceKm: distance,
  );

  void _optimiseSetup() {
    final distance = haversineKm(
      origin.lat,
      origin.lon,
      destination.lat,
      destination.lon,
    );
    final fareGuide = _currentFareGuide(distance);
    final previewRoute = _previewRoute(distance, fareGuide);
    final previewAircraft = Aircraft(
      id: 'preview',
      typeId: type.id,
      name: type.displayName,
      airlineId: 'player',
      purchasedGameDay: widget.game.gameDay,
    );
    final result = optimiseRouteSettings(
      RouteOptimisationInput(
        route: previewRoute,
        aircraft: previewAircraft,
        aircraftType: type,
        origin: origin,
        destination: destination,
        globalFuelPrice: widget.game.globalFuelPrice,
        airline: widget.game.player,
        allAirlines: widget.game.airlines.values.toList(growable: false),
        allRoutes: widget.game.routes.values.toList(growable: false),
        gameDay: widget.game.gameDay,
      ),
    );
    setState(() {
      flights = result.flightsPerWeek;
      ecoController.text = result.priceEconomy.toString();
      bizController.text = result.priceBusiness.toString();
      optimise = false;
    });
  }

  void _create() {
    try {
      final distance = haversineKm(
        origin.lat,
        origin.lon,
        destination.lat,
        destination.lon,
      );
      final fareGuide = _currentFareGuide(distance);
      final route = widget.game.createRoute(
        originIata: origin.iata,
        destinationIata: destination.iata,
        aircraftTypeId: type.id,
        flightsPerWeek: flights,
        priceEconomy: ecoController.text.trim().isEmpty
            ? null
            : _clampedFare(ecoController.text, fareGuide.maxEconomy),
        priceBusiness:
            type.seatsBusiness <= 0 || bizController.text.trim().isEmpty
            ? null
            : _clampedFare(bizController.text, fareGuide.maxBusiness),
        buyNewAircraft: true,
      );
      if (optimise) widget.game.optimiseRoute(route.id);
      Navigator.pop(context);
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
    }
  }
}

class _AirportDropdown extends StatelessWidget {
  const _AirportDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final Airport value;
  final ValueChanged<Airport> onChanged;
  @override
  Widget build(BuildContext context) => Autocomplete<Airport>(
    initialValue: TextEditingValue(text: value.iata),
    optionsBuilder: (text) => searchAirports(text.text, airports, limit: 12),
    displayStringForOption: (a) => '${a.iata} · ${a.city}',
    onSelected: onChanged,
    fieldViewBuilder: (context, controller, focus, submit) => TextField(
      controller: controller,
      focusNode: focus,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.flight_takeoff),
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.title, this.value, this.accent);
  final String title;
  final String value;
  final Color accent;
  @override
  Widget build(BuildContext context) => _Card(
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

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _cardSurface(context),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _hairline(context)),
    ),
    child: child,
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0xff9aa4b5)),
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
      color: _panelSurface(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _hairline(context)),
      boxShadow: [
        BoxShadow(
          color: _isLight(context)
              ? Colors.black.withValues(alpha: 0.16)
              : Colors.black.withValues(alpha: 0.54),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
  );
}

bool _isLight(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light;

Color _chromeSurface(BuildContext context) =>
    _isLight(context) ? const Color(0xf7ffffff) : const Color(0xee050915);

Color _panelSurface(BuildContext context) =>
    _isLight(context) ? const Color(0xf7ffffff) : const Color(0xee0b1020);

Color _cardSurface(BuildContext context) =>
    _isLight(context) ? const Color(0xfff8fafc) : const Color(0xff151b2b);

Color _subtleSurface(BuildContext context) => _isLight(context)
    ? const Color(0xffeef2f7)
    : Colors.white.withValues(alpha: 0.04);

Color _hairline(BuildContext context) => _isLight(context)
    ? const Color(0xffd3dce8)
    : Colors.white.withValues(alpha: 0.12);

Color _mutedText(BuildContext context) =>
    _isLight(context) ? const Color(0xff64748b) : const Color(0xff9aa4b5);

class _Ticker extends StatefulWidget {
  const _Ticker({required this.game});
  final GameController game;

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  var index = 0;
  var animationCycle = 0;

  @override
  void didUpdateWidget(covariant _Ticker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final items = _items;
    if (index >= items.length) {
      index = 0;
      return;
    }
    final currentId = items[index].id;
    if (!items.any((item) => item.id == currentId)) index = 0;
  }

  List<NewsTickerItem> get _items => widget.game.newsTicker.isEmpty
      ? const [
          NewsTickerItem(
            id: 'fallback',
            text: 'Welcome to Mighty Airline Empire!',
          ),
        ]
      : widget.game.newsTicker.take(8).toList(growable: false);

  void _advanceTicker() {
    if (!mounted) return;
    final items = _items;
    setState(() {
      index = items.isEmpty ? 0 : (index + 1) % items.length;
      animationCycle += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final item = items[index.clamp(0, items.length - 1)];
    final speed = widget.game.speed == 0
        ? 1
        : (widget.game.speed / 300).round();
    final article = item.articleId == null
        ? null
        : widget.game.newsArticles[item.articleId!];
    final isAlert =
        item.playerRelated ||
        item.severity == 'fleet' ||
        item.severity == 'breaking';
    final tickerText =
        '${isAlert ? '‼️ ' : ''}${item.text}${article == null ? '' : ' Read the article'}';
    return InkWell(
      onTap: article == null
          ? null
          : () => _showHeraldArticle(
              context,
              widget.game,
              article,
              readOnly: true,
            ),
      child: Container(
        height: 42,
        color: const Color(0xff050915),
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          key: ValueKey('${item.id}-$animationCycle-$speed'),
          tween: Tween(begin: 1, end: -1),
          duration: Duration(
            seconds: speed >= 6
                ? 10
                : speed >= 3
                ? 14
                : speed >= 1
                ? 18
                : 24,
          ),
          onEnd: _advanceTicker,
          builder: (context, value, child) => FractionalTranslation(
            translation: Offset(value, 0),
            child: child,
          ),
          child: Text(
            '  $tickerText     $tickerText',
            maxLines: 1,
            style: TextStyle(
              color: article != null || isAlert
                  ? const Color(0xffffd166)
                  : const Color(0xffc7d2e5),
              fontWeight: article != null || isAlert
                  ? FontWeight.w900
                  : FontWeight.w700,
              decoration: article == null
                  ? TextDecoration.none
                  : TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }
}

void _showHeraldArticle(
  BuildContext context,
  GameController game,
  NewsArticle article, {
  bool readOnly = false,
}) {
  void dismiss(BuildContext dialogContext) {
    if (!readOnly) game.popNewspaper(article.id);
    Navigator.pop(dialogContext);
  }

  final severity = article.severity.toLowerCase();
  final accent = severity == 'crash' || severity == 'breaking'
      ? const Color(0xffb91c1c)
      : severity == 'grounding'
      ? const Color(0xffea580c)
      : const Color(0xff2563eb);
  final label = severity == 'crash' || severity == 'breaking'
      ? 'BREAKING NEWS'
      : severity == 'grounding'
      ? 'AVIATION ALERT'
      : 'INCIDENT REPORT';
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xfff5f0e8),
      surfaceTintColor: Colors.transparent,
      contentPadding: EdgeInsets.zero,
      contentTextStyle: const TextStyle(color: Color(0xff1a1008)),
      content: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(height: 6, color: accent),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.flight_takeoff,
                            color: Color(0xff1a1008),
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'THE AVIATION HERALD',
                              style: TextStyle(
                                fontFamily: 'Georgia',
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                                fontSize: 16,
                                color: Color(0xff1a1008),
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              Text(
                                'DAY ${article.gameDay}',
                                style: const TextStyle(
                                  color: Color(0x991a1008),
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(height: 22, color: Color(0xff1a1008)),
                      Text(
                        article.headline.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xff1a1008),
                          fontFamily: 'Georgia',
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        article.subheadline,
                        style: const TextStyle(
                          color: Color(0xcc1a1008),
                          fontFamily: 'Georgia',
                          fontStyle: FontStyle.italic,
                          fontSize: 15,
                          height: 1.3,
                        ),
                      ),
                      const Divider(height: 24, color: Color(0x331a1008)),
                      ...article.paragraphs.indexed.map((entry) {
                        final paragraph = entry.$2;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: RichText(
                            textAlign: TextAlign.justify,
                            text: TextSpan(
                              style: const TextStyle(
                                color: Color(0xff1a1008),
                                fontFamily: 'Georgia',
                                fontSize: 15,
                                height: 1.42,
                              ),
                              children: entry.$1 == 0 && paragraph.isNotEmpty
                                  ? [
                                      TextSpan(
                                        text: paragraph[0],
                                        style: const TextStyle(
                                          fontSize: 46,
                                          height: 0.9,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      TextSpan(text: paragraph.substring(1)),
                                    ]
                                  : [TextSpan(text: paragraph)],
                            ),
                          ),
                        );
                      }),
                      if (article.actionAircraftId != null && !readOnly)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Divider(color: Color(0x331a1008)),
                              const Text(
                                'Your operations team requires a decision.',
                                style: TextStyle(
                                  color: Color(0xcc1a1008),
                                  fontFamily: 'Georgia',
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: () {
                                  game.startMaintenance(
                                    article.actionAircraftId!,
                                    MaintenanceTier.standard,
                                  );
                                  dismiss(dialogContext);
                                },
                                icon: const Icon(Icons.build),
                                label: Text(
                                  'Send to maintenance (${article.actionMaintenanceCost ?? 0} USD)',
                                ),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: () {
                                  game.updateMaintenancePolicy(
                                    game.player.maintenancePolicy.copyWith(
                                      enabled: true,
                                      autoMaintainIssues: true,
                                    ),
                                  );
                                  game.startMaintenance(
                                    article.actionAircraftId!,
                                    MaintenanceTier.standard,
                                  );
                                  dismiss(dialogContext);
                                },
                                icon: const Icon(Icons.engineering),
                                label: const Text(
                                  'Always maintain aircraft with issues',
                                ),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: () {
                                  game.keepIssueAircraftFlying(
                                    article.actionAircraftId!,
                                  );
                                  dismiss(dialogContext);
                                },
                                icon: const Icon(Icons.warning_amber),
                                label: const Text('Keep flying'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xffb91c1c),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => dismiss(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
