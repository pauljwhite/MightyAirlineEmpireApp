import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart' show LatLng;

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

const _speedOptions = <({int value, String label})>[
  (value: 60, label: '1x'),
  (value: 300, label: '2x'),
  (value: 1200, label: '3x'),
  (value: 3600, label: '4x'),
  (value: 14400, label: '5x'),
];

void main() => runApp(const MightyAirlineEmpireApp());

class MightyAirlineEmpireApp extends StatefulWidget {
  const MightyAirlineEmpireApp({super.key});
  @override
  State<MightyAirlineEmpireApp> createState() => _MightyAirlineEmpireAppState();
}

class _MightyAirlineEmpireAppState extends State<MightyAirlineEmpireApp> {
  late final GameController game;
  final _navigatorKey = GlobalKey<NavigatorState>();
  Timer? _gameLoop;
  DateTime? _lastTickAt;
  var _initialNewGameDialogShown = false;
  var currency = currencyOptions.first;
  Airport? selectedAirport = airportsByIata['LHR'];
  _Panel? panel;
  var mobileSearchOpen = false;
  final _autoOpenedArticleIds = <String>{};

  @override
  void initState() {
    super.initState();
    game = GameController(autoStart: false);
    _lastTickAt = DateTime.now();
    _gameLoop = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now();
      final previous = _lastTickAt ?? now;
      _lastTickAt = now;
      final delta = now.difference(previous);
      game.advanceGameClock(
        delta > const Duration(milliseconds: 80)
            ? const Duration(milliseconds: 80)
            : delta,
      );
    });
  }

  void _scheduleInitialNewGameDialog() {
    if (_initialNewGameDialogShown || game.hasStarted) return;
    _initialNewGameDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || game.hasStarted) return;
      final dialogContext = _navigatorKey.currentContext ?? context;
      _showNewGameDialog(
        dialogContext,
        game,
        currency,
        (v) => setState(() => currency = v),
        forceStart: true,
      );
    });
  }

  @override
  void dispose() {
    _gameLoop?.cancel();
    game.dispose();
    super.dispose();
  }

  void _openCreateRoute({
    Airport? origin,
    Airport? destination,
    bool useSelectedAirport = false,
  }) {
    final dialogContext = _navigatorKey.currentContext ?? context;
    final navigator = _navigatorKey.currentState;
    showDialog<void>(
      context: dialogContext,
      builder: (context) => _CreateRouteDialog(
        game: game,
        currency: currency,
        origin: origin ?? (useSelectedAirport ? selectedAirport : null),
        destination: destination,
        onClose: () => navigator?.pop(),
      ),
    );
  }

  void _openRouteDetail(RoutePlan route) {
    final dialogContext = _navigatorKey.currentContext ?? context;
    if (game.airlines[route.airlineId]?.isPlayer == true) {
      showDialog<void>(
        context: dialogContext,
        builder: (context) =>
            _RouteEditDialog(game: game, route: route, currency: currency),
      );
      return;
    }
    showDialog<void>(
      context: dialogContext,
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
      final dialogContext = _navigatorKey.currentContext ?? context;
      _showHeraldArticle(dialogContext, game, article);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: game,
      builder: (context, _) {
        final lightMode = game.themeMode == ThemeModeSetting.light;
        _scheduleInitialNewGameDialog();
        return MaterialApp(
          navigatorKey: _navigatorKey,
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
          home: game.hasStarted
              ? Scaffold(
                  body: SafeArea(
                    bottom: false,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 980;
                        final topOffset = compact
                            ? (mobileSearchOpen ? 132.0 : 92.0)
                            : 72.0;
                        _scheduleHeraldAutoOpen(context);
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: _WorldMap(
                                game: game,
                                showAiOnMap: game.showAiOnMap,
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
                                selectedPanel: panel,
                                onToggleSearch: () => setState(
                                  () => mobileSearchOpen = !mobileSearchOpen,
                                ),
                                onPanel: (p) => setState(
                                  () => panel = panel == p ? null : p,
                                ),
                                onCurrency: (v) => setState(() => currency = v),
                                onSpeed: game.setSpeed,
                                onAirport: (a) => setState(() {
                                  selectedAirport = a;
                                  mobileSearchOpen = false;
                                }),
                              ),
                            ),
                            Positioned(
                              top: topOffset,
                              left: 12,
                              child: _MapToggle(
                                showAi: game.showAiOnMap,
                                onChanged: game.setShowAiOnMap,
                              ),
                            ),
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeInOut,
                              top: topOffset,
                              bottom: 52,
                              right: panel == null
                                  ? -(compact ? constraints.maxWidth : 430) - 32
                                  : 12,
                              width: compact ? constraints.maxWidth - 24 : 430,
                              child: panel == null
                                  ? const SizedBox.shrink()
                                  : _MainPanel(
                                      game: game,
                                      panel: panel!,
                                      currency: currency,
                                      onClose: () =>
                                          setState(() => panel = null),
                                      onCreateRoute: () => _openCreateRoute(),
                                    ),
                            ),
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeInOut,
                              left: selectedAirport == null ? -460 : 12,
                              top: topOffset,
                              bottom: 52,
                              width: compact ? constraints.maxWidth - 24 : 430,
                              child: selectedAirport == null
                                  ? const SizedBox.shrink()
                                  : _AirportPanel(
                                      game: game,
                                      airport: selectedAirport!,
                                      currency: currency,
                                      onClose: () => setState(
                                        () => selectedAirport = null,
                                      ),
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
                )
              : Scaffold(
                  body: SafeArea(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.flight_takeoff, size: 54),
                          const SizedBox(height: 14),
                          Text(
                            'Mighty Airline Empire',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Set up your airline to begin.',
                            style: TextStyle(color: Color(0xff9aa4b5)),
                          ),
                        ],
                      ),
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
    required this.selectedPanel,
    required this.onToggleSearch,
    required this.onPanel,
    required this.onCurrency,
    required this.onSpeed,
    required this.onAirport,
  });
  final GameController game;
  final bool compact;
  final CurrencyOption currency;
  final bool searchOpen;
  final _Panel? selectedPanel;
  final VoidCallback onToggleSearch;
  final ValueChanged<_Panel> onPanel;
  final ValueChanged<CurrencyOption> onCurrency;
  final ValueChanged<int> onSpeed;
  final ValueChanged<Airport> onAirport;
  @override
  Widget build(BuildContext context) {
    final search = _SearchBox(onAirport: onAirport);
    final speedValue = game.speed == 0 ? 0 : game.speed;
    final nav = _PanelNav(
      selectedPanel: selectedPanel,
      onPanel: onPanel,
      compact: compact,
    );
    return Container(
      decoration: BoxDecoration(
        color: _chromeSurface(context),
        border: Border(bottom: BorderSide(color: _hairline(context))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AirlineBadge(
                      game: game,
                      currency: currency,
                      onCurrency: onCurrency,
                      compact: compact,
                    ),
                    const SizedBox(width: 6),
                    _DateBadge(game: game, compact: compact),
                    const SizedBox(width: 6),
                    _SpeedControl(
                      compact: compact,
                      speedValue: speedValue,
                      onSpeed: onSpeed,
                    ),
                    IconButton(
                      tooltip: 'Advance day',
                      onPressed: game.runDailyTick,
                      icon: const Icon(Icons.skip_next),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: search,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else
                  const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (compact)
                      IconButton(
                        tooltip: 'Search airports',
                        onPressed: onToggleSearch,
                        icon: Icon(searchOpen ? Icons.close : Icons.search),
                        visualDensity: VisualDensity.compact,
                      ),
                    nav,
                  ],
                ),
              ],
            ),
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

class _PanelNav extends StatelessWidget {
  const _PanelNav({
    required this.selectedPanel,
    required this.onPanel,
    required this.compact,
  });

  final _Panel? selectedPanel;
  final ValueChanged<_Panel> onPanel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return PopupMenuButton<_Panel>(
        tooltip: 'Panels',
        initialValue: selectedPanel,
        onSelected: onPanel,
        icon: Icon(
          selectedPanel == null
              ? Icons.dashboard_customize
              : _panelIcon(selectedPanel!),
        ),
        itemBuilder: (context) => _Panel.values
            .map(
              (panel) => PopupMenuItem(
                value: panel,
                child: Row(
                  children: [
                    Icon(_panelIcon(panel), size: 18),
                    const SizedBox(width: 10),
                    Text(_panelLabel(panel)),
                  ],
                ),
              ),
            )
            .toList(),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _Panel.values
            .map(
              (panel) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _PanelNavButton(
                  panel: panel,
                  selected: selectedPanel == panel,
                  onTap: () => onPanel(panel),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PanelNavButton extends StatelessWidget {
  const _PanelNavButton({
    required this.panel,
    required this.selected,
    required this.onTap,
  });

  final _Panel panel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: _panelLabel(panel),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xff2f8cff).withValues(alpha: 0.2)
              : _subtleSurface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xff77c9ff) : _hairline(context),
          ),
        ),
        child: Icon(
          _panelIcon(panel),
          size: 18,
          color: selected ? const Color(0xff77c9ff) : null,
        ),
      ),
    ),
  );
}

class _SpeedControl extends StatelessWidget {
  const _SpeedControl({
    required this.compact,
    required this.speedValue,
    required this.onSpeed,
  });

  final bool compact;
  final int speedValue;
  final ValueChanged<int> onSpeed;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return PopupMenuButton<int>(
        tooltip: 'Game speed',
        initialValue: speedValue,
        onSelected: onSpeed,
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 0,
            child: Row(
              children: [
                Icon(Icons.pause, size: 18),
                SizedBox(width: 10),
                Text('Paused'),
              ],
            ),
          ),
          ..._speedOptions.map(
            (option) =>
                PopupMenuItem(value: option.value, child: Text(option.label)),
          ),
        ],
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _subtleSurface(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _hairline(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(speedValue == 0 ? Icons.pause : Icons.speed, size: 17),
              const SizedBox(width: 5),
              Text(
                speedValue == 0 ? 'Pause' : _speedLabel(speedValue),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: _subtleSurface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _hairline(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SpeedSegment(
            selected: speedValue == 0,
            tooltip: 'Pause',
            width: 28,
            onTap: () => onSpeed(0),
            child: const Icon(Icons.pause, size: 13),
          ),
          ..._speedOptions.map(
            (option) => _SpeedSegment(
              selected: speedValue == option.value,
              tooltip: option.label,
              width: 28,
              onTap: () => onSpeed(option.value),
              child: Text(
                option.label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedSegment extends StatelessWidget {
  const _SpeedSegment({
    required this.selected,
    required this.tooltip,
    required this.width,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final String tooltip;
  final double width;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final selectedColor = const Color(0xff2f8cff).withValues(alpha: 0.22);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: width,
          height: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? selectedColor : Colors.transparent,
            border: Border(
              right: BorderSide(
                color: _hairline(context).withValues(alpha: .7),
              ),
            ),
          ),
          child: IconTheme(
            data: IconThemeData(
              color: selected ? const Color(0xff77c9ff) : null,
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: selected ? const Color(0xff77c9ff) : null,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

String _speedLabel(int speed) {
  for (final option in _speedOptions) {
    if (option.value == speed) return option.label;
  }
  return '${speed}x';
}

IconData _panelIcon(_Panel panel) => switch (panel) {
  _Panel.routes => Icons.alt_route,
  _Panel.fleet => Icons.flight,
  _Panel.finance => Icons.account_balance_wallet,
  _Panel.competitors => Icons.groups,
  _Panel.hubs => Icons.apartment,
};

String _panelLabel(_Panel panel) => switch (panel) {
  _Panel.routes => 'Routes',
  _Panel.fleet => 'Fleet',
  _Panel.finance => 'Finance',
  _Panel.competitors => 'Rivals',
  _Panel.hubs => 'Hubs',
};

class _AirlineBadge extends StatelessWidget {
  const _AirlineBadge({
    required this.game,
    required this.currency,
    required this.onCurrency,
    required this.compact,
  });
  final GameController game;
  final CurrencyOption currency;
  final ValueChanged<CurrencyOption> onCurrency;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final muted = _mutedText(context);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      menuChildren: [
        _AirlineProfileDropdown(
          game: game,
          currency: currency,
          onCurrency: onCurrency,
        ),
      ],
      builder: (context, controller, child) => InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () {
          controller.isOpen ? controller.close() : controller.open();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _cardSurface(context),
            border: Border.all(color: _hairline(context)),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AirlineLogo(logo: game.player.logoEmoji, size: 28),
              if (!compact) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.player.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      money(game.player.cashUSD, currency),
                      style: TextStyle(
                        color: game.player.cashUSD >= 0
                            ? const Color(0xff25c96b)
                            : const Color(0xffff6b6b),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
              ],
              Icon(Icons.expand_more, size: 18, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AirlineProfileDropdown extends StatelessWidget {
  const _AirlineProfileDropdown({
    required this.game,
    required this.currency,
    required this.onCurrency,
  });

  final GameController game;
  final CurrencyOption currency;
  final ValueChanged<CurrencyOption> onCurrency;

  @override
  Widget build(BuildContext context) {
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
    final width = math.min(430.0, MediaQuery.sizeOf(context).width - 24);
    void closeMenu() => MenuController.maybeOf(context)?.close();

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: MediaQuery.sizeOf(context).height - 92,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _chromeSurface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _hairline(context)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 28,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _AirlineLogo(logo: player.logoEmoji, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        player.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
                _Card(
                  child: DropdownButtonFormField<CurrencyOption>(
                    initialValue: currency,
                    decoration: const InputDecoration(
                      labelText: 'Display currency',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: currencyOptions
                        .map(
                          (option) => DropdownMenuItem(
                            value: option,
                            child: Text('${option.code} · ${option.symbol}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      onCurrency(value);
                      closeMenu();
                    },
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        closeMenu();
                        _showRebrandDialog(context, game, currency);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Rebrand'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        closeMenu();
                        _showExportDialog(context, game);
                      },
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Export'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        closeMenu();
                        _showImportDialog(context, game, onCurrency);
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('Import'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        closeMenu();
                        _showSettingsDialog(context, game);
                      },
                      icon: const Icon(Icons.palette),
                      label: const Text('Theme'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        closeMenu();
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
      ),
    );
  }
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
  ValueChanged<CurrencyOption> onCurrency, {
  bool forceStart = false,
}) {
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
    barrierDismissible: !forceStart,
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
        return PopScope(
          canPop: !forceStart,
          child: AlertDialog(
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
                              labelText:
                                  'Logo emoji, short mark, or data:image',
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _mutedText(context),
                      ),
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
              if (!forceStart)
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
          ),
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
  const _DateBadge({required this.game, required this.compact});
  final GameController game;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final date = DateTime(
      game.settings.startingYear,
      1,
      1,
    ).add(Duration(days: game.gameDay));
    final dayMs = game.gameTimeMs % gameDayMs;
    final hour = (dayMs ~/ 3600000).toString().padLeft(2, '0');
    final minute = ((dayMs % 3600000) ~/ 60000).toString().padLeft(2, '0');
    final label = compact
        ? '${_monthLabel(date.month)} ${date.day} · $hour:$minute'
        : '${_monthLabel(date.month)} ${date.day}, ${date.year} · $hour:$minute';
    return Container(
      width: compact ? 132 : 178,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xff111827),
        border: Border.all(color: const Color(0xff263247)),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        label,
        textAlign: TextAlign.left,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

String _monthLabel(int month) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][(month - 1).clamp(0, 11)];

@immutable
class _SingleWorldEpsg3857 extends Epsg3857 {
  const _SingleWorldEpsg3857();

  @override
  bool get replicatesWorldLongitude => false;
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

class _WorldMap extends StatefulWidget {
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
  State<_WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<_WorldMap> {
  final MapController _mapController = MapController();
  final LayerHitNotifier<RoutePlan> _routeHitNotifier = ValueNotifier(null);
  String? _lastFocusedAirportIata;
  double? _trackpadZoomStart;
  var _mapReady = false;

  @override
  void didUpdateWidget(covariant _WorldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedAirport?.iata != widget.selectedAirport?.iata) {
      _focusSelectedAirport();
    }
  }

  @override
  void dispose() {
    _routeHitNotifier.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _focusSelectedAirport() {
    final airport = widget.selectedAirport;
    if (!_mapReady ||
        airport == null ||
        airport.iata == _lastFocusedAirportIata) {
      return;
    }
    _lastFocusedAirportIata = airport.iata;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.selectedAirport?.iata != airport.iata) return;
      final currentZoom = _mapController.camera.zoom;
      _mapController.move(
        LatLng(airport.lat, airport.lon),
        math.max(currentZoom, 4.1),
        id: 'selected-airport-${airport.iata}',
      );
    });
  }

  void _handleMapReady() {
    _mapReady = true;
    _focusSelectedAirport();
  }

  void _handleTrackpadPinchStart(PointerPanZoomStartEvent event) {
    if (!_mapReady) return;
    _trackpadZoomStart = _mapController.camera.zoom;
  }

  void _handleTrackpadPinchUpdate(PointerPanZoomUpdateEvent event) {
    if (!_mapReady || event.scale <= 0) return;
    final startZoom = _trackpadZoomStart ?? _mapController.camera.zoom;
    final minZoom = 1.8;
    final maxZoom = 8.0;
    final newZoom = (startZoom + math.log(event.scale) / math.ln2).clamp(
      minZoom,
      maxZoom,
    );
    if ((newZoom - _mapController.camera.zoom).abs() < 0.005) return;
    _mapController.move(
      _mapController.camera.focusedZoomCenter(event.localPosition, newZoom),
      newZoom,
      id: 'trackpad-pinch',
    );
  }

  void _handleTrackpadPinchEnd(PointerPanZoomEndEvent event) {
    _trackpadZoomStart = null;
  }

  @override
  Widget build(BuildContext context) {
    final drawableRoutes = _drawableRoutes().toList(growable: false);
    final lightMap = widget.game.themeMode == ThemeModeSetting.light;

    return Listener(
      onPointerPanZoomStart: _handleTrackpadPinchStart,
      onPointerPanZoomUpdate: _handleTrackpadPinchUpdate,
      onPointerPanZoomEnd: _handleTrackpadPinchEnd,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          crs: const _SingleWorldEpsg3857(),
          initialCenter: widget.selectedAirport == null
              ? const LatLng(26, 12)
              : LatLng(
                  widget.selectedAirport!.lat,
                  widget.selectedAirport!.lon,
                ),
          initialZoom: 2.05,
          minZoom: 1.8,
          maxZoom: 8,
          onMapReady: _handleMapReady,
          cameraConstraint: CameraConstraint.containCenter(
            bounds: LatLngBounds(
              const LatLng(-85, -180),
              const LatLng(85, 180),
            ),
          ),
          interactionOptions: const InteractionOptions(
            flags:
                InteractiveFlag.drag |
                InteractiveFlag.pinchZoom |
                InteractiveFlag.pinchMove |
                InteractiveFlag.scrollWheelZoom |
                InteractiveFlag.doubleTapZoom |
                InteractiveFlag.doubleTapDragZoom,
            enableMultiFingerGestureRace: true,
            pinchZoomThreshold: 0.08,
            pinchMoveThreshold: 8,
          ),
          backgroundColor: lightMap
              ? const Color(0xffdbe8f3)
              : const Color(0xff08111f),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'mighty_airline_empire_app',
            panBuffer: 2,
            keepBuffer: 4,
            tileProvider: NetworkTileProvider(
              abortObsoleteRequests: false,
              cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
                maxCacheSize: 500000000,
              ),
            ),
            tileBuilder: (context, tileWidget, tile) {
              if (lightMap) {
                return Opacity(opacity: 0.96, child: tileWidget);
              }
              return ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0.42,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0.46,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0.56,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]),
                child: Opacity(opacity: 0.7, child: tileWidget),
              );
            },
          ),
          MouseRegion(
            hitTestBehavior: HitTestBehavior.deferToChild,
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onTap: () {
                final route = _routeHitNotifier.value?.hitValues.lastOrNull;
                if (route != null) widget.onRouteSelected(route);
              },
              child: PolylineLayer<RoutePlan>(
                hitNotifier: _routeHitNotifier,
                minimumHitbox: 28,
                drawInSingleWorld: true,
                simplificationTolerance: 0,
                polylines: _routePolylines(drawableRoutes),
              ),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: widget.game.mapAnimationTick,
            builder: (context, _, _) =>
                MarkerLayer(markers: _planeMarkers(drawableRoutes)),
          ),
          MarkerLayer(markers: _airportMarkers()),
          RichAttributionWidget(
            showFlutterMapAttribution: false,
            attributions: [
              TextSourceAttribution('OpenStreetMap contributors', onTap: () {}),
            ],
          ),
        ],
      ),
    );
  }

  Iterable<RoutePlan> _drawableRoutes() =>
      widget.game.routes.values.where((route) {
        if (!route.isActive || route.aircraftId == null) return false;
        if (widget.showAiOnMap) return true;
        return widget.game.airlines[route.airlineId]?.isPlayer == true;
      });

  List<Polyline<RoutePlan>> _routePolylines(List<RoutePlan> drawableRoutes) {
    final lines = <Polyline<RoutePlan>>[];
    for (final route in drawableRoutes) {
      final origin = airportsByIata[route.originIata];
      final dest = airportsByIata[route.destinationIata];
      if (origin == null || dest == null) continue;
      final airline = widget.game.airlines[route.airlineId];
      final isPlayer = airline?.isPlayer == true;
      final color = _colorFromHex(airline?.color ?? '#2f8cff');
      for (final segment in _routeArcLatLngSegments(origin, dest)) {
        lines.add(
          Polyline<RoutePlan>(
            points: segment,
            color: color.withValues(alpha: isPlayer ? 0.9 : 0.5),
            borderColor: color.withValues(alpha: isPlayer ? 0.24 : 0.14),
            borderStrokeWidth: isPlayer ? 5.5 : 4,
            strokeWidth: isPlayer ? 2.6 : 1.6,
            hitValue: route,
          ),
        );
      }
    }
    return lines;
  }

  List<Marker> _airportMarkers() => airports
      .map((a) {
        final airport = widget.game.airportByIata(a.iata) ?? a;
        final closedUntil = airport.closedUntilGameDay;
        final isClosed =
            closedUntil != null && closedUntil >= widget.game.gameDay;
        final selected = widget.selectedAirport?.iata == a.iata;
        final playerHub = widget.game.player.hubIatas.contains(a.iata);
        final aiHub = widget.game.competitors.any(
          (airline) => airline.hubIatas.contains(a.iata),
        );
        final radius = switch (a.size) {
          AirportSize.small => 2.2,
          AirportSize.medium => 3.0,
          AirportSize.large => 4.0,
          AirportSize.major => 5.3,
        };
        final color = selected
            ? const Color(0xffffd166)
            : isClosed
            ? const Color(0xffff6b6b)
            : playerHub
            ? const Color(0xffffc857)
            : aiHub
            ? const Color(0xff2dd4bf)
            : const Color(0xff58a6ff);

        return Marker(
          point: LatLng(a.lat, a.lon),
          width: 36,
          height: 36,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onAirportSelected(airport),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: selected ? radius * 2 + 8 : radius * 2,
                height: selected ? radius * 2 + 8 : radius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: isClosed
                      ? Border.all(color: const Color(0xffffb3b3), width: 2)
                      : playerHub || aiHub
                      ? Border.all(color: Colors.white70, width: 1.2)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: selected ? 0.38 : 0.22),
                      blurRadius: selected ? 12 : 6,
                      spreadRadius: selected ? 2 : 0,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      })
      .toList(growable: false);

  List<Marker> _planeMarkers(List<RoutePlan> drawableRoutes) {
    final markers = <Marker>[];
    for (final route in drawableRoutes) {
      final marker = _planeMarker(route);
      if (marker != null) markers.add(marker);
    }
    return markers;
  }

  Marker? _planeMarker(RoutePlan route) {
    final ac = widget.game.aircraft[route.aircraftId];
    if (ac == null ||
        ac.isGrounded ||
        ac.status == AircraftStatus.maintenance ||
        ac.status == AircraftStatus.crashed) {
      return null;
    }
    final origin = airportsByIata[route.originIata];
    final dest = airportsByIata[route.destinationIata];
    if (origin == null || dest == null) return null;

    final visualPoint = roundTripRoutePosition(
      originLat: origin.lat,
      originLon: origin.lon,
      destinationLat: dest.lat,
      destinationLon: dest.lon,
      flightProgress: ac.flightProgress,
    );
    final airline = widget.game.airlines[route.airlineId];
    final color = _colorFromHex(airline?.color ?? '#ffffff');
    final type = aircraftTypesById[ac.typeId];
    final sizePx = switch (type?.category) {
      AircraftCategory.regional => 22.0,
      AircraftCategory.narrowbody => 25.0,
      AircraftCategory.widebody => 30.0,
      AircraftCategory.sst => 29.0,
      null => 25.0,
    };

    return Marker(
      point: LatLng(visualPoint.lat, visualPoint.lon),
      width: sizePx + 12,
      height: sizePx + 12,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: visualPoint.bearingRadians,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: sizePx * 0.68,
                height: sizePx * 0.68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.16),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.18),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              SvgPicture.asset(
                _planeAssetForCategory(type?.category),
                width: sizePx,
                height: sizePx,
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              ),
              SvgPicture.asset(
                _planeAssetForCategory(type?.category),
                width: sizePx,
                height: sizePx,
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(
                  Colors.white.withValues(alpha: 0.16),
                  BlendMode.srcIn,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _planeAssetForCategory(AircraftCategory? category) {
  switch (category) {
    case AircraftCategory.regional:
      return 'assets/map_planes/regional.svg';
    case AircraftCategory.widebody:
      return 'assets/map_planes/widebody.svg';
    case AircraftCategory.sst:
      return 'assets/map_planes/sst.svg';
    case AircraftCategory.narrowbody:
    case null:
      return 'assets/map_planes/narrowbody.svg';
  }
}

List<List<LatLng>> _routeArcLatLngSegments(
  Airport origin,
  Airport destination, {
  int pointCount = 32,
}) {
  final lonDelta = _shortestLonDelta(origin.lon, destination.lon);
  final rawPoints = <({double lat, double lon})>[];
  for (var i = 0; i <= pointCount; i += 1) {
    rawPoints.add(
      _visualArcPoint(
        origin.lat,
        origin.lon,
        destination.lat,
        destination.lon,
        i / pointCount,
        lonDelta: lonDelta,
        normalize: false,
      ),
    );
  }
  return _splitArcAtAntimeridian(rawPoints)
      .map(
        (segment) => segment
            .map((point) => LatLng(point.lat, point.lon))
            .toList(growable: false),
      )
      .where((segment) => segment.length > 1)
      .toList(growable: false);
}

({double lat, double lon}) _visualArcPoint(
  double originLat,
  double originLon,
  double destinationLat,
  double destinationLon,
  double progress, {
  double? lonDelta,
  bool normalize = true,
}) => visualRouteArcPoint(
  originLat,
  originLon,
  destinationLat,
  destinationLon,
  progress,
  lonDelta: lonDelta,
  normalize: normalize,
);

Offset _airportPoint(Airport a, Size size) => Offset(
  ((a.lon + 180) / 360) * size.width,
  ((85 - a.lat.clamp(-85.0, 85.0)) / 170) * size.height,
);

Offset _latLonPoint(double lat, double lon, Size size) => Offset(
  ((_normalizeLon(lon) + 180) / 360) * size.width,
  ((85 - lat.clamp(-85.0, 85.0)) / 170) * size.height,
);

List<List<Offset>> _routeArcSegments(
  Airport origin,
  Airport destination,
  Size size, {
  int pointCount = 32,
}) {
  final lonDelta = _shortestLonDelta(origin.lon, destination.lon);
  final rawPoints = <({double lat, double lon})>[];
  for (var i = 0; i <= pointCount; i += 1) {
    rawPoints.add(
      _visualArcPoint(
        origin.lat,
        origin.lon,
        destination.lat,
        destination.lon,
        i / pointCount,
        lonDelta: lonDelta,
        normalize: false,
      ),
    );
  }
  final split = _splitArcAtAntimeridian(rawPoints);
  return split
      .map(
        (segment) => segment
            .map((point) => _latLonPoint(point.lat, point.lon, size))
            .toList(growable: false),
      )
      .where((segment) => segment.length > 1)
      .toList(growable: false);
}

List<List<({double lat, double lon})>> _splitArcAtAntimeridian(
  List<({double lat, double lon})> rawPoints,
) {
  if (rawPoints.isEmpty) return const [];
  final segments = <List<({double lat, double lon})>>[];
  var current = <({double lat, double lon})>[
    (lat: rawPoints.first.lat, lon: _normalizeLon(rawPoints.first.lon)),
  ];
  for (var i = 1; i < rawPoints.length; i += 1) {
    final previous = rawPoints[i - 1];
    final next = rawPoints[i];
    final crossing = _antimeridianBetween(previous.lon, next.lon);
    if (crossing == null) {
      current.add((lat: next.lat, lon: _normalizeLon(next.lon)));
      continue;
    }
    final t = (crossing - previous.lon) / (next.lon - previous.lon);
    final crossingLat = (previous.lat + (next.lat - previous.lat) * t).clamp(
      -85.0,
      85.0,
    );
    current.add((lat: crossingLat, lon: crossing > 0 ? 180 : -180));
    segments.add(current);
    current = [
      (lat: crossingLat, lon: crossing > 0 ? -180 : 180),
      (lat: next.lat, lon: _normalizeLon(next.lon)),
    ];
  }
  if (current.length > 1) segments.add(current);
  return segments;
}

double _shortestLonDelta(double fromLon, double toLon) =>
    shortestLongitudeDelta(fromLon, toLon);

double _normalizeLon(double lon) => normalizeLongitude(lon);

double? _antimeridianBetween(double fromLon, double toLon) {
  final low = math.min(fromLon, toLon);
  final high = math.max(fromLon, toLon);
  final start = ((low - 180) / 360).ceil();
  final end = ((high - 180) / 360).floor();
  if (start > end) return null;
  final crossing = 180 + start * 360;
  if (crossing <= low || crossing >= high) return null;
  return crossing.toDouble();
}

Color _colorFromHex(String hex) {
  final clean = hex.replaceFirst('#', '');
  final value =
      int.tryParse(clean.length == 6 ? 'ff$clean' : clean, radix: 16) ??
      0xffffffff;
  return Color(value);
}

class _GeoPoint {
  const _GeoPoint(this.lat, this.lon);
  final double lat;
  final double lon;
}

const _worldLandmasses = <List<_GeoPoint>>[
  [
    _GeoPoint(71, -168),
    _GeoPoint(70, -138),
    _GeoPoint(57, -127),
    _GeoPoint(50, -125),
    _GeoPoint(32, -117),
    _GeoPoint(16, -97),
    _GeoPoint(8, -82),
    _GeoPoint(19, -75),
    _GeoPoint(26, -81),
    _GeoPoint(31, -88),
    _GeoPoint(30, -96),
    _GeoPoint(25, -104),
    _GeoPoint(38, -123),
    _GeoPoint(49, -124),
    _GeoPoint(58, -135),
    _GeoPoint(70, -168),
  ],
  [
    _GeoPoint(72, -94),
    _GeoPoint(74, -62),
    _GeoPoint(61, -52),
    _GeoPoint(51, -58),
    _GeoPoint(45, -70),
    _GeoPoint(50, -82),
    _GeoPoint(58, -92),
    _GeoPoint(72, -94),
  ],
  [
    _GeoPoint(83, -52),
    _GeoPoint(78, -21),
    _GeoPoint(63, -20),
    _GeoPoint(59, -43),
    _GeoPoint(69, -57),
    _GeoPoint(83, -52),
  ],
  [
    _GeoPoint(12, -82),
    _GeoPoint(10, -69),
    _GeoPoint(5, -52),
    _GeoPoint(-8, -35),
    _GeoPoint(-22, -40),
    _GeoPoint(-55, -67),
    _GeoPoint(-52, -75),
    _GeoPoint(-35, -73),
    _GeoPoint(-16, -77),
    _GeoPoint(2, -79),
    _GeoPoint(12, -82),
  ],
  [
    _GeoPoint(37, -10),
    _GeoPoint(51, -10),
    _GeoPoint(58, 10),
    _GeoPoint(70, 30),
    _GeoPoint(70, 58),
    _GeoPoint(62, 92),
    _GeoPoint(51, 122),
    _GeoPoint(60, 160),
    _GeoPoint(47, 170),
    _GeoPoint(34, 137),
    _GeoPoint(22, 121),
    _GeoPoint(9, 105),
    _GeoPoint(7, 80),
    _GeoPoint(24, 68),
    _GeoPoint(31, 45),
    _GeoPoint(39, 30),
    _GeoPoint(38, 12),
    _GeoPoint(43, 0),
    _GeoPoint(37, -10),
  ],
  [
    _GeoPoint(37, -17),
    _GeoPoint(31, 32),
    _GeoPoint(12, 50),
    _GeoPoint(-35, 31),
    _GeoPoint(-35, 17),
    _GeoPoint(-18, 12),
    _GeoPoint(0, 9),
    _GeoPoint(5, -8),
    _GeoPoint(20, -17),
    _GeoPoint(37, -17),
  ],
  [
    _GeoPoint(23, 49),
    _GeoPoint(30, 58),
    _GeoPoint(25, 68),
    _GeoPoint(12, 76),
    _GeoPoint(7, 56),
    _GeoPoint(16, 43),
    _GeoPoint(23, 49),
  ],
  [
    _GeoPoint(7, 95),
    _GeoPoint(18, 105),
    _GeoPoint(16, 122),
    _GeoPoint(0, 126),
    _GeoPoint(-11, 118),
    _GeoPoint(-6, 102),
    _GeoPoint(7, 95),
  ],
  [
    _GeoPoint(-10, 112),
    _GeoPoint(-12, 154),
    _GeoPoint(-27, 154),
    _GeoPoint(-39, 144),
    _GeoPoint(-35, 116),
    _GeoPoint(-21, 113),
    _GeoPoint(-10, 112),
  ],
  [
    _GeoPoint(-35, 166),
    _GeoPoint(-34, 179),
    _GeoPoint(-47, 178),
    _GeoPoint(-47, 168),
    _GeoPoint(-35, 166),
  ],
  [
    _GeoPoint(-62, -180),
    _GeoPoint(-62, -120),
    _GeoPoint(-66, -60),
    _GeoPoint(-64, 0),
    _GeoPoint(-67, 70),
    _GeoPoint(-63, 140),
    _GeoPoint(-62, 180),
    _GeoPoint(-85, 180),
    _GeoPoint(-85, -180),
    _GeoPoint(-62, -180),
  ],
];

const _worldTerrainHighlights = <List<_GeoPoint>>[
  [
    _GeoPoint(55, -130),
    _GeoPoint(47, -114),
    _GeoPoint(35, -110),
    _GeoPoint(21, -102),
    _GeoPoint(18, -112),
    _GeoPoint(33, -124),
    _GeoPoint(55, -130),
  ],
  [
    _GeoPoint(-8, -79),
    _GeoPoint(-14, -72),
    _GeoPoint(-28, -69),
    _GeoPoint(-48, -72),
    _GeoPoint(-42, -66),
    _GeoPoint(-20, -64),
    _GeoPoint(-8, -79),
  ],
  [
    _GeoPoint(28, 69),
    _GeoPoint(36, 79),
    _GeoPoint(34, 95),
    _GeoPoint(25, 102),
    _GeoPoint(20, 86),
    _GeoPoint(28, 69),
  ],
  [
    _GeoPoint(12, 34),
    _GeoPoint(9, 45),
    _GeoPoint(-22, 35),
    _GeoPoint(-25, 22),
    _GeoPoint(3, 27),
    _GeoPoint(12, 34),
  ],
];

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
    _drawWorldBasemap(canvas, size);
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
    final drawableRoutes = game.routes.values.where((route) {
      if (!route.isActive || route.aircraftId == null) return false;
      if (showAiOnMap) return true;
      return game.airlines[route.airlineId]?.isPlayer == true;
    }).toList();
    for (final route in drawableRoutes) {
      final origin = airportsByIata[route.originIata];
      final dest = airportsByIata[route.destinationIata];
      if (origin == null || dest == null) continue;
      final segments = _routeArcSegments(origin, dest, size);
      final airline = game.airlines[route.airlineId];
      final isPlayer = airline?.isPlayer == true;
      final color = _colorFromHex(airline?.color ?? '#2f8cff');
      final glowPaint = Paint()
        ..color = color.withValues(alpha: isPlayer ? 0.22 : 0.10)
        ..strokeWidth = isPlayer ? 5 : 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final routePaint = Paint()
        ..color = color.withValues(alpha: isPlayer ? 0.86 : 0.46)
        ..strokeWidth = isPlayer ? 2.2 : 1.35
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final segment in segments) {
        final path = Path()..moveTo(segment.first.dx, segment.first.dy);
        for (var i = 1; i < segment.length; i += 1) {
          path.lineTo(segment[i].dx, segment[i].dy);
        }
        canvas.drawPath(path, glowPaint);
        _drawDashedPolyline(
          canvas,
          segment,
          routePaint,
          dash: isPlayer ? 10 : 5,
          gap: isPlayer ? 9 : 10,
        );
      }
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

  void _drawWorldBasemap(Canvas canvas, Size size) {
    final landPaint = Paint()
      ..color = const Color(0xff172233)
      ..style = PaintingStyle.fill;
    final landHighlightPaint = Paint()
      ..color = const Color(0xff223148).withValues(alpha: 0.42)
      ..style = PaintingStyle.fill;
    final coastPaint = Paint()
      ..color = const Color(0xff3b4b62).withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round;
    final softCoastPaint = Paint()
      ..color = const Color(0xff5f7892).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.8
      ..strokeJoin = StrokeJoin.round;

    for (final landmass in _worldLandmasses) {
      final path = Path();
      for (var i = 0; i < landmass.length; i += 1) {
        final point = _latLonPoint(landmass[i].lat, landmass[i].lon, size);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, softCoastPaint);
      canvas.drawPath(path, landPaint);
      canvas.drawPath(path, coastPaint);
    }

    for (final shade in _worldTerrainHighlights) {
      final path = Path();
      for (var i = 0; i < shade.length; i += 1) {
        final point = _latLonPoint(shade[i].lat, shade[i].lon, size);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, landHighlightPaint);
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
    final cycle = (ac.flightProgress * 2).clamp(0, 2).toDouble();
    final t = cycle <= 1 ? cycle : 2 - cycle;
    final from = cycle <= 1 ? origin : dest;
    final to = cycle <= 1 ? dest : origin;
    final visualPoint = _visualArcPoint(from.lat, from.lon, to.lat, to.lon, t);
    final ahead = _visualArcPoint(
      from.lat,
      from.lon,
      to.lat,
      to.lon,
      math.min(1, t + 0.01),
    );
    final point = _latLonPoint(visualPoint.lat, visualPoint.lon, size);
    final aheadPoint = _latLonPoint(ahead.lat, ahead.lon, size);
    final angle = math.atan2(
      aheadPoint.dy - point.dy,
      aheadPoint.dx - point.dx,
    );
    final airline = game.airlines[route.airlineId];
    final color = _colorFromHex(airline?.color ?? '#ffffff');
    final type = aircraftTypesById[ac.typeId];
    final sizePx = switch (type?.category) {
      AircraftCategory.regional => 8.5,
      AircraftCategory.narrowbody => 10.0,
      AircraftCategory.widebody => 12.5,
      AircraftCategory.sst => 12.0,
      null => 10.0,
    };
    canvas.save();
    canvas.translate(point.dx, point.dy);
    canvas.rotate(angle);
    canvas.scale(sizePx);
    canvas.drawCircle(
      Offset.zero,
      0.9,
      Paint()..color = color.withValues(alpha: 0.16),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = const Color(0xff050915)
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.16;
    final plane = _planePathForCategory(type?.category);
    canvas.drawPath(plane, outline);
    canvas.drawPath(plane, paint);
    canvas.drawPath(
      plane,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 0.05,
    );
    canvas.restore();
  }

  void _drawDashedPolyline(
    Canvas canvas,
    List<Offset> points,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    if (points.length < 2) return;
    var drawDash = true;
    var remaining = dash;
    for (var i = 1; i < points.length; i += 1) {
      var start = points[i - 1];
      final end = points[i];
      var vector = end - start;
      var segmentLength = vector.distance;
      if (segmentLength <= 0) continue;
      final direction = vector / segmentLength;
      while (segmentLength > 0) {
        final step = math.min(remaining, segmentLength);
        final next = start + direction * step;
        if (drawDash) {
          canvas.drawLine(start, next, paint);
        }
        start = next;
        segmentLength -= step;
        remaining -= step;
        if (remaining <= 0.0001) {
          drawDash = !drawDash;
          remaining = drawDash ? dash : gap;
        }
      }
    }
  }

  Path _planePathForCategory(AircraftCategory? category) {
    switch (category) {
      case AircraftCategory.regional:
        return Path()
          ..moveTo(1.0, 0)
          ..cubicTo(0.76, -0.12, 0.42, -0.17, -0.15, -0.16)
          ..lineTo(-0.8, -0.55)
          ..lineTo(-0.55, -0.12)
          ..lineTo(-0.96, -0.08)
          ..lineTo(-0.96, 0.08)
          ..lineTo(-0.55, 0.12)
          ..lineTo(-0.8, 0.55)
          ..lineTo(-0.15, 0.16)
          ..cubicTo(0.42, 0.17, 0.76, 0.12, 1.0, 0)
          ..close();
      case AircraftCategory.widebody:
        return Path()
          ..moveTo(1.08, 0)
          ..cubicTo(0.75, -0.2, 0.05, -0.24, -0.42, -0.2)
          ..lineTo(-0.18, -0.86)
          ..lineTo(-0.48, -0.92)
          ..lineTo(-0.78, -0.18)
          ..lineTo(-1.0, -0.14)
          ..lineTo(-0.88, 0)
          ..lineTo(-1.0, 0.14)
          ..lineTo(-0.78, 0.18)
          ..lineTo(-0.48, 0.92)
          ..lineTo(-0.18, 0.86)
          ..lineTo(-0.42, 0.2)
          ..cubicTo(0.05, 0.24, 0.75, 0.2, 1.08, 0)
          ..close();
      case AircraftCategory.sst:
        return Path()
          ..moveTo(1.2, 0)
          ..lineTo(0.25, -0.16)
          ..lineTo(-0.2, -0.75)
          ..lineTo(-0.42, -0.68)
          ..lineTo(-0.34, -0.15)
          ..lineTo(-1.05, -0.34)
          ..lineTo(-0.78, 0)
          ..lineTo(-1.05, 0.34)
          ..lineTo(-0.34, 0.15)
          ..lineTo(-0.42, 0.68)
          ..lineTo(-0.2, 0.75)
          ..lineTo(0.25, 0.16)
          ..close();
      case AircraftCategory.narrowbody:
      case null:
        return Path()
          ..moveTo(1.05, 0)
          ..cubicTo(0.72, -0.15, 0.12, -0.18, -0.34, -0.14)
          ..lineTo(-0.54, -0.7)
          ..lineTo(-0.78, -0.65)
          ..lineTo(-0.65, -0.12)
          ..lineTo(-1.0, -0.09)
          ..lineTo(-1.0, 0.09)
          ..lineTo(-0.65, 0.12)
          ..lineTo(-0.78, 0.65)
          ..lineTo(-0.54, 0.7)
          ..lineTo(-0.34, 0.14)
          ..cubicTo(0.12, 0.18, 0.72, 0.15, 1.05, 0)
          ..close();
    }
  }

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
  Widget build(BuildContext context) {
    final valueText =
        '${money(value, currency)}/d ${isLiveRoute ? 'live' : 'potential'}';
    final valueColor = isLiveRoute
        ? value >= 0
              ? const Color(0xff3af083)
              : const Color(0xffff6b6b)
        : const Color(0xff8b95a8);
    return Material(
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
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 76,
                      maxWidth: 96,
                    ),
                    child: Text(
                      '${_formatCount(demand)} pax/d',
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff6ed4ff),
                        fontWeight: FontWeight.w900,
                      ),
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
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 112,
                      maxWidth: 148,
                    ),
                    child: Text(
                      valueText,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: valueColor,
                        fontWeight: FontWeight.w700,
                      ),
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
}

String _distanceLabel(double km) =>
    km >= 1000 ? '${(km / 1000).toStringAsFixed(1)}k km' : '${km.round()} km';

class _MainPanel extends StatelessWidget {
  const _MainPanel({
    required this.game,
    required this.panel,
    required this.currency,
    required this.onClose,
    required this.onCreateRoute,
  });
  final GameController game;
  final _Panel panel;
  final CurrencyOption currency;
  final VoidCallback onClose;
  final VoidCallback onCreateRoute;
  @override
  Widget build(BuildContext context) => _PanelShell(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Icon(_panelIcon(panel), color: const Color(0xff77c9ff)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _panelLabel(panel),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close panel',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
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
    this.previous,
  });

  final String label;
  final double value;
  final Color color;
  final double? previous;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    final delta = previous != null ? ((value - previous!) * 100).round() : null;
    final deltaColor = delta == null
        ? null
        : delta > 0
            ? const Color(0xff3af083)
            : delta < 0
                ? const Color(0xffff6b6b)
                : const Color(0xff9aa4b5);
    final deltaText = delta == null
        ? null
        : delta > 0
            ? '+${delta}pp'
            : delta < 0
                ? '${delta}pp'
                : null;
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
        if (deltaText != null) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            child: Text(
              deltaText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: deltaColor,
              ),
            ),
          ),
        ] else if (previous != null)
          const SizedBox(width: 50),
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
              previous: current.loadFactorEconomy,
            ),
            if (route.priceBusiness > 0 || route.loadFactorBusiness > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _LoadFactorLine(
                  label: 'Biz',
                  value: route.loadFactorBusiness,
                  color: const Color(0xff77c9ff),
                  previous: current.loadFactorBusiness,
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
            if (route.dailyCost > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _MiniFinanceStat(
                    'Fuel',
                    money(route.dailyFuelCost, currency),
                  ),
                  _MiniFinanceStat(
                    'Maintenance',
                    money(route.dailyMaintenanceCost, currency),
                  ),
                  _MiniFinanceStat(
                    'Crew',
                    money(route.dailyCrewCost, currency),
                  ),
                  _MiniFinanceStat(
                    'Airport fees',
                    money(route.dailyAirportFees, currency),
                  ),
                ],
              ),
            ],
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
  String? confirmingSaleId;

  String _maintenanceTierLabel(MaintenanceTier tier) =>
      tier.name[0].toUpperCase() + tier.name.substring(1);

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
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Fleet (${fleet.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) =>
                      _BuyAircraftDialog(game: game, currency: currency),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Buy Aircraft'),
              ),
            ],
          ),
        ),
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              const Text(
                'Fleet Maintenance Policy',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 8),
              _FleetStatusChip(
                label: policy.enabled
                    ? 'ON · ${_maintenanceTierLabel(policy.tier)} @ ${policy.threshold.round()}%'
                    : 'OFF',
                color: policy.enabled
                    ? const Color(0xff2dd4bf)
                    : const Color(0xff8b95a8),
              ),
            ],
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Auto-maintenance for all aircraft'),
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
                  subtitle: const Text(
                    'Grounding articles stay in the ticker, but no longer pop up.',
                  ),
                ),
              ],
            ),
          ],
        ),
        if (fleet.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: const Row(
              children: [
                SizedBox(width: 10),
                SizedBox(width: 10),
                SizedBox(width: 58, child: Text('Aircraft')),
                Expanded(child: Text('Route')),
                SizedBox(
                  width: 46,
                  child: Text('Hrs', textAlign: TextAlign.end),
                ),
                SizedBox(
                  width: 58,
                  child: Text('Cond.', textAlign: TextAlign.end),
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
          return ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: conditionColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 58,
                  child: Text(
                    type?.model ?? ac.typeId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    routeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff9aa4b5),
                      fontSize: 12,
                    ),
                  ),
                ),
                SizedBox(
                  width: 46,
                  child: Text(
                    '${_formatCount(ac.totalFlightHours)}h',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Color(0xff8b95a8),
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 50,
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: (ac.condition / 100).clamp(0, 1),
                            minHeight: 6,
                            color: conditionColor,
                            backgroundColor: const Color(0xff293244),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        ac.condition.toStringAsFixed(0),
                        style: TextStyle(
                          color: conditionColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            children: [
              Column(
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
                      '${_aircraftCategoryLabel(type.category)} · ${type.seatsEconomy}Y/${type.seatsBusiness}J · ${_formatCount(type.rangeKm)} km range · ${type.cruiseSpeedKmh} km/h',
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
                          color: const Color(
                            0xffff6b6b,
                          ).withValues(alpha: 0.35),
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
                                    ? () => setState(
                                        () => confirmingSaleId = ac.id,
                                      )
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
                        final cfg = maintenanceTiers[tier]!;
                        final conditionGain = cfg.conditionGain >= 999
                            ? math.max(0.0, 100 - ac.condition)
                            : math.min(cfg.conditionGain, 100 - ac.condition);
                        final costPerPoint = conditionGain <= 0
                            ? cost
                            : (cost / conditionGain).round();
                        return OutlinedButton(
                          onPressed: ac.status == AircraftStatus.maintenance
                              ? null
                              : () => game.startMaintenance(ac.id, tier),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_maintenanceTierLabel(tier)} · ${money(cost, currency)}',
                              ),
                              Text(
                                '${cfg.durationDays}d · ${cfg.conditionGain >= 999 ? 'to 100%' : '+${cfg.conditionGain.round()}%'} · ${money(costPerPoint, currency)}/pt',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
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
                                            ? (value) =>
                                                  game.setAutoMaintenance(
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
                                            ? (value) =>
                                                  game.setAutoMaintenance(
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
            ],
          );
        }),
      ],
    );
  }
}

class _BuyAircraftDialog extends StatefulWidget {
  const _BuyAircraftDialog({required this.game, required this.currency});

  final GameController game;
  final CurrencyOption currency;

  @override
  State<_BuyAircraftDialog> createState() => _BuyAircraftDialogState();
}

class _BuyAircraftDialogState extends State<_BuyAircraftDialog> {
  static const allManufacturers = 'All';

  var selectedManufacturer = allManufacturers;
  String? purchaseError;

  @override
  Widget build(BuildContext context) {
    final gameYear =
        widget.game.settings.startingYear + widget.game.gameDay ~/ 365;
    final manufacturers = <String>[
      allManufacturers,
      ...aircraftTypes.map((type) => type.manufacturer).toSet().toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
    ];
    final visibleTypes =
        aircraftTypes
            .where(
              (type) =>
                  selectedManufacturer == allManufacturers ||
                  type.manufacturer == selectedManufacturer,
            )
            .toList()
          ..sort((a, b) {
            final aAvailable = a.yearIntroduced <= gameYear;
            final bAvailable = b.yearIntroduced <= gameYear;
            if (aAvailable != bAvailable) return aAvailable ? -1 : 1;
            final maker = a.manufacturer.compareTo(b.manufacturer);
            if (maker != 0) return maker;
            return a.model.compareTo(b.model);
          });
    final compact = MediaQuery.sizeOf(context).width < 720;
    final dialogHeight =
        MediaQuery.sizeOf(context).height * (compact ? 0.94 : 0.86);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 36,
        vertical: compact ? 10 : 28,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 920, maxHeight: dialogHeight),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Buy Aircraft',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(
                              'Cash available: ${money(widget.game.player.cashUSD, widget.currency)}',
                              style: const TextStyle(
                                color: Color(0xff3af083),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Year $gameYear',
                              style: const TextStyle(color: Color(0xff8b95a8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: compact
                  ? Column(
                      children: [
                        _ManufacturerRail(
                          manufacturers: manufacturers,
                          selected: selectedManufacturer,
                          horizontal: true,
                          onSelected: _selectManufacturer,
                        ),
                        Expanded(
                          child: _AircraftPurchaseList(
                            game: widget.game,
                            currency: widget.currency,
                            gameYear: gameYear,
                            types: visibleTypes,
                            purchaseError: purchaseError,
                            onBuy: _buyAircraft,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        SizedBox(
                          width: 178,
                          child: _ManufacturerRail(
                            manufacturers: manufacturers,
                            selected: selectedManufacturer,
                            horizontal: false,
                            onSelected: _selectManufacturer,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: _AircraftPurchaseList(
                            game: widget.game,
                            currency: widget.currency,
                            gameYear: gameYear,
                            types: visibleTypes,
                            purchaseError: purchaseError,
                            onBuy: _buyAircraft,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectManufacturer(String manufacturer) {
    setState(() {
      selectedManufacturer = manufacturer;
      purchaseError = null;
    });
  }

  void _buyAircraft(AircraftType type) {
    if (type.yearIntroduced >
        widget.game.settings.startingYear + widget.game.gameDay ~/ 365) {
      return;
    }
    if (widget.game.player.cashUSD < type.purchasePrice) return;
    try {
      widget.game.buyAircraft(type.id);
      Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      setState(
        () => purchaseError = e.toString().replaceFirst('Bad state: ', ''),
      );
    }
  }
}

class _ManufacturerRail extends StatelessWidget {
  const _ManufacturerRail({
    required this.manufacturers,
    required this.selected,
    required this.horizontal,
    required this.onSelected,
  });

  final List<String> manufacturers;
  final String selected;
  final bool horizontal;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final children = manufacturers.map((manufacturer) {
      final isSelected = selected == manufacturer;
      return Padding(
        padding: EdgeInsets.only(
          right: horizontal ? 4 : 0,
          bottom: horizontal ? 0 : 2,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(horizontal ? 999 : 0),
          onTap: () => onSelected(manufacturer),
          child: Container(
            width: horizontal ? null : double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: horizontal ? 12 : 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(horizontal ? 999 : 0),
            ),
            child: Text(
              manufacturer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xfff8fafc)
                    : const Color(0xff9aa4b5),
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }).toList();

    if (horizontal) {
      return Container(
        height: 52,
        color: Colors.white.withValues(alpha: 0.025),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          children: children,
        ),
      );
    }

    return Container(
      color: Colors.white.withValues(alpha: 0.025),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: children,
      ),
    );
  }
}

class _AircraftPurchaseList extends StatelessWidget {
  const _AircraftPurchaseList({
    required this.game,
    required this.currency,
    required this.gameYear,
    required this.types,
    required this.purchaseError,
    required this.onBuy,
  });

  final GameController game;
  final CurrencyOption currency;
  final int gameYear;
  final List<AircraftType> types;
  final String? purchaseError;
  final ValueChanged<AircraftType> onBuy;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (purchaseError != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xffff6b6b).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xffff6b6b).withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              purchaseError!,
              style: const TextStyle(color: Color(0xffffb4b4)),
            ),
          ),
        ...types.map((type) {
          final unavailable = type.yearIntroduced > gameYear;
          final canAfford = game.player.cashUSD >= type.purchasePrice;
          return _AircraftPurchaseCard(
            type: type,
            currency: currency,
            unavailable: unavailable,
            canAfford: canAfford,
            onBuy: () => onBuy(type),
          );
        }),
      ],
    );
  }
}

class _AircraftPurchaseCard extends StatelessWidget {
  const _AircraftPurchaseCard({
    required this.type,
    required this.currency,
    required this.unavailable,
    required this.canAfford,
    required this.onBuy,
  });

  final AircraftType type;
  final CurrencyOption currency;
  final bool unavailable;
  final bool canAfford;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: unavailable ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 112,
              height: 58,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: _subtleSurface(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _hairline(context)),
              ),
              child: Icon(
                _aircraftCategoryIcon(type.category),
                color: unavailable
                    ? const Color(0xff6b7280)
                    : const Color(0xff77c9ff),
                size: 34,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              type.model,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              _aircraftCategoryLabel(type.category),
                              style: const TextStyle(
                                color: Color(0xff8b95a8),
                                fontSize: 12,
                              ),
                            ),
                            if (unavailable)
                              _FleetStatusChip(
                                label: 'AVAIL. ${type.yearIntroduced}',
                                color: const Color(0xffffd166),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            money(type.purchasePrice, currency),
                            style: TextStyle(
                              color: !unavailable && !canAfford
                                  ? const Color(0xffff6b6b)
                                  : const Color(0xfff8fafc),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (!unavailable)
                            FilledButton(
                              onPressed: canAfford ? onBuy : null,
                              child: Text(canAfford ? 'Buy' : 'No funds'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _SpecText(
                        'Seats',
                        type.seatsBusiness > 0
                            ? '${type.seatsEconomy}Y/${type.seatsBusiness}J'
                            : '${type.seatsEconomy}Y',
                      ),
                      _SpecText('Range', '${_formatCount(type.rangeKm)} km'),
                      _SpecText('Runway', '${type.minRunwayM} m'),
                      _SpecText('Speed', '${type.cruiseSpeedKmh} km/h'),
                      _SpecText(
                        'Fuel',
                        '${_formatCount(type.fuelBurnLPer100Km)} L/100km',
                      ),
                      _SpecText(
                        'Maint',
                        '${money(type.maintenanceCostPerHourUSD, currency)}/hr',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _aircraftCategoryIcon(AircraftCategory category) => switch (category) {
  AircraftCategory.regional => Icons.connecting_airports,
  AircraftCategory.narrowbody => Icons.flight,
  AircraftCategory.widebody => Icons.airplanemode_active,
  AircraftCategory.sst => Icons.rocket_launch,
};

class _SpecText extends StatelessWidget {
  const _SpecText(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: '$label: ',
      style: const TextStyle(color: Color(0xff8b95a8), fontSize: 12),
      children: [
        TextSpan(
          text: value,
          style: const TextStyle(
            color: Color(0xffcfd6e6),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
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

String _aircraftCategoryLabel(AircraftCategory category) =>
    category == AircraftCategory.sst
    ? 'SST'
    : category.name[0].toUpperCase() + category.name.substring(1);

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
    final exactFuelCost = routes.fold<double>(
      0,
      (sum, route) => sum + route.dailyFuelCost,
    );
    final exactMaintenanceCost = routes.fold<double>(
      0,
      (sum, route) => sum + route.dailyMaintenanceCost,
    );
    final exactCrewCost = routes.fold<double>(
      0,
      (sum, route) => sum + route.dailyCrewCost,
    );
    final exactAirportFees = routes.fold<double>(
      0,
      (sum, route) => sum + route.dailyAirportFees,
    );
    final exactCostTotal =
        exactFuelCost + exactMaintenanceCost + exactCrewCost + exactAirportFees;
    final fuelCost = exactCostTotal > 0 ? exactFuelCost : totalDailyCost * 0.35;
    final maintenanceCost = exactCostTotal > 0
        ? exactMaintenanceCost
        : totalDailyCost * 0.25;
    final crewCost = exactCostTotal > 0 ? exactCrewCost : totalDailyCost * 0.25;
    final airportFees = exactCostTotal > 0
        ? exactAirportFees
        : totalDailyCost * 0.15;
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
                value: -fuelCost,
                color: const Color(0xffff6b6b),
                currency: currency,
              ),
              _FinanceBreakdownRow(
                label: 'Maintenance',
                value: -maintenanceCost,
                color: const Color(0xffffa94d),
                currency: currency,
              ),
              _FinanceBreakdownRow(
                label: 'Crew',
                value: -crewCost,
                color: const Color(0xffffd166),
                currency: currency,
              ),
              _FinanceBreakdownRow(
                label: 'Airport fees',
                value: -airportFees,
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
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: creditLimit <= 0
                      ? 0
                      : (player.totalDebt / creditLimit).clamp(0, 1),
                  minHeight: 8,
                  color: player.totalDebt > creditLimit * 0.8
                      ? const Color(0xffffd166)
                      : const Color(0xff77c9ff),
                  backgroundColor: const Color(0xff293244),
                ),
              ),
              const SizedBox(height: 12),
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
                children: loanOffers.map((offer) {
                  final available = game.canApplyForLoan(offer);
                  final dailyPayment = calculateDailyLoanPayment(
                    offer.amountUSD,
                    offer.annualInterestRate,
                    offer.termYears,
                  );
                  return SizedBox(
                    width: 190,
                    child: OutlinedButton(
                      onPressed: available
                          ? () => game.applyForLoan(offer)
                          : null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            money(offer.amountUSD, currency),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            '${formatInterestRate(offer.annualInterestRate)} · ${offer.termYears}y · ${money(dailyPayment, currency)}/day',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11),
                          ),
                          if (!available)
                            const Text(
                              'credit limit',
                              style: TextStyle(fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
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
      (label: 'Full', amount: loan.principalUSD),
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
                child: Text('Max cash · ${money(affordable, currency)}'),
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
      final aiShareholders = airline.isPlayer
          ? <({String name, double share})>[]
          : airline.shareholders.entries
                .where((entry) => entry.key != 'player' && entry.value > 0)
                .map(
                  (entry) => (
                    name: widget.game.airlines[entry.key]?.name ?? entry.key,
                    share: entry.value,
                  ),
                )
                .toList(growable: false);
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: _MapPainter._colorFromHex(
                                    airline.color,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
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
                          Text(
                            '${airline.isPlayer ? 'Your airline' : '${airline.personality.name} airline'} · Hub: ${airline.hubIatas.isEmpty ? '-' : airline.hubIatas.join(', ')}${airline.isInsolvent ? ' · Bankrupt' : ''}',
                            style: const TextStyle(color: Color(0xff9aa4b5)),
                          ),
                        ],
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
                        ...aiShareholders.map(
                          (shareholder) => Expanded(
                            flex: shareholder.share.round().clamp(1, 100),
                            child: Container(
                              color: const Color(
                                0xff94a3b8,
                              ).withValues(alpha: 0.72),
                            ),
                          ),
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
                    if (playerStake > 0)
                      _OwnershipChip(
                        label: 'You ${playerStake.toStringAsFixed(0)}%',
                        accent: const Color(0xff2dd4bf),
                      ),
                    ...aiShareholders.map(
                      (shareholder) => _OwnershipChip(
                        label:
                            '${shareholder.name} ${shareholder.share.toStringAsFixed(0)}%',
                        accent: const Color(0xff94a3b8),
                      ),
                    ),
                    _OwnershipChip(
                      label: 'Float ${marketFloat.toStringAsFixed(0)}%',
                      accent: const Color(0xff64748b),
                    ),
                  ],
                ),
                if (!airline.isPlayer) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: marketFloat < 1 && aiShareholders.isEmpty
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
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => _RouteSummaryDialog(
                        game: widget.game,
                        route: route,
                        currency: widget.currency,
                      ),
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
  var source = 'market';
  String? error;
  showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final airline = game.airlines[airlineId];
        if (airline == null) return const SizedBox.shrink();
        final owned = game.playerStakeIn(airlineId);
        final float = game.marketFloatForAirline(airlineId);
        final sellerOptions = airline.shareholders.entries
            .where((entry) => entry.key != 'player' && entry.value >= 1)
            .map(
              (entry) => (
                id: entry.key,
                name: game.airlines[entry.key]?.name ?? entry.key,
                stake: entry.value,
              ),
            )
            .toList(growable: false);
        if (source != 'market' &&
            !sellerOptions.any((seller) => seller.id == source)) {
          source = 'market';
        }
        final sourceAvailable = source == 'market'
            ? float
            : sellerOptions
                      .where((seller) => seller.id == source)
                      .firstOrNull
                      ?.stake ??
                  0;
        final max = selling ? owned : math.min(50, sourceAvailable);
        final clampedPercent = max < 1 ? 0.0 : percent.clamp(1, max).toDouble();
        final value = game.companyValue(airlineId);
        final buyPrice = clampedPercent <= 0
            ? 0.0
            : game.sharePurchasePrice(
                airlineId,
                clampedPercent,
                source: source,
              );
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
                if (!selling && sellerOptions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Buy from',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text('Market · ${float.toStringAsFixed(0)}%'),
                        selected: source == 'market',
                        onSelected: float < 1
                            ? null
                            : (_) => setState(() {
                                source = 'market';
                                percent = 5;
                                error = null;
                              }),
                      ),
                      ...sellerOptions.map(
                        (seller) => ChoiceChip(
                          label: Text(
                            '${seller.name} · ${seller.stake.toStringAsFixed(0)}%',
                          ),
                          selected: source == seller.id,
                          onSelected: (_) => setState(() {
                            source = seller.id;
                            percent = 5;
                            error = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                  if (source != 'market')
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Secondary share blocks include a 15% seller premium.',
                        style: TextStyle(
                          color: Color(0xff9aa4b5),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
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
                          game.buyShares(
                            airlineId,
                            clampedPercent,
                            source: source,
                          );
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
    final origin = game.airportByIata(latestRoute.originIata);
    final destination = game.airportByIata(latestRoute.destinationIata);
    final ac = latestRoute.aircraftId == null
        ? null
        : game.aircraft[latestRoute.aircraftId!];
    final type = ac == null ? null : aircraftTypesById[ac.typeId];
    final condition = ac?.condition ?? 100;
    final conditionColor = condition >= 70
        ? const Color(0xff3af083)
        : condition >= 40
        ? const Color(0xffffd166)
        : const Color(0xffff6b6b);
    return AlertDialog(
      title: Text(
        latestRoute.airlineId == 'player' ? 'Route Detail' : 'Competitor Route',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (airline != null)
                Row(
                  children: [
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: _MapPainter._colorFromHex(airline.color),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _AirlineLogo(logo: airline.logoEmoji, size: 30),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        airline.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (!airline.isPlayer)
                      Text(
                        airline.personality.name,
                        style: const TextStyle(color: Color(0xff8b95a8)),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    latestRoute.originIata,
                    style: const TextStyle(
                      color: Color(0xff58a6ff),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, color: Color(0xff8b95a8)),
                  ),
                  Text(
                    latestRoute.destinationIata,
                    style: const TextStyle(
                      color: Color(0xff58a6ff),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              Text(
                origin != null && destination != null
                    ? '${origin.city} -> ${destination.city}'
                    : '${latestRoute.originIata} -> ${latestRoute.destinationIata}',
                style: const TextStyle(color: Color(0xff8b95a8)),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _RouteSummaryStat(
                    label: 'Distance',
                    value: '${_formatCount(latestRoute.distanceKm)} km',
                  ),
                  _RouteSummaryStat(
                    label: 'Economy fare',
                    value: money(latestRoute.priceEconomy, currency),
                  ),
                  if (latestRoute.priceBusiness > 0)
                    _RouteSummaryStat(
                      label: 'Business fare',
                      value: money(latestRoute.priceBusiness, currency),
                    ),
                  _RouteSummaryStat(
                    label: 'Flights',
                    value: '${latestRoute.flightsPerWeek}/week',
                  ),
                  _RouteSummaryStat(
                    label: 'Daily revenue',
                    value: money(latestRoute.dailyRevenue, currency),
                    color: const Color(0xff3af083),
                  ),
                  _RouteSummaryStat(
                    label: 'Daily profit',
                    value: latestRoute.dailyProfit == 0
                        ? '-'
                        : money(latestRoute.dailyProfit, currency),
                    color: latestRoute.dailyProfit >= 0
                        ? const Color(0xff3af083)
                        : const Color(0xffff6b6b),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Load factor',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    _LoadFactorLine(
                      label: 'Eco',
                      value: latestRoute.loadFactorEconomy,
                      color: const Color(0xff3af083),
                    ),
                    if (latestRoute.priceBusiness > 0 ||
                        latestRoute.loadFactorBusiness > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _LoadFactorLine(
                          label: 'Biz',
                          value: latestRoute.loadFactorBusiness,
                          color: const Color(0xff77c9ff),
                        ),
                      ),
                  ],
                ),
              ),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Aircraft',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    if (ac == null || type == null)
                      const Text(
                        'No aircraft assigned',
                        style: TextStyle(color: Color(0xff8b95a8)),
                      )
                    else ...[
                      Text(
                        type.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '${type.seatsEconomy} eco · ${type.seatsBusiness} biz · ${_formatCount(type.rangeKm)} km range',
                        style: const TextStyle(color: Color(0xff8b95a8)),
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: (condition / 100).clamp(0, 1),
                        color: conditionColor,
                        backgroundColor: const Color(0xff293244),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Condition ${condition.toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: Color(0xff8b95a8)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
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

class _RouteSummaryStat extends StatelessWidget {
  const _RouteSummaryStat({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: _subtleSurface(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _hairline(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xff8b95a8))),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    ),
  );
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
    final currentYear =
        widget.game.settings.startingYear + widget.game.gameDay ~/ 365;
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
    final optimisationPreview = widget.game.previewRouteOptimisation(route.id);
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
    final shopTypes = aircraftTypes.where((candidateType) {
      final byManufacturer =
          buyManufacturer == 'All' ||
          candidateType.manufacturer == buyManufacturer;
      final available = candidateType.yearIntroduced <= currentYear;
      final fits =
          origin != null &&
          destination != null &&
          candidateType.rangeKm >= route.distanceKm &&
          canAirportHandleAircraft(origin, candidateType) &&
          canAirportHandleAircraft(destination, candidateType);
      return available && byManufacturer && fits;
    }).toList();
    shopTypes.sort((a, b) => a.purchasePrice.compareTo(b.purchasePrice));
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
                                '${candidateType.displayName} · ${candidateType.seatsEconomy}Y/${candidateType.seatsBusiness}J · ${_formatCount(candidateType.rangeKm)} km · ${money(candidateType.purchasePrice, widget.currency)}',
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
                      onPressed: optimisationPreview == null
                          ? null
                          : () {
                              final result = widget.game.optimiseRoute(
                                route.id,
                              );
                              setState(() {
                                flights = result.flightsPerWeek;
                                ecoController.text = result.priceEconomy
                                    .toString();
                                bizController.text = result.priceBusiness
                                    .toString();
                              });
                            },
                      icon: const Icon(Icons.auto_fix_high),
                      label: Text(
                        optimisationPreview == null ? 'Optimised' : 'Optimise',
                      ),
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

class _RouteJourneyCard extends StatelessWidget {
  const _RouteJourneyCard({
    required this.origin,
    required this.destination,
    required this.distanceKm,
    required this.demand,
    required this.competitorCount,
    required this.aircraftType,
    required this.rangeLimited,
    required this.runwayLimited,
    required this.currency,
  });

  final Airport origin;
  final Airport destination;
  final double distanceKm;
  final double demand;
  final int competitorCount;
  final AircraftType? aircraftType;
  final bool rangeLimited;
  final bool runwayLimited;
  final CurrencyOption currency;

  @override
  Widget build(BuildContext context) {
    final potentialValue =
        demand * (150 + math.sqrt(math.max(250, distanceKm)) * 18);
    final statusColor = aircraftType == null
        ? const Color(0xff9aa4b5)
        : rangeLimited || runwayLimited
        ? const Color(0xffff6b6b)
        : const Color(0xff3af083);
    final statusText = aircraftType == null
        ? 'No aircraft selected'
        : rangeLimited
        ? '${aircraftType!.model} range ${_formatCount(aircraftType!.rangeKm)} km'
        : runwayLimited
        ? 'Runway too short for ${aircraftType!.model}'
        : 'Aircraft compatible';

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _JourneyAirportBlock(
                  label: 'Origin',
                  airport: origin,
                  alignEnd: false,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: [
                    const Icon(Icons.flight_takeoff, color: Color(0xff77c9ff)),
                    const SizedBox(height: 4),
                    Text(
                      _distanceLabel(distanceKm),
                      style: const TextStyle(
                        color: Color(0xff9aa4b5),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _JourneyAirportBlock(
                  label: 'Destination',
                  airport: destination,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _JourneyPill(
                icon: Icons.groups,
                label: '${_formatCount(demand)} pax/day',
              ),
              _JourneyPill(
                icon: Icons.trending_up,
                label: '${money(potentialValue, currency)}/day potential',
              ),
              _JourneyPill(
                icon: Icons.route,
                label: competitorCount == 0
                    ? 'No live rivals'
                    : '$competitorCount live rival route${competitorCount == 1 ? '' : 's'}',
              ),
              _JourneyPill(
                icon: aircraftType == null
                    ? Icons.info_outline
                    : rangeLimited || runwayLimited
                    ? Icons.warning_amber
                    : Icons.check_circle,
                label: statusText,
                color: statusColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JourneyAirportBlock extends StatelessWidget {
  const _JourneyAirportBlock({
    required this.label,
    required this.airport,
    required this.alignEnd,
  });

  final String label;
  final Airport airport;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xff8b95a8), fontSize: 12),
      ),
      Text(
        airport.iata,
        style: const TextStyle(
          color: Color(0xff77c9ff),
          fontSize: 24,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
      Text(
        airport.city,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      Text(
        airport.country,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xff9aa4b5), fontSize: 12),
      ),
    ],
  );
}

class _JourneyPill extends StatelessWidget {
  const _JourneyPill({
    required this.icon,
    required this.label,
    this.color = const Color(0xff9aa4b5),
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: _subtleSurface(context),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: _hairline(context)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _CreateRouteDialog extends StatefulWidget {
  const _CreateRouteDialog({
    required this.game,
    required this.currency,
    required this.onClose,
    this.origin,
    this.destination,
  });
  final GameController game;
  final CurrencyOption currency;
  final VoidCallback onClose;
  final Airport? origin;
  final Airport? destination;
  @override
  State<_CreateRouteDialog> createState() => _CreateRouteDialogState();
}

class _CreateRouteDialogState extends State<_CreateRouteDialog> {
  late Airport origin = widget.origin ?? airportsByIata['LHR']!;
  late Airport destination = _initialRouteDestination(
    origin,
    widget.destination,
    widget.game,
  );
  AircraftType? type;
  late final ecoController = TextEditingController();
  late final bizController = TextEditingController();
  String? selectedAircraftId;
  String buyManufacturer = 'All';
  bool showAircraftShop = false;
  bool buyNewAircraft = false;
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
    final selectedAircraft = selectedAircraftId == null
        ? null
        : widget.game.aircraft[selectedAircraftId!];
    final selectedAircraftType = selectedAircraft == null
        ? null
        : aircraftTypesById[selectedAircraft.typeId];
    final selectedAircraftUsable =
        selectedAircraftType != null &&
        selectedAircraftType.rangeKm >= distance &&
        canAirportHandleAircraft(origin, selectedAircraftType) &&
        canAirportHandleAircraft(destination, selectedAircraftType);
    final sameAirport = origin.iata == destination.iata;
    final buyableAircraft = aircraftTypes
        .where(
          (t) =>
              t.yearIntroduced <= gameYear &&
              t.rangeKm >= distance &&
              canAirportHandleAircraft(origin, t) &&
              canAirportHandleAircraft(destination, t),
        )
        .toList();
    buyableAircraft.sort((a, b) => a.purchasePrice.compareTo(b.purchasePrice));
    if (type != null && !buyableAircraft.contains(type)) {
      type = null;
      buyNewAircraft = false;
    }
    final effectiveType =
        selectedAircraftType ?? (buyNewAircraft ? type : null);
    final guideType =
        effectiveType ?? buyableAircraft.firstOrNull ?? aircraftTypes.first;
    final runwayLimited =
        effectiveType != null &&
        (!canAirportHandleAircraft(origin, effectiveType) ||
            !canAirportHandleAircraft(destination, effectiveType));
    final rangeLimited =
        effectiveType != null && effectiveType.rangeKm < distance;
    final pair = routePairKey(origin.iata, destination.iata);
    final competitorCount = widget.game.routes.values
        .where(
          (route) =>
              route.isActive &&
              route.airlineId != 'player' &&
              routePairKey(route.originIata, route.destinationIata) == pair,
        )
        .length;
    final hasAircraftForRoute =
        selectedAircraft != null || (buyNewAircraft && type != null);
    final canAffordPendingAircraft =
        !buyNewAircraft ||
        selectedAircraft != null ||
        (type != null && widget.game.player.cashUSD >= type!.purchasePrice);
    final pendingPurchaseValid =
        !buyNewAircraft ||
        selectedAircraft != null ||
        (type != null &&
            buyableAircraft.contains(type) &&
            canAffordPendingAircraft);
    final canCreate =
        !sameAirport &&
        (selectedAircraft == null || selectedAircraftUsable) &&
        pendingPurchaseValid;
    final availableAircraft = widget.game.player.fleetIds
        .map((id) => widget.game.aircraft[id])
        .whereType<Aircraft>()
        .where(
          (ac) =>
              ac.assignedRouteId == null &&
              ac.status == AircraftStatus.idle &&
              ac.airlineId == 'player',
        )
        .toList();
    final manufacturers =
        <String>{'All', ...buyableAircraft.map((t) => t.manufacturer)}.toList()
          ..sort((a, b) {
            if (a == 'All') return -1;
            if (b == 'All') return 1;
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
    final shopAircraft = buyManufacturer == 'All'
        ? buyableAircraft
        : buyableAircraft
              .where((t) => t.manufacturer == buyManufacturer)
              .toList(growable: false);
    final fareGuide = _currentFareGuide(distance, guideType);
    final previewRoute = _previewRoute(distance, fareGuide);
    final previewAircraft = effectiveType == null
        ? null
        : Aircraft(
            id: 'preview',
            typeId: effectiveType.id,
            name: effectiveType.displayName,
            airlineId: 'player',
            purchasedGameDay: widget.game.gameDay,
            condition: selectedAircraft?.condition ?? 100,
          );
    final previewEconomics = !hasAircraftForRoute
        ? null
        : calculateRouteEconomics(
            route: previewRoute,
            aircraft: previewAircraft!,
            type: effectiveType!,
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AirportDropdown(
                label: 'Origin',
                value: origin,
                onChanged: (a) => setState(() {
                  origin = a;
                  if (destination.iata == a.iata) {
                    destination = _fallbackRouteDestination(a, widget.game);
                  }
                  error = null;
                }),
              ),
              const SizedBox(height: 10),
              _AirportDropdown(
                label: 'Destination',
                value: destination,
                onChanged: (a) => setState(() {
                  destination = a;
                  error = null;
                }),
              ),
              if (sameAirport) ...[
                const SizedBox(height: 8),
                const _InlineWarning(
                  'Origin and destination must be different airports.',
                ),
              ],
              const SizedBox(height: 10),
              _RouteJourneyCard(
                origin: origin,
                destination: destination,
                distanceKm: distance,
                demand: sameAirport
                    ? 0
                    : baselineDailyPassengers(origin, destination),
                competitorCount: sameAirport ? 0 : competitorCount,
                aircraftType: effectiveType,
                rangeLimited: rangeLimited,
                runwayLimited: runwayLimited,
                currency: widget.currency,
              ),
              const SizedBox(height: 10),
              _RouteAircraftPicker(
                availableAircraft: availableAircraft,
                selectedAircraftId: selectedAircraftId,
                pendingType: selectedAircraft == null && buyNewAircraft
                    ? type
                    : null,
                noAircraftSelected: selectedAircraft == null && !buyNewAircraft,
                distanceKm: distance,
                origin: origin,
                destination: destination,
                currency: widget.currency,
                onSelectNoAircraft: () => setState(() {
                  selectedAircraftId = null;
                  buyNewAircraft = false;
                  type = null;
                }),
                onSelectAircraft: (id) => setState(() {
                  selectedAircraftId = id;
                  buyNewAircraft = false;
                  final acType =
                      aircraftTypesById[widget.game.aircraft[id]!.typeId];
                  if (acType != null) type = acType;
                }),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => showAircraftShop = !showAircraftShop),
                  icon: Icon(
                    showAircraftShop ? Icons.expand_less : Icons.add_circle,
                  ),
                  label: Text(
                    showAircraftShop
                        ? 'Hide aircraft shop'
                        : 'Buy new aircraft',
                  ),
                ),
              ),
              if (showAircraftShop)
                _InlineAircraftShop(
                  types: shopAircraft,
                  manufacturers: manufacturers,
                  selectedManufacturer: buyManufacturer,
                  selectedTypeId: selectedAircraft == null ? type?.id : null,
                  distanceKm: distance,
                  cash: widget.game.player.cashUSD,
                  origin: origin,
                  destination: destination,
                  currency: widget.currency,
                  onManufacturerChanged: (value) =>
                      setState(() => buyManufacturer = value),
                  onSelected: (selectedType) => setState(() {
                    type = selectedType;
                    selectedAircraftId = null;
                    buyNewAircraft = true;
                    showAircraftShop = false;
                  }),
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
                label: guideType.seatsBusiness > 0
                    ? 'Business fare (${widget.currency.code})'
                    : 'No business cabin',
                suggested: fareGuide.suggestedBusiness,
                maxFare: fareGuide.maxBusiness,
                currency: widget.currency,
                enabled: guideType.seatsBusiness > 0,
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
                      onPressed:
                          !hasAircraftForRoute ||
                              !pendingPurchaseValid ||
                              (buyableAircraft.isEmpty &&
                                  selectedAircraft == null &&
                                  buyNewAircraft) ||
                              (selectedAircraft != null &&
                                  !selectedAircraftUsable) ||
                              sameAirport
                          ? null
                          : _optimiseSetup,
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canCreate ? _create : null,
          child: Text(
            !hasAircraftForRoute
                ? 'Create inactive route'
                : selectedAircraft == null
                ? 'Create + buy ${type?.model ?? 'aircraft'}'
                : 'Create + assign ${selectedAircraftType?.model ?? 'aircraft'}',
          ),
        ),
      ],
    );
  }

  _FareGuide _currentFareGuide(double distance, AircraftType guideType) {
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
      typeId: guideType.id,
      name: guideType.displayName,
      airlineId: 'player',
      purchasedGameDay: widget.game.gameDay,
    );
    return _fareGuideForRoute(
      route: previewRoute,
      aircraft: previewAircraft,
      type: guideType,
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
    priceBusiness:
        fareGuide.suggestedBusiness <= 0 || bizController.text.trim().isEmpty
        ? 0
        : _clampedFare(bizController.text, fareGuide.maxBusiness),
    createdGameDay: widget.game.gameDay,
    distanceKm: distance,
  );

  void _optimiseSetup() {
    final optimisationType = selectedAircraftId == null
        ? type
        : aircraftTypesById[widget.game.aircraft[selectedAircraftId!]?.typeId];
    if (optimisationType == null) return;
    final distance = haversineKm(
      origin.lat,
      origin.lon,
      destination.lat,
      destination.lon,
    );
    final fareGuide = _currentFareGuide(distance, optimisationType);
    final previewRoute = _previewRoute(distance, fareGuide);
    final previewAircraft = Aircraft(
      id: 'preview',
      typeId: optimisationType.id,
      name: optimisationType.displayName,
      airlineId: 'player',
      purchasedGameDay: widget.game.gameDay,
    );
    final result = optimiseRouteSettings(
      RouteOptimisationInput(
        route: previewRoute,
        aircraft: previewAircraft,
        aircraftType: optimisationType,
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
      final createType = selectedAircraftId == null
          ? (type ??
                _fallbackAircraftTypeForRoute(origin, destination, widget.game))
          : aircraftTypesById[widget
                .game
                .aircraft[selectedAircraftId!]!
                .typeId];
      if (createType == null) {
        throw StateError('No compatible aircraft type available for route');
      }
      final fareGuide = _currentFareGuide(distance, createType);
      widget.onClose();
      final route = widget.game.createRoute(
        originIata: origin.iata,
        destinationIata: destination.iata,
        aircraftTypeId: createType.id,
        aircraftId: selectedAircraftId,
        flightsPerWeek: flights,
        priceEconomy: ecoController.text.trim().isEmpty
            ? null
            : _clampedFare(ecoController.text, fareGuide.maxEconomy),
        priceBusiness:
            createType.seatsBusiness <= 0 || bizController.text.trim().isEmpty
            ? null
            : _clampedFare(bizController.text, fareGuide.maxBusiness),
        buyNewAircraft: buyNewAircraft && selectedAircraftId == null,
      );
      if (optimise && route.aircraftId != null) {
        try {
          widget.game.optimiseRoute(route.id);
        } catch (_) {
          // Route creation has succeeded; optimisation can still be retried
          // from route detail if the route is missing transient data.
        }
      }
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
    }
  }
}

Airport _initialRouteDestination(
  Airport origin,
  Airport? requested,
  GameController game,
) {
  if (requested != null && requested.iata != origin.iata) return requested;
  return _fallbackRouteDestination(origin, game);
}

Airport _fallbackRouteDestination(Airport origin, GameController game) {
  const preferred = ['JFK', 'LHR', 'LAX', 'CDG', 'HND', 'DXB', 'SYD'];
  for (final iata in preferred) {
    final airport = airportsByIata[iata];
    if (airport != null &&
        airport.iata != origin.iata &&
        _hasAffordableRouteAircraft(origin, airport, game)) {
      return airport;
    }
  }
  for (final airport in airports) {
    if (airport.iata != origin.iata &&
        _hasAffordableRouteAircraft(origin, airport, game)) {
      return airport;
    }
  }
  for (final iata in preferred) {
    final airport = airportsByIata[iata];
    if (airport != null && airport.iata != origin.iata) return airport;
  }
  return airports.firstWhere(
    (airport) => airport.iata != origin.iata,
    orElse: () => origin,
  );
}

bool _hasAffordableRouteAircraft(
  Airport origin,
  Airport destination,
  GameController game,
) {
  final distance = haversineKm(
    origin.lat,
    origin.lon,
    destination.lat,
    destination.lon,
  );
  final gameYear = game.settings.startingYear + game.gameDay ~/ 365;
  for (final type in aircraftTypes) {
    if (type.yearIntroduced > gameYear) continue;
    if (type.purchasePrice > game.player.cashUSD) continue;
    if (type.rangeKm < distance) continue;
    if (!canAirportHandleAircraft(origin, type) ||
        !canAirportHandleAircraft(destination, type)) {
      continue;
    }
    return true;
  }
  return false;
}

AircraftType? _fallbackAircraftTypeForRoute(
  Airport origin,
  Airport destination,
  GameController game,
) {
  final distance = haversineKm(
    origin.lat,
    origin.lon,
    destination.lat,
    destination.lon,
  );
  final gameYear = game.settings.startingYear + game.gameDay ~/ 365;
  final compatible =
      aircraftTypes
          .where(
            (type) =>
                type.yearIntroduced <= gameYear &&
                type.rangeKm >= distance &&
                canAirportHandleAircraft(origin, type) &&
                canAirportHandleAircraft(destination, type),
          )
          .toList()
        ..sort((a, b) => a.purchasePrice.compareTo(b.purchasePrice));
  return compatible.firstOrNull;
}

class _RouteAircraftPicker extends StatelessWidget {
  const _RouteAircraftPicker({
    required this.availableAircraft,
    required this.selectedAircraftId,
    required this.pendingType,
    required this.noAircraftSelected,
    required this.distanceKm,
    required this.origin,
    required this.destination,
    required this.currency,
    required this.onSelectNoAircraft,
    required this.onSelectAircraft,
  });

  final List<Aircraft> availableAircraft;
  final String? selectedAircraftId;
  final AircraftType? pendingType;
  final bool noAircraftSelected;
  final double distanceKm;
  final Airport origin;
  final Airport destination;
  final CurrencyOption currency;
  final VoidCallback onSelectNoAircraft;
  final ValueChanged<String> onSelectAircraft;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Aircraft', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            pendingType == null
                ? 'Use an idle aircraft from your fleet, or create the route inactive.'
                : '${pendingType!.displayName} will be purchased when this route is created.',
            style: const TextStyle(color: Color(0xff9aa4b5)),
          ),
          const SizedBox(height: 10),
          _SelectableInfoRow(
            selected: noAircraftSelected,
            enabled: true,
            title: 'No aircraft',
            subtitle: 'Create the route inactive and assign a plane later.',
            trailing: 'inactive',
            onTap: onSelectNoAircraft,
          ),
          if (pendingType != null) ...[
            const SizedBox(height: 10),
            _SelectableInfoRow(
              selected: selectedAircraftId == null,
              enabled: true,
              title: 'New ${pendingType!.displayName}',
              subtitle:
                  '${pendingType!.seatsEconomy}Y'
                  '${pendingType!.seatsBusiness > 0 ? '/${pendingType!.seatsBusiness}J' : ''}'
                  ' · ${pendingType!.rangeKm.toStringAsFixed(0)} km · '
                  '${money(pendingType!.purchasePrice, currency)}',
              trailing: 'buy on create',
              onTap: () {},
            ),
          ],
          if (availableAircraft.isNotEmpty) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: availableAircraft.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final ac = availableAircraft[index];
                  final acType = aircraftTypesById[ac.typeId];
                  final tooFar = acType != null && distanceKm > acType.rangeKm;
                  final runwayLimited =
                      acType != null &&
                      (!canAirportHandleAircraft(origin, acType) ||
                          !canAirportHandleAircraft(destination, acType));
                  final enabled = acType != null && !tooFar && !runwayLimited;
                  final subtitle = acType == null
                      ? ac.typeId
                      : '${acType.displayName} · '
                            '${acType.seatsEconomy}Y'
                            '${acType.seatsBusiness > 0 ? '/${acType.seatsBusiness}J' : ''}'
                            ' · condition ${ac.condition.toStringAsFixed(0)}%';
                  final reason = tooFar
                      ? 'out of range'
                      : runwayLimited
                      ? 'runway too short'
                      : null;
                  return _SelectableInfoRow(
                    selected: selectedAircraftId == ac.id,
                    enabled: enabled,
                    title: ac.name,
                    subtitle: subtitle,
                    trailing: reason,
                    onTap: () => onSelectAircraft(ac.id),
                  );
                },
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            const Text(
              'No idle aircraft are available. Buy one below.',
              style: TextStyle(color: Color(0xff6f7a8d), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineAircraftShop extends StatelessWidget {
  const _InlineAircraftShop({
    required this.types,
    required this.manufacturers,
    required this.selectedManufacturer,
    required this.selectedTypeId,
    required this.distanceKm,
    required this.cash,
    required this.origin,
    required this.destination,
    required this.currency,
    required this.onManufacturerChanged,
    required this.onSelected,
  });

  final List<AircraftType> types;
  final List<String> manufacturers;
  final String selectedManufacturer;
  final String? selectedTypeId;
  final double distanceKm;
  final double cash;
  final Airport origin;
  final Airport destination;
  final CurrencyOption currency;
  final ValueChanged<String> onManufacturerChanged;
  final ValueChanged<AircraftType> onSelected;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Aircraft shop · cash ${money(cash, currency)}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${distanceKm.toStringAsFixed(0)} km',
                style: const TextStyle(color: Color(0xff9aa4b5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: manufacturers.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final manufacturer = manufacturers[index];
                final selected = selectedManufacturer == manufacturer;
                return ChoiceChip(
                  label: Text(manufacturer),
                  selected: selected,
                  onSelected: (_) => onManufacturerChanged(manufacturer),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: types.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final type = types[index];
                final canAfford = cash >= type.purchasePrice;
                final runwayLimited =
                    !canAirportHandleAircraft(origin, type) ||
                    !canAirportHandleAircraft(destination, type);
                final enabled = canAfford && !runwayLimited;
                final trailing = !canAfford
                    ? 'too expensive'
                    : runwayLimited
                    ? 'runway too short'
                    : selectedTypeId == type.id
                    ? 'selected'
                    : null;
                return _SelectableInfoRow(
                  selected: selectedTypeId == type.id,
                  enabled: enabled,
                  title: type.displayName,
                  subtitle:
                      '${_aircraftCategoryLabel(type.category)} · '
                      '${type.seatsEconomy}Y'
                      '${type.seatsBusiness > 0 ? '/${type.seatsBusiness}J' : ''}'
                      ' · ${type.rangeKm.toStringAsFixed(0)} km range · '
                      '${type.minRunwayM} m runway · '
                      '${type.cruiseSpeedKmh} km/h · '
                      '${money(type.purchasePrice, currency)}',
                  trailing: trailing,
                  onTap: () => onSelected(type),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableInfoRow extends StatelessWidget {
  const _SelectableInfoRow({
    required this.selected,
    required this.enabled,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final bool selected;
  final bool enabled;
  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected ? const Color(0xff5db4ff) : const Color(0xff273145);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xff1c4268)
              : enabled
              ? const Color(0xff141b2b)
              : const Color(0xff101524),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.airplanemode_active,
              color: enabled
                  ? selected
                        ? const Color(0xff74c0fc)
                        : const Color(0xff9aa4b5)
                  : const Color(0xff4a5263),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: enabled ? Colors.white : const Color(0xff5d6678),
                    ),
                  ),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled
                          ? const Color(0xff9aa4b5)
                          : const Color(0xff4f586a),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Text(
                trailing!,
                style: TextStyle(
                  color: enabled
                      ? const Color(0xff7dd3fc)
                      : const Color(0xffff7a7a),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xffff6b6b).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xffff6b6b).withValues(alpha: 0.4)),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber, color: Color(0xffff9d9d), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xffffb3b3),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
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
      onChanged: (text) {
        final match = _airportFromTypedRouteQuery(text);
        if (match != null && match.iata != value.iata) onChanged(match);
      },
      onSubmitted: (text) {
        final match =
            _airportFromTypedRouteQuery(text) ??
            searchAirports(text, airports, limit: 1).firstOrNull;
        if (match != null) onChanged(match);
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.flight_takeoff),
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

Airport? _airportFromTypedRouteQuery(String query) {
  final normalized = query.trim().toUpperCase();
  if (normalized.isEmpty) return null;
  final direct = airportsByIata[normalized];
  if (direct != null) return direct;
  for (final airport in airports) {
    if (airport.icao?.toUpperCase() == normalized) return airport;
  }
  return null;
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
    final speed = widget.game.speed;
    final article = item.articleId == null
        ? null
        : widget.game.newsArticles[item.articleId!];
    final isAlert =
        item.playerRelated ||
        item.severity == 'fleet' ||
        item.severity == 'breaking';
    final tickerText =
        '${isAlert ? '‼️ ' : ''}${item.text}${article == null ? '' : ' Read the article'}';
    final tagText = isAlert ? 'FLEET ALERT' : 'NEWS';
    final tagColor =
        isAlert ? const Color(0xffff8c42) : const Color(0xffffd166);
    final tagBg = isAlert
        ? const Color(0xffffd166).withValues(alpha: 0.12)
        : Colors.transparent;

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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: tagBg,
                border: Border.all(
                  color: tagColor.withValues(alpha: 0.45),
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tagText,
                style: TextStyle(
                  color: tagColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRect(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('${item.id}-$animationCycle-$speed'),
                  tween: Tween(begin: 1, end: -1),
                  duration: Duration(seconds: _tickerDurationSeconds(speed)),
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
            ),
          ],
        ),
      ),
    );
  }

  int _tickerDurationSeconds(int speed) {
    if (speed >= 14400) return 5;
    if (speed >= 3600) return 7;
    if (speed >= 1200) return 10;
    if (speed >= 300) return 15;
    return 22;
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
