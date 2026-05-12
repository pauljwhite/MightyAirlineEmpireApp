import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/airport_search.dart';
import 'core/format.dart';
import 'core/geo.dart';
import 'data/aircraft_types.dart';
import 'data/airports.dart';
import 'engine/demand_model.dart';
import 'engine/economics_engine.dart';
import 'engine/finance.dart';
import 'engine/hub_upgrades.dart';
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
  var currency = currencyOptions.first;
  Airport? selectedAirport = airportsByIata['LHR'];
  var panel = _Panel.routes;
  var mobileSearchOpen = false;
  var showAiOnMap = true;

  @override
  void initState() {
    super.initState();
    game = GameController();
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: game,
      builder: (context, _) {
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
                          game: game,
                          showAiOnMap: showAiOnMap,
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

enum _Panel { routes, fleet, finance, competitors }

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
    final message = won
        ? game.settings.objective == GameObjective.marketShare
              ? 'You reached ${game.settings.targetMarketShare.round()}% market share.'
              : 'You are the last airline standing.'
        : '${player.name} has become insolvent.';
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
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(color: Colors.white70, fontSize: 17),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _OutcomeStat(
                      label: 'Cash',
                      value: money(player.cashUSD, currency),
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
                      value: player.totalPassengersAllTime.toString(),
                    ),
                    _OutcomeStat(
                      label: 'Market share',
                      value: '${player.marketSharePercent.toStringAsFixed(1)}%',
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
                    Expanded(
                      child: OutlinedButton(
                        onPressed: game.dismissGameOutcome,
                        child: const Text('Continue Playing'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: onNewGame,
                        child: const Text('Start Again'),
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
  const _OutcomeStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
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
      color: const Color(0xee050915),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: [
              _AirlineBadge(game: game, currency: currency),
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
  const _AirlineBadge({required this.game, required this.currency});
  final GameController game;
  final CurrencyOption currency;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xff111827),
      border: Border.all(color: const Color(0xff263247)),
      borderRadius: BorderRadius.circular(28),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(game.player.logoEmoji, style: const TextStyle(fontSize: 24)),
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
              style: const TextStyle(
                color: Color(0xff3af083),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    ),
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
      PopupMenuItem(value: 'new', child: Text('Start again')),
    ],
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
                        Text(
                          logo.isEmpty ? game.player.logoEmoji : logo,
                          style: const TextStyle(fontSize: 34),
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
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Logo emoji or short mark',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() => error = null),
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
                  TextField(
                    controller: emojiController,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'Logo emoji',
                      counterText: '',
                      border: OutlineInputBorder(),
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
                    playerAirlineEmoji: emoji.isEmpty ? '✈️' : emoji,
                    difficulty: difficulty,
                    startingCash: startingCash,
                    aiCount: aiCount,
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

void _showExportDialog(BuildContext context, GameController game) {
  final json = game.exportJson();
  final controller = TextEditingController(text: json);
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
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
  );
}

void _showImportDialog(
  BuildContext context,
  GameController game,
  ValueChanged<CurrencyOption> onCurrency,
) {
  final controller = TextEditingController();
  String? error;
  showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              try {
                game.importJson(controller.text);
                final importedCurrency = currencyOptions.firstWhere(
                  (option) => option.code == game.settings.currency,
                  orElse: () => currencyOptions.first,
                );
                onCurrency(importedCurrency);
                Navigator.pop(context);
              } catch (e) {
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xff111827),
        border: Border.all(color: const Color(0xff263247)),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        'Day $day, $year',
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
  });
  final GameController game;
  final bool showAiOnMap;
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
}

Offset _airportPoint(Airport a, Size size) => Offset(
  ((a.lon + 180) / 360) * size.width,
  ((85 - a.lat.clamp(-85.0, 85.0)) / 170) * size.height,
);

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
      final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      final lift = ((end - start).distance * 0.12).clamp(16, 80).toDouble();
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(mid.dx, mid.dy - lift, end.dx, end.dy);
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
    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final lift = ((end - start).distance * 0.12).clamp(16, 80).toDouble();
    final control = Offset(mid.dx, mid.dy - lift);
    final progressSeed = _routeSeed(route.id) / 997.0;
    final cycle =
        (game.gameDay * math.max(1, route.flightsPerWeek) * 0.071 +
            progressSeed) %
        2.0;
    final t = cycle <= 1 ? cycle : 2 - cycle;
    final from = cycle <= 1 ? start : end;
    final to = cycle <= 1 ? end : start;
    final controlPoint = cycle <= 1 ? control : control;
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

  int _routeSeed(String value) =>
      value.codeUnits.fold(0, (sum, unit) => (sum + unit * 31) % 997);

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
    final destinations =
        game.airportList
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
                _InfoRow('ICAO', airport.icao ?? '-'),
                _InfoRow('Size', airport.size.name),
                _InfoRow('Hub', isPlayerHub ? 'Yes' : 'No'),
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
                          onTap: () => onCreateRoute(airport, item.airport),
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
                    onPressed: () => onCreateRoute(airport, null),
                    icon: const Icon(Icons.add),
                    label: const Text('New Route'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isPlayerHub
                        ? null
                        : () => game.setPlayerHub(airport.iata),
                    icon: const Icon(Icons.apartment),
                    label: Text(isPlayerHub ? 'Hub' : 'Set Hub'),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: onCreateRoute,
          icon: const Icon(Icons.add_road),
          label: const Text('New Route'),
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

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.game,
    required this.route,
    required this.currency,
  });
  final GameController game;
  final RoutePlan route;
  final CurrencyOption currency;
  @override
  Widget build(BuildContext context) {
    final ac = route.aircraftId == null
        ? null
        : game.aircraft[route.aircraftId!];
    final type = ac == null ? null : aircraftTypesById[ac.typeId];
    final loadFactor = (route.loadFactorEconomy * 100).round();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
          const SizedBox(height: 6),
          Text(
            type == null
                ? 'No aircraft assigned'
                : '${type.displayName} · ${route.flightsPerWeek}/week · $loadFactor% LF',
            style: const TextStyle(color: Color(0xff9aa4b5)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => game.optimiseRoute(route.id),
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Optimise'),
              ),
              OutlinedButton.icon(
                onPressed: game.runDailyTick,
                icon: const Icon(Icons.skip_next),
                label: const Text('Run day'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FleetView extends StatelessWidget {
  const _FleetView({required this.game, required this.currency});
  final GameController game;
  final CurrencyOption currency;
  @override
  Widget build(BuildContext context) {
    final fleet = game.playerFleet;
    final policy = game.player.maintenancePolicy;
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
          return _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ac.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  type?.displayName ?? ac.typeId,
                  style: const TextStyle(color: Color(0xff9aa4b5)),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: ac.condition / 100,
                  color: ac.condition < 35
                      ? const Color(0xffff6b6b)
                      : const Color(0xff3af083),
                ),
                const SizedBox(height: 8),
                Text(
                  route == null
                      ? 'Unassigned'
                      : 'Route ${route.originIata} -> ${route.destinationIata}',
                ),
                Text(
                  ac.status == AircraftStatus.maintenance
                      ? 'In ${ac.activeMaintTier?.name ?? 'standard'} maintenance since day ${ac.lastMaintenanceGameDay}'
                      : 'Maintenance owed ${ac.maintenanceHoursOwed.toStringAsFixed(1)}h',
                  style: const TextStyle(color: Color(0xff9aa4b5)),
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

class _FinanceView extends StatelessWidget {
  const _FinanceView({required this.game, required this.currency});
  final GameController game;
  final CurrencyOption currency;
  @override
  Widget build(BuildContext context) {
    final player = game.player;
    final last = player.dailyStats.lastOrNull;
    final lastProfit = last?.profit ?? player.lastDailyProfit;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetricCard(
          'Cash',
          money(player.cashUSD, currency),
          const Color(0xff3af083),
        ),
        _MetricCard(
          'Last daily profit',
          money(lastProfit, currency),
          lastProfit >= 0 ? const Color(0xff3af083) : const Color(0xffff6b6b),
        ),
        _MetricCard(
          'Debt',
          money(player.totalDebt, currency),
          const Color(0xffffd166),
        ),
        ExpansionTile(
          title: const Text('Loans'),
          initiallyExpanded: true,
          children: [
            ...player.loans.map(
              (loan) => ListTile(
                title: Text(money(loan.principalUSD, currency)),
                subtitle: Text(
                  '${formatInterestRate(loan.annualInterestRate)} · ${loan.termYears} years · ${money(loan.dailyPaymentUSD, currency)}/day',
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: loanOffers
                  .map(
                    (offer) => OutlinedButton(
                      onPressed: () => game.applyForLoan(offer),
                      child: Text(
                        '${money(offer.amountUSD, currency)} · ${formatInterestRate(offer.annualInterestRate)}',
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: player.loans.isEmpty
                        ? null
                        : () => game.repayLoans(player.cashUSD),
                    child: const Text('Repay what I can afford'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: player.loans.isEmpty
                        ? null
                        : () => game.repayLoans(player.totalDebt * 0.25),
                    child: const Text('Repay 25%'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
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
      final profitableRoutes = routes
          .where((route) => route.dailyProfit > 0)
          .length;
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
                    Text(
                      airline.logoEmoji,
                      style: const TextStyle(fontSize: 26),
                    ),
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
                _InfoRow(
                  'Last profit',
                  money(airline.lastDailyProfit, widget.currency),
                ),
                _InfoRow('Company value', money(companyValue, widget.currency)),
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
                  '${routes.length} routes · $profitableRoutes profitable',
                ),
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
                  Text(airline.logoEmoji, style: const TextStyle(fontSize: 24)),
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
              TextField(
                controller: ecoController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Economy fare (${widget.currency.code})',
                  prefixIcon: const Icon(Icons.payments),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bizController,
                enabled: hasBusiness,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: hasBusiness
                      ? 'Business fare (${widget.currency.code})'
                      : 'No business cabin',
                  prefixIcon: const Icon(Icons.business_center),
                ),
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
              priceEconomy: int.tryParse(ecoController.text) ?? 0,
              priceBusiness: hasBusiness
                  ? int.tryParse(bizController.text) ?? 0
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
  int flights = 7;
  bool optimise = true;
  String? error;

  @override
  Widget build(BuildContext context) {
    final distance = haversineKm(
      origin.lat,
      origin.lon,
      destination.lat,
      destination.lon,
    );
    final viableAircraft = aircraftTypes
        .where((t) => t.rangeKm >= distance)
        .take(90)
        .toList();
    if (!viableAircraft.contains(type) && viableAircraft.isNotEmpty)
      type = viableAircraft.first;
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

  void _create() {
    try {
      final route = widget.game.createRoute(
        originIata: origin.iata,
        destinationIata: destination.iata,
        aircraftTypeId: type.id,
        flightsPerWeek: flights,
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
      color: const Color(0xff151b2b),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xff273246)),
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
      color: const Color(0xee0b1020),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xff263247)),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 22)],
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
  );
}

class _Ticker extends StatelessWidget {
  const _Ticker({required this.game});
  final GameController game;
  @override
  Widget build(BuildContext context) {
    final text = game.newsTicker.isEmpty
        ? 'Native Flutter parity port underway'
        : game.newsTicker.last;
    final speed = game.speed == 0 ? 1 : (game.speed / 300).round();
    final article = game.latestArticle;
    return InkWell(
      onTap: article == null
          ? null
          : () => _showHeraldArticle(context, game, article),
      child: Container(
        height: 42,
        color: const Color(0xff050915),
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          key: ValueKey(text + speed.toString()),
          tween: Tween(begin: 1, end: -1),
          duration: Duration(
            seconds: speed <= 1
                ? 24
                : speed == 3
                ? 16
                : 10,
          ),
          builder: (context, value, child) => FractionalTranslation(
            translation: Offset(value, 0),
            child: child,
          ),
          child: Text(
            '  $text',
            maxLines: 1,
            style: TextStyle(
              color: article == null
                  ? const Color(0xffc7d2e5)
                  : const Color(0xffffd166),
              fontWeight: FontWeight.w700,
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
  NewsArticle article,
) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(article.headline),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                article.subheadline,
                style: const TextStyle(
                  color: Color(0xff9aa4b5),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              ...article.paragraphs.map(
                (paragraph) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(paragraph),
                ),
              ),
              if (article.actionAircraftId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      game.startMaintenance(
                        article.actionAircraftId!,
                        MaintenanceTier.standard,
                      );
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.build),
                    label: Text(
                      'Send to maintenance (${article.actionMaintenanceCost ?? 0} USD)',
                    ),
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
    ),
  );
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
