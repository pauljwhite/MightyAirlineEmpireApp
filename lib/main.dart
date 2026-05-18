import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
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
  (value: 1200, label: '3x'),
  (value: 3600, label: '5x'),
  (value: 14400, label: '10x'),
];

void main() => runApp(const MightyAirlineEmpireApp());

class MightyAirlineEmpireApp extends StatefulWidget {
  const MightyAirlineEmpireApp({super.key});
  @override
  State<MightyAirlineEmpireApp> createState() => _MightyAirlineEmpireAppState();
}

class _MightyAirlineEmpireAppState extends State<MightyAirlineEmpireApp>
    with WidgetsBindingObserver {
  late final GameController game;
  final _navigatorKey = GlobalKey<NavigatorState>();
  Timer? _gameLoop;
  DateTime? _lastTickAt;
  var _autoSaveChecked = false;
  var currency = currencyOptions.first;
  Airport? selectedAirport;
  _Panel? panel;
  var mobileSearchOpen = false;
  final _autoOpenedArticleIds = <String>{};
  ThemeData? _cachedLightTheme;
  ThemeData? _cachedDarkTheme;
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    game = GameController(autoStart: false);
    _themeMode = game.themeMode == ThemeModeSetting.light
        ? ThemeMode.light
        : ThemeMode.dark;
    game.addListener(_syncThemeMode);
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
    _tryRestoreAutoSave();
  }

  void _tryRestoreAutoSave() {
    GameController.loadAutoSave().then((saved) {
      if (!mounted) return;
      if (saved != null && !game.hasStarted) {
        try {
          game.importJson(saved);
          final restoredCurrency = currencyOptions.firstWhere(
            (c) => c.code == game.settings.currency,
            orElse: () => currencyOptions.first,
          );
          setState(() {
            currency = restoredCurrency;
            _autoSaveChecked = true;
            _themeMode = game.themeMode == ThemeModeSetting.light
                ? ThemeMode.light
                : ThemeMode.dark;
          });
          return;
        } catch (_) {
          // Corrupt save — fall through to show new-game dialog
        }
      }
      // No save or corrupt save: show splash screen
      setState(() => _autoSaveChecked = true);
    });
  }

  void _syncThemeMode() {
    final next = game.themeMode == ThemeModeSetting.light
        ? ThemeMode.light
        : ThemeMode.dark;
    if (next != _themeMode) setState(() => _themeMode = next);
  }

  Future<void> _resetToSplash() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('mighty_airline_autosave');
    game.resetToPreStart();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (game.hasStarted) {
        SharedPreferences.getInstance().then(
          (prefs) => prefs.setString('mighty_airline_autosave', game.exportJson()),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    final isPlayerCrash = article.playerRelated && article.severity == 'crash';
    if (!isPlayerCrash) {
      if (article.actionAircraftId == null) return;
      if (game.player.maintenancePolicy.autoMaintainIssues) return;
    }
    _autoOpenedArticleIds.add(article.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !game.newsArticles.containsKey(article.id)) return;
      final dialogContext = _navigatorKey.currentContext ?? context;
      _showHeraldArticle(dialogContext, game, article);
    });
  }

  ThemeData _buildTheme(bool lightMode) {
    return (lightMode
                      ? ThemeData.light(useMaterial3: true)
                      : ThemeData.dark(useMaterial3: true))
                  .copyWith(
                    scaffoldBackgroundColor: lightMode
                        ? const Color(0xfff2f2f7)
                        : const Color(0xff111111),
                    colorScheme: ColorScheme.fromSeed(
                      seedColor: const Color(0xff2f8cff),
                      brightness: lightMode
                          ? Brightness.light
                          : Brightness.dark,
                    ),
                    // ── Dialogs ────────────────────────────────────────────
                    dialogTheme: DialogThemeData(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      backgroundColor: lightMode
                          ? const Color(0xf8f8f8f8)
                          : const Color(0xec1c1c1c),
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      titleTextStyle: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: lightMode ? const Color(0xff111827) : Colors.white,
                      ),
                    ),
                    // ── Material button fallback (for any remaining M3 buttons) ──
                    filledButtonTheme: FilledButtonThemeData(
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith((s) {
                          if (s.contains(WidgetState.disabled)) {
                            return lightMode
                                ? const Color(0xffd0d0d0)
                                : const Color(0xff2a2a2a);
                          }
                          return const Color(0xff0a84ff);
                        }),
                        foregroundColor: WidgetStateProperty.resolveWith((s) =>
                            s.contains(WidgetState.disabled)
                                ? (lightMode
                                      ? const Color(0xff888888)
                                      : const Color(0xff555555))
                                : Colors.white),
                        overlayColor: WidgetStateProperty.resolveWith((s) =>
                            s.contains(WidgetState.pressed)
                                ? Colors.black.withValues(alpha: 0.15)
                                : s.contains(WidgetState.hovered)
                                ? Colors.black.withValues(alpha: 0.06)
                                : Colors.transparent),
                        shape: WidgetStateProperty.all(const StadiumBorder()),
                        elevation: WidgetStateProperty.all(0),
                        splashFactory: NoSplash.splashFactory,
                        textStyle: WidgetStateProperty.all(
                          const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        animationDuration: const Duration(milliseconds: 120),
                      ),
                    ),
                    outlinedButtonTheme: OutlinedButtonThemeData(
                      style: ButtonStyle(
                        foregroundColor: WidgetStateProperty.resolveWith((s) =>
                            s.contains(WidgetState.disabled)
                                ? (lightMode
                                      ? const Color(0xff9e9e9e)
                                      : const Color(0xff4a5568))
                                : lightMode
                                ? const Color(0xff1c1c1e)
                                : Colors.white),
                        backgroundColor: WidgetStateProperty.resolveWith((s) =>
                            s.contains(WidgetState.pressed)
                                ? (lightMode
                                      ? Colors.black.withValues(alpha: 0.06)
                                      : Colors.white.withValues(alpha: 0.10))
                                : (lightMode
                                      ? Colors.black.withValues(alpha: 0.03)
                                      : Colors.white.withValues(alpha: 0.06))),
                        side: WidgetStateProperty.resolveWith((s) => BorderSide(
                          color: lightMode
                              ? Colors.black.withValues(alpha: 0.11)
                              : Colors.white.withValues(alpha: 0.14),
                        )),
                        shape: WidgetStateProperty.all(const StadiumBorder()),
                        elevation: WidgetStateProperty.all(0),
                        splashFactory: NoSplash.splashFactory,
                        textStyle: WidgetStateProperty.all(
                          const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 11,
                          ),
                        ),
                        animationDuration: const Duration(milliseconds: 120),
                      ),
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: ButtonStyle(
                        foregroundColor: WidgetStateProperty.resolveWith((s) =>
                            s.contains(WidgetState.disabled)
                                ? (lightMode
                                      ? const Color(0xffb0b8c8)
                                      : const Color(0xff555555))
                                : const Color(0xff0a84ff)),
                        overlayColor: WidgetStateProperty.resolveWith((s) =>
                            s.contains(WidgetState.pressed)
                                ? const Color(0xff0a84ff).withValues(alpha: 0.1)
                                : s.contains(WidgetState.hovered)
                                ? const Color(0xff0a84ff).withValues(alpha: 0.05)
                                : Colors.transparent),
                        shape: WidgetStateProperty.all(const StadiumBorder()),
                        splashFactory: NoSplash.splashFactory,
                        textStyle: WidgetStateProperty.all(
                          const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                        animationDuration: const Duration(milliseconds: 120),
                      ),
                    ),
                    elevatedButtonTheme: ElevatedButtonThemeData(
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.all(
                          const Color(0xff0a84ff),
                        ),
                        foregroundColor: WidgetStateProperty.all(Colors.white),
                        shape: WidgetStateProperty.all(const StadiumBorder()),
                        elevation: WidgetStateProperty.all(0),
                        splashFactory: NoSplash.splashFactory,
                        animationDuration: const Duration(milliseconds: 120),
                      ),
                    ),
                    // ── Text inputs ────────────────────────────────────────
                    inputDecorationTheme: InputDecorationTheme(
                      filled: true,
                      fillColor: lightMode
                          ? const Color(0xffebebf0)
                          : Colors.white.withValues(alpha: 0.07),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: const Color(0xff2f8cff),
                          width: 2,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Color(0xffff453a),
                          width: 1.5,
                        ),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Color(0xffff453a),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      isDense: true,
                      hintStyle: TextStyle(
                        color: lightMode
                            ? const Color(0xff8e8e93)
                            : const Color(0xff636366),
                        fontSize: 15,
                      ),
                      labelStyle: TextStyle(
                        fontSize: 15,
                        color: lightMode
                            ? const Color(0xff636366)
                            : const Color(0xff8e8e93),
                      ),
                    ),
                    // ── Switch (iOS-like) ───────────────────────────────────
                    switchTheme: SwitchThemeData(
                      thumbColor: WidgetStateProperty.all(Colors.white),
                      trackColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return const Color(0xff30d158);
                        }
                        return lightMode
                            ? const Color(0xffe5e5ea)
                            : const Color(0xff39393d);
                      }),
                      trackOutlineColor: WidgetStateProperty.all(
                        Colors.transparent,
                      ),
                    ),
                    // ── Slider ──────────────────────────────────────────────
                    sliderTheme: SliderThemeData(
                      activeTrackColor: const Color(0xff2f8cff),
                      inactiveTrackColor: lightMode
                          ? const Color(0xffd1d1d6)
                          : Colors.white.withValues(alpha: 0.18),
                      thumbColor: Colors.white,
                      overlayColor: const Color(0x292f8cff),
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 11,
                        elevation: 3,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 20,
                      ),
                    ),
                    // ── Chips ───────────────────────────────────────────────
                    chipTheme: ChipThemeData(
                      shape: const StadiumBorder(),
                      side: BorderSide.none,
                      backgroundColor: lightMode
                          ? const Color(0xffe5e5ea)
                          : Colors.white.withValues(alpha: 0.1),
                      selectedColor: const Color(0xff2f8cff),
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: lightMode ? const Color(0xff1c1c1e) : Colors.white,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    // ── Segmented button ────────────────────────────────────
                    segmentedButtonTheme: SegmentedButtonThemeData(
                      style: SegmentedButton.styleFrom(
                        shape: const StadiumBorder(),
                        backgroundColor: lightMode
                            ? const Color(0xffe5e5ea)
                            : Colors.white.withValues(alpha: 0.08),
                        selectedBackgroundColor: const Color(0xff2f8cff),
                        foregroundColor: lightMode
                            ? const Color(0xff3c3c43)
                            : const Color(0xffaeaeb2),
                        selectedForegroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                        side: BorderSide.none,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                    // ── List tiles ───────────────────────────────────────────
                    listTileTheme: ListTileThemeData(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    // ── Popup / context menus ────────────────────────────────
                    popupMenuTheme: PopupMenuThemeData(
                      color: lightMode
                          ? const Color(0xf8f8f8f8)
                          : const Color(0xee1c1c1c),
                      elevation: 12,
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: lightMode
                              ? Colors.black.withValues(alpha: 0.07)
                              : Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        letterSpacing: -0.2,
                      ),
                      labelTextStyle: WidgetStateProperty.all(
                        const TextStyle(
                          fontSize: 15,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    // ── Snack bars ───────────────────────────────────────────
                    snackBarTheme: SnackBarThemeData(
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: lightMode
                          ? const Color(0xff2c2c2e)
                          : const Color(0xff2c2c2e),
                      contentTextStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
                    // ── Cards ────────────────────────────────────────────────
                    cardTheme: CardThemeData(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: lightMode
                              ? Colors.black.withValues(alpha: 0.07)
                              : Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      color: lightMode
                          ? const Color(0xfff8f8f8)
                          : const Color(0xff1e1e1e),
                      surfaceTintColor: Colors.transparent,
                    ),
                    // ── Dividers ─────────────────────────────────────────────
                    dividerTheme: DividerThemeData(
                      color: lightMode
                          ? Colors.black.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.08),
                      thickness: 0.5,
                      space: 1,
                    ),
                  );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Mighty Airline Empire',
      theme: _cachedLightTheme ??= _buildTheme(true),
      darkTheme: _cachedDarkTheme ??= _buildTheme(false),
      themeMode: _themeMode,
      home: AnimatedBuilder(
        animation: game,
        builder: (context, _) {
          return game.hasStarted
              ? PopScope(
                  canPop: panel == null && selectedAirport == null && !mobileSearchOpen,
                  onPopInvokedWithResult: (didPop, _) {
                    if (didPop) return;
                    setState(() {
                      if (panel != null) {
                        panel = null;
                      } else if (selectedAirport != null) {
                        selectedAirport = null;
                      } else if (mobileSearchOpen) {
                        mobileSearchOpen = false;
                      }
                    });
                  },
                  child: Scaffold(
                  body: SafeArea(
                    bottom: false,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 700;
                        // Inline search becomes too narrow before the mobile
                        // breakpoint — collapse it to a floating icon earlier.
                        final showSearch = constraints.maxWidth >= 900;
                        final topOffset = compact ? 70.0 : 68.0;
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
                                showSearch: showSearch,
                                currency: currency,
                                selectedPanel: panel,
                                onPanel: (p) => setState(
                                  () => panel = panel == p ? null : p,
                                ),
                                onCurrency: (v) => setState(() => currency = v),
                                onSpeed: game.setSpeed,
                                onAirport: (a) => setState(() {
                                  selectedAirport = a;
                                  mobileSearchOpen = false;
                                }),
                                onSearchToggle: () => setState(
                                  () => mobileSearchOpen = !mobileSearchOpen,
                                ),
                                onGameStart: () => setState(() => selectedAirport = null),
                                onReset: _resetToSplash,
                              ),
                            ),
                            Positioned(
                              top: topOffset,
                              left: 8,
                              right: 8,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _MapToggle(
                                    showAi: game.showAiOnMap,
                                    onChanged: game.setShowAiOnMap,
                                  ),
                                  if (compact || !showSearch) ...[
                                    const SizedBox(height: 5),
                                    _FloatingSearchRow(
                                      searchOpen: mobileSearchOpen,
                                      onToggle: () => setState(
                                        () => mobileSearchOpen = !mobileSearchOpen,
                                      ),
                                      onAirport: (a) => setState(() {
                                        selectedAirport = a;
                                        mobileSearchOpen = false;
                                      }),
                                    ),
                                  ],
                                ],
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
                                    onGameStart: () => setState(() => selectedAirport = null),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                )
              : _SplashScreen(
                  game: game,
                  currency: currency,
                  onCurrency: (v) => setState(() => currency = v),
                  onGameStart: () => setState(() => selectedAirport = null),
                  ready: _autoSaveChecked,
                );
        },
      ),
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
              color: const Color(0xff111111),
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
                        style: const TextStyle(color: Color(0xff9e9e9e)),
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
                        child: _AppBtn(
                          variant: _BtnVariant.ghost,
                          onPressed: game.dismissGameOutcome,
                          child: const Text('Continue Playing'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: _AppBtn(
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

// ── Splash screen plane ticker data ──────────────────────────────────────────
const _splashAmericanPlanes = <String>[
  'assets/planes/B707-320.png',
  'assets/planes/B727-200.png',
  'assets/planes/B737-800.png',
  'assets/planes/B737Max8.png',
  'assets/planes/B747-400.png',
  'assets/planes/B747-8i.png',
  'assets/planes/B757-200.png',
  'assets/planes/B767-300er.png',
  'assets/planes/B777-200er.png',
  'assets/planes/B787-9.png',
  'assets/planes/B777-9.png',
  'assets/planes/DC8-50.png',
  'assets/planes/DC9-30.png',
  'assets/planes/DC10-10.png',
  'assets/planes/MD80.png',
  'assets/planes/MD11.png',
  'assets/planes/l1011-1.png',
];

const _splashRussianPlanes = <String>[
  'assets/planes/Tu104.png',
  'assets/planes/Tu134.png',
  'assets/planes/Tu144.png',
  'assets/planes/Tu154.png',
  'assets/planes/Tu214.png',
  'assets/planes/IL62.png',
  'assets/planes/IL86.png',
  'assets/planes/IL96.png',
  'assets/planes/Yak40.png',
  'assets/planes/Yak42.png',
  'assets/planes/An24.png',
  'assets/planes/il14.png',
  'assets/planes/SSJ-100.png',
  'assets/planes/MC-21-300.png',
];

const _splashEuropeanPlanes = <String>[
  'assets/planes/Concorde.png',
  'assets/planes/A220-300.png',
  'assets/planes/A319neo.png',
  'assets/planes/A320neo.png',
  'assets/planes/A321xlr.png',
  'assets/planes/A330-900neo.png',
  'assets/planes/A340-600.png',
  'assets/planes/A350-900.png',
  'assets/planes/A380-800.png',
  'assets/planes/ATR72-600.png',
  'assets/planes/BAe146-200.png',
  'assets/planes/AvroRJ100.png',
  'assets/planes/Fokker100.png',
  'assets/planes/Saab340.png',
  'assets/planes/Caravelle.png',
  'assets/planes/Mercure.png',
];

class _SplashPlaneTicker extends StatefulWidget {
  const _SplashPlaneTicker({
    required this.planes,
    required this.direction,
    required this.duration,
  });
  final List<String> planes;
  /// -1 = scroll left, 1 = scroll right.
  final int direction;
  final Duration duration;

  @override
  State<_SplashPlaneTicker> createState() => _SplashPlaneTickerState();
}

class _SplashPlaneTickerState extends State<_SplashPlaneTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  static const _cardW = 160.0;
  static const _cardH = 90.0;
  static const _gap = 10.0;

  double get _singleW => widget.planes.length * (_cardW + _gap);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        height: _cardH,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            // Left: slides from 0 → -_singleW; right: -_singleW → 0
            final dx = widget.direction < 0
                ? -(t * _singleW)
                : -(1.0 - t) * _singleW;
            return OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: Transform.translate(
                offset: Offset(dx, 0),
                child: Row(
                  children: [
                    // Duplicate list so the loop is seamless
                    for (final path in [...widget.planes, ...widget.planes])
                      Padding(
                        padding: const EdgeInsets.only(right: _gap),
                        child: _SplashPlaneCard(path: path),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SplashPlaneCard extends StatelessWidget {
  const _SplashPlaneCard({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0x18ffffff),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x22ffffff)),
      ),
      padding: const EdgeInsets.all(10),
      child: Image.asset(
        path,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({
    required this.game,
    required this.currency,
    required this.onCurrency,
    required this.onGameStart,
    required this.ready,
  });

  final GameController game;
  final CurrencyOption currency;
  final ValueChanged<CurrencyOption> onCurrency;
  final VoidCallback onGameStart;
  /// False while the auto-save check is still in flight — hides buttons
  /// to prevent interaction before we know whether a save exists.
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Logo + title ────────────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Transform.scale(
              scale: 1.12,
              child: Image.asset(
                'assets/icon.png',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Mighty Airline Empire',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          // ── Plane tickers ───────────────────────────────────────────────
          const SizedBox(height: 44),
          const _SplashPlaneTicker(
            planes: _splashAmericanPlanes,
            direction: -1,
            duration: Duration(seconds: 28),
          ),
          const SizedBox(height: 10),
          const _SplashPlaneTicker(
            planes: _splashRussianPlanes,
            direction: 1,
            duration: Duration(seconds: 32),
          ),
          const SizedBox(height: 10),
          const _SplashPlaneTicker(
            planes: _splashEuropeanPlanes,
            direction: -1,
            duration: Duration(seconds: 25),
          ),
          if (ready) ...[
            const SizedBox(height: 32),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AppBtn(
                  variant: _BtnVariant.ghost,
                  onPressed: () =>
                      _showImportDialog(context, game, onCurrency),
                  icon: const Icon(Icons.download),
                  child: const Text('Import save'),
                ),
                const SizedBox(width: 12),
                _AppBtn(
                  onPressed: () => _showNewGameDialog(
                    context,
                    game,
                    currency,
                    onCurrency,
                    forceStart: true,
                    onGameStart: onGameStart,
                  ),
                  icon: const Icon(Icons.add),
                  child: const Text('Start new game'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.game,
    required this.compact,
    required this.showSearch,
    required this.currency,
    required this.selectedPanel,
    required this.onPanel,
    required this.onCurrency,
    required this.onSpeed,
    required this.onAirport,
    required this.onSearchToggle,
    required this.onGameStart,
    required this.onReset,
  });
  final GameController game;
  final bool compact;
  /// True when the inline search box should be shown in the nav centre.
  /// When false (intermediate width), a search icon is shown instead.
  final bool showSearch;
  final CurrencyOption currency;
  final _Panel? selectedPanel;
  final ValueChanged<_Panel> onPanel;
  final ValueChanged<CurrencyOption> onCurrency;
  final ValueChanged<int> onSpeed;
  final ValueChanged<Airport> onAirport;
  final VoidCallback onSearchToggle;
  final VoidCallback onGameStart;
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context) {
    final search = _SearchBox(onAirport: onAirport);
    final speedValue = game.speed == 0 ? 0 : game.speed;
    final nav = _PanelNav(
      selectedPanel: selectedPanel,
      onPanel: onPanel,
      compact: compact,
    );
    final dark = !_isLight(context);
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xf5121212) : const Color(0xf8ffffff),
        border: Border(bottom: BorderSide(color: _hairline(context))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: SizedBox(
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
                  onGameStart: onGameStart,
                  onReset: onReset,
                ),
                const SizedBox(width: 6),
                _DateBadge(game: game, compact: compact),
                const SizedBox(width: 6),
                _SpeedControl(
                  compact: compact,
                  speedValue: speedValue,
                  onSpeed: onSpeed,
                ),
                if (!compact)
                  IconButton(
                    tooltip: 'Advance day',
                    onPressed: game.runDailyTick,
                    icon: const Icon(Icons.skip_next),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (!compact && showSearch)
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: search,
                  ),
                ),
              )
            else if (!compact)
              // Intermediate width: inline search would be too small — show
              // an icon button that opens the floating search instead.
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: IconButton(
                    tooltip: 'Search airports',
                    icon: const Icon(Icons.search),
                    onPressed: onSearchToggle,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              )
            else
              const Spacer(),
            nav,
          ],
        ),
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
              ? Icons.menu
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
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _subtleSurface(context),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: _hairline(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(speedValue == 0 ? Icons.pause : Icons.speed, size: 17),
              if (speedValue != 0) ...[
                const SizedBox(width: 5),
                Text(
                  _speedLabel(speedValue),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final dark = !_isLight(context);
    final segments = <({int value, Widget label, String tooltip})>[
      (
        value: 0,
        label: const Icon(Icons.pause_rounded, size: 14),
        tooltip: 'Pause',
      ),
      ..._speedOptions.map(
        (o) => (
          value: o.value,
          label: Text(
            o.label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              height: 1,
            ),
          ),
          tooltip: o.label,
        ),
      ),
    ];

    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: segments.map((seg) {
          final selected = speedValue == seg.value;
          return _SpeedSegment(
            selected: selected,
            tooltip: seg.tooltip,
            onTap: () => onSpeed(seg.value),
            dark: dark,
            child: seg.label,
          );
        }).toList(),
      ),
    );
  }
}

class _SpeedSegment extends StatefulWidget {
  const _SpeedSegment({
    required this.selected,
    required this.tooltip,
    required this.onTap,
    required this.dark,
    required this.child,
  });

  final bool selected;
  final String tooltip;
  final VoidCallback onTap;
  final bool dark;
  final Widget child;

  @override
  State<_SpeedSegment> createState() => _SpeedSegmentState();
}

class _SpeedSegmentState extends State<_SpeedSegment> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.selected
        ? Colors.white
        : (widget.dark
              ? Colors.white.withValues(alpha: 0.55)
              : Colors.black.withValues(alpha: 0.45));

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minWidth: 28),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: widget.selected
                ? (_pressed
                      ? const Color(0xff006ed6)
                      : const Color(0xff0a84ff))
                : (_pressed
                      ? (widget.dark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.08))
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(100),
            boxShadow: widget.selected && !_pressed
                ? [
                    BoxShadow(
                      color: const Color(0xff0a84ff).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: IconTheme(
            data: IconThemeData(color: fg, size: 14),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: fg),
              child: widget.child,
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

class _AirlineBadge extends StatefulWidget {
  const _AirlineBadge({
    required this.game,
    required this.currency,
    required this.onCurrency,
    required this.compact,
    required this.onGameStart,
    required this.onReset,
  });
  final GameController game;
  final CurrencyOption currency;
  final ValueChanged<CurrencyOption> onCurrency;
  final bool compact;
  final VoidCallback onGameStart;
  final VoidCallback onReset;

  @override
  State<_AirlineBadge> createState() => _AirlineBadgeState();
}

class _AirlineBadgeState extends State<_AirlineBadge>
    with SingleTickerProviderStateMixin {
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;
  bool _isOpen = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _removeOverlay();
    _animCtrl.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  Future<void> _closeMenu() async {
    if (!_isOpen) return;
    await _animCtrl.reverse();
    _removeOverlay();
    if (mounted) setState(() => _isOpen = false);
  }

  void _openMenu() {
    if (_isOpen) return;
    setState(() => _isOpen = true);
    _overlay = OverlayEntry(builder: (ctx) {
      // Capture stable context for dialogs before overlay is built
      final stableCtx = context;
      return Stack(
        children: [
          // Invisible full-screen tap-to-dismiss layer
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
            ),
          ),
          // Animated dropdown positioned below the badge
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 8),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: _AirlineProfileDropdown(
                  game: widget.game,
                  currency: widget.currency,
                  onCurrency: widget.onCurrency,
                  onGameStart: widget.onGameStart,
                  onReset: widget.onReset,
                  stableContext: stableCtx,
                  onClose: _closeMenu,
                ),
              ),
            ),
          ),
        ],
      );
    });
    Overlay.of(context).insert(_overlay!);
    _animCtrl.forward(from: 0);
  }

  void _toggleMenu() => _isOpen ? _closeMenu() : _openMenu();

  @override
  Widget build(BuildContext context) {
    final muted = _mutedText(context);
    return CompositedTransformTarget(
      link: _link,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: _toggleMenu,
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
              _AirlineLogo(logo: widget.game.player.logoEmoji, size: 28),
              const SizedBox(width: 8),
              if (widget.compact)
                Text(
                  money(widget.game.player.cashUSD, widget.currency),
                  style: TextStyle(
                    color: widget.game.player.cashUSD >= 0
                        ? const Color(0xff25c96b)
                        : const Color(0xffff6b6b),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              if (!widget.compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.game.player.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      money(widget.game.player.cashUSD, widget.currency),
                      style: TextStyle(
                        color: widget.game.player.cashUSD >= 0
                            ? const Color(0xff25c96b)
                            : const Color(0xffff6b6b),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: Icon(Icons.expand_more, size: 18, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline currency selector — expands/collapses inside the profile panel.
/// Avoids PopupMenuButton's overlay, which appeared behind the profile panel.
class _CurrencyPickerCard extends StatefulWidget {
  const _CurrencyPickerCard({
    required this.currency,
    required this.onCurrency,
  });

  final CurrencyOption currency;
  final ValueChanged<CurrencyOption> onCurrency;

  @override
  State<_CurrencyPickerCard> createState() => _CurrencyPickerCardState();
}

class _CurrencyPickerCardState extends State<_CurrencyPickerCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header row (always visible) ─────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Display currency',
                          style: TextStyle(
                            fontSize: 12,
                            color: _mutedText(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.currency.code} · ${widget.currency.symbol}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _open ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    color: _mutedText(context),
                  ),
                ],
              ),
            ),
          ),
          // ── Option list (visible when open) ─────────────────────────────
          if (_open) ...[
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 4),
            ...currencyOptions.map((opt) {
              final selected = opt.code == widget.currency.code;
              return InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  widget.onCurrency(opt);
                  setState(() => _open = false);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 4,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        child: selected
                            ? Icon(
                                Icons.check,
                                size: 15,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${opt.code} · ${opt.symbol}',
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _AirlineProfileDropdown extends StatelessWidget {
  const _AirlineProfileDropdown({
    required this.game,
    required this.currency,
    required this.onCurrency,
    required this.onGameStart,
    required this.onReset,
    required this.stableContext,
    required this.onClose,
  });

  final GameController game;
  final CurrencyOption currency;
  final ValueChanged<CurrencyOption> onCurrency;
  final VoidCallback onGameStart;
  final VoidCallback onReset;
  // Context from _AirlineBadge — lives in the main tree, not the menu overlay,
  // so it stays mounted after closeMenu() removes the dropdown from the overlay.
  final BuildContext stableContext;
  final VoidCallback onClose;

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
    void closeMenu() => onClose();

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
          // Column with pinned header + scrollable body + pinned footer.
          // Flexible on the scroll area lets the panel shrink on large screens
          // while still scrolling when the content overflows on small ones.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Pinned header ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 0),
                child: Row(
                  children: [
                    _AirlineLogo(logo: player.logoEmoji, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            player.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'IATA: ${player.iataPrefix} · Founded ${game.settings.startingYear + player.foundedGameDay ~/ 365}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xff9e9e9e),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: game.themeMode == ThemeModeSetting.dark
                          ? 'Switch to light mode'
                          : 'Switch to dark mode',
                      icon: Icon(
                        game.themeMode == ThemeModeSetting.dark
                            ? Icons.light_mode
                            : Icons.dark_mode,
                      ),
                      onPressed: () => game.setThemeMode(
                        game.themeMode == ThemeModeSetting.dark
                            ? ThemeModeSetting.light
                            : ThemeModeSetting.dark,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 16, color: _hairline(context)),
              // ── Scrollable body ───────────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
                              _InfoRow('In maintenance', maintenanceAircraft.toString()),
                            _InfoRow('Routes', '${routes.length} total'),
                            _InfoRow('Active routes', activeRoutes.toString()),
                            if (inactiveRoutes > 0)
                              _InfoRow('Inactive routes', inactiveRoutes.toString()),
                            _InfoRow(
                              'Hubs',
                              player.hubIatas.isEmpty ? 'None' : player.hubIatas.join(', '),
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
                      _CurrencyPickerCard(
                        currency: currency,
                        onCurrency: onCurrency,
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
              // ── Pinned footer ─────────────────────────────────────────
              Divider(height: 1, color: _hairline(context)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Primary actions
                    Row(
                      children: [
                        Expanded(
                          child: _AppBtn(
                            variant: _BtnVariant.ghost,
                            onPressed: () {
                              closeMenu();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (stableContext.mounted)
                                  _showRebrandDialog(stableContext, game, currency);
                              });
                            },
                            icon: const Icon(Icons.edit),
                            child: const Text('Rebrand'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AppBtn(
                            variant: _BtnVariant.ghost,
                            onPressed: () {
                              closeMenu();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (stableContext.mounted)
                                  _showPRCampaignDialog(stableContext, game, currency);
                              });
                            },
                            icon: const Icon(Icons.campaign),
                            child: const Text('PR Campaign'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Secondary actions
                    Row(
                      children: [
                        Expanded(
                          child: _AppBtn(
                            variant: _BtnVariant.ghost,
                            onPressed: () {
                              closeMenu();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (stableContext.mounted)
                                  _showExportDialog(stableContext, game);
                              });
                            },
                            icon: const Icon(Icons.upload_file),
                            child: const Text('Export'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AppBtn(
                            variant: _BtnVariant.ghost,
                            onPressed: () {
                              closeMenu();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!stableContext.mounted) return;
                                if (game.gameDay > 0) {
                                  showDialog<bool>(
                                    context: stableContext,
                                    builder: (ctx) => _GlassDialog(
                                      maxWidth: 420,
                                      title: const Text('Abandon current game?'),
                                      content: const Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Text(
                                          'Your current progress will be lost and cannot be recovered.',
                                        ),
                                      ),
                                      actions: [
                                        _AppBtn(
                                          variant: _BtnVariant.plain,
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        _AppBtn(
                                          variant: _BtnVariant.danger,
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('Abandon & restart'),
                                        ),
                                      ],
                                    ),
                                  ).then((confirmed) {
                                    if (confirmed == true &&
                                        stableContext.mounted) {
                                      onReset();
                                    }
                                  });
                                } else {
                                  onReset();
                                }
                              });
                            },
                            icon: const Icon(Icons.restart_alt),
                            child: const Text('Start again'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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
      _AppBtn(
        variant: _BtnVariant.ghost,
        onPressed: onUploadLogo,
        icon: const Icon(Icons.upload_file),
        child: const Text('Upload logo'),
      ),
      const SizedBox(height: 8),
      Text(
        _isImageLogo(value)
            ? 'Custom image logo detected from imported save.'
            : 'Pick an emoji, type a short mark, or paste a data:image logo.',
        style: const TextStyle(color: Color(0xff9e9e9e), fontSize: 12),
      ),
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

void _showPRCampaignDialog(
  BuildContext context,
  GameController game,
  CurrencyOption currency,
) {
  const tiers = [
    (
      name: 'Targeted',
      description:
          'Regional media blitz across key markets — digital ads, social push, airport out-of-home, and influencer partnerships.',
      cost: 25000000.0,
      repGain: 8.0,
    ),
    (
      name: 'National',
      description:
          'Primetime TV spots, major airport takeovers, celebrity endorsements, and a sustained press campaign across all national outlets.',
      cost: 75000000.0,
      repGain: 15.0,
    ),
    (
      name: 'Global',
      description:
          'Full international media blitz — flagship sponsorships, Super Bowl–scale buys, stadium naming rights, and a global brand awareness push.',
      cost: 200000000.0,
      repGain: 25.0,
    ),
  ];

  showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final rep = game.player.reputationScore;
        final cash = game.player.cashUSD;
        final atMax = rep >= 100;

        return _GlassDialog(
          title: const Text('PR Campaign'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      atMax
                          ? 'Your reputation is already at its maximum.'
                          : 'Choose the scale of your campaign. Reputation is currently ${rep.toStringAsFixed(0)}/100.',
                      style: const TextStyle(fontSize: 13, color: Color(0xff9e9e9e)),
                    ),
                  ),
                  for (final tier in tiers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    tier.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Text(
                                  money(tier.cost, currency),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                tier.description,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xff9e9e9e),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '+${tier.repGain.toStringAsFixed(0)} reputation',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xff4ade80),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                _AppBtn(
                                  small: true,
                                  variant: _BtnVariant.tonal,
                                  onPressed: atMax || cash < tier.cost
                                      ? null
                                      : () {
                                          final ok = game.launchPRCampaign(
                                            cost: tier.cost,
                                            reputationGain: tier.repGain,
                                          );
                                          if (!ok) return;
                                          Navigator.pop(context);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '${tier.name} PR campaign launched! +${tier.repGain.toStringAsFixed(0)} reputation',
                                              ),
                                              duration: const Duration(seconds: 3),
                                            ),
                                          );
                                        },
                                  child: const Text('Launch'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            _AppBtn(
              variant: _BtnVariant.plain,
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );
}

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
        final nameChanged =
            name.isNotEmpty && name != game.player.name;
        final colorChanged = colour != game.player.color;
        final logoChanged =
            logo.isNotEmpty && logo != game.player.logoEmoji;
        final value = game.playerCompanyValue();
        final nameCost = nameChanged && colorChanged
            ? 0.0
            : nameChanged
            ? math.max(1000000, value * 0.04)
            : 0.0;
        final colorCost = colorChanged && !nameChanged
            ? math.max(250000, value * 0.015)
            : colorChanged && nameChanged
            ? math.max(1200000, value * 0.05)
            : 0.0;
        final logoCost =
            logoChanged ? math.max(500000, value * 0.02) : 0.0;
        final cost = game.rebrandCost(
          name: name,
          color: colour,
          logoEmoji: logo,
        );
        final hasChange = cost > 0;
        return _GlassDialog(
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
                                  color: Color(0xff9e9e9e),
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
                    ),
                    onChanged: (_) => setState(() => error = null),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: logoController,
                    decoration: const InputDecoration(
                      labelText: 'Logo emoji, short mark, or data:image',
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
                    children: [
                      ..._brandColours.map(
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
                                      : const Color(0xff383838),
                                  width: colour == candidate ? 3 : 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _RainbowCircleButton(
                        currentColor: _MapPainter._colorFromHex(colour),
                        onColorSelected: (c) => setState(() => colour = _colorToHex(c)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (hasChange) ...[
                    if (nameChanged && colorChanged)
                      _InfoRow(
                        'Name + colour change',
                        money(colorCost, currency),
                      )
                    else ...[
                      if (nameChanged)
                        _InfoRow('Name change', money(nameCost, currency)),
                      if (colorChanged)
                        _InfoRow('Colour change', money(colorCost, currency)),
                    ],
                    if (logoChanged)
                      _InfoRow('Logo change', money(logoCost, currency)),
                    const Divider(),
                  ],
                  Text(
                    hasChange ? 'Total: ${money(cost, currency)}' : 'No changes',
                    style: TextStyle(
                      color: hasChange
                          ? const Color(0xffffd166)
                          : const Color(0xff9e9e9e),
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
            _AppBtn(
              variant: _BtnVariant.plain,
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            _AppBtn(
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
  bool cancellable = false,
  VoidCallback? onGameStart,
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
  var aiCount = game.settings.aiCount.clamp(0, 25).toInt();
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
  var activeSection = 0;

  showDialog<void>(
    context: context,
    barrierDismissible: cancellable,
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
        final dark = Theme.of(context).brightness == Brightness.dark;

        return PopScope(
          canPop: cancellable,
          child: _GlassDialog(
            maxWidth: 920,
            onClose: cancellable ? () => Navigator.pop(context) : null,
            title: const Text('Start new airline'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Section 1: Your airline ──────────────────────────
                  _NewGameSection(
                    index: 0,
                    activeSection: activeSection,
                    title: 'Your airline',
                    collapsedSummary: _SectionSummary(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _MapPainter._colorFromHex(
                              colorController.text.isEmpty
                                  ? '#3b82f6'
                                  : colorController.text,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(nameController.text.trim().isEmpty
                            ? 'My Airline'
                            : nameController.text.trim()),
                        const SizedBox(width: 6),
                        Text(emojiController.text.trim().isEmpty
                            ? '✈️'
                            : emojiController.text.trim()),
                      ],
                    ),
                    onTap: () => setState(() => activeSection = 0),
                    onContinue: () => setState(() => activeSection = 1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Airline name',
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
                          children: [
                            ..._airlineColorOptions.map(
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
                                      color: selectedColor ==
                                              color.toLowerCase()
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : _hairline(context),
                                      width: selectedColor ==
                                              color.toLowerCase()
                                          ? 3
                                          : 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _RainbowCircleButton(
                              size: 34,
                              currentColor: _MapPainter._colorFromHex(colorController.text),
                              onColorSelected: (c) {
                                colorController.text = _colorToHex(c);
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: colorController,
                          decoration: const InputDecoration(
                            labelText: 'Custom colour',
                            hintText: '#3b82f6',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Logo',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
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
                              style: const TextStyle(
                                color: Color(0xffff6b6b),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ── Section 2: Operations ────────────────────────────
                  _NewGameSection(
                    index: 1,
                    activeSection: activeSection,
                    title: 'Operations',
                    collapsedSummary: _SectionSummary(
                      children: [
                        Text('${startingHub.iata} · $startingYear · ${selectedCurrency.code}'),
                      ],
                    ),
                    onTap: () => setState(() => activeSection = 1),
                    onContinue: () => setState(() => activeSection = 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            spacing: 8,
                            children: _newGameEras.map((option) {
                              final selected = startingYear == option.year;
                              return GestureDetector(
                                onTap: () => setState(
                                  () => startingYear = option.year,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 130),
                                  curve: Curves.easeOut,
                                  width: 108,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xff0a84ff)
                                        : (dark
                                            ? Colors.white.withValues(
                                                alpha: 0.08,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.05,
                                              )),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected
                                          ? Colors.transparent
                                          : (dark
                                              ? Colors.white.withValues(
                                                  alpha: 0.10,
                                                )
                                              : Colors.black.withValues(
                                                  alpha: 0.08,
                                                )),
                                    ),
                                    boxShadow: selected
                                        ? [
                                            BoxShadow(
                                              color: const Color(
                                                0xff0a84ff,
                                              ).withValues(alpha: 0.35),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        option.year.toString(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: selected
                                              ? Colors.white
                                              : (dark
                                                  ? Colors.white
                                                  : Colors.black87),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        option.label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: selected
                                              ? Colors.white.withValues(
                                                  alpha: 0.85,
                                                )
                                              : (dark
                                                  ? Colors.white.withValues(
                                                      alpha: 0.50,
                                                    )
                                                  : Colors.black.withValues(
                                                      alpha: 0.45,
                                                    )),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$availableAircraft aircraft available · ${era.flagship}',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: _mutedText(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Currency',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: currencyOptions.map((opt) {
                            final isSelected =
                                opt.code == selectedCurrency.code;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => selectedCurrency = opt),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 130),
                                curve: Curves.easeOut,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xff0a84ff)
                                      : (dark
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : Colors.black.withValues(
                                              alpha: 0.05,
                                            )),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.transparent
                                        : (dark
                                            ? Colors.white.withValues(
                                                alpha: 0.10,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.08,
                                              )),
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: const Color(
                                              0xff0a84ff,
                                            ).withValues(alpha: 0.35),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Text(
                                  '${opt.symbol} ${opt.code}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.white
                                        : (dark
                                            ? Colors.white
                                            : Colors.black87),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                  // ── Section 3: Game settings ─────────────────────────
                  _NewGameSection(
                    index: 2,
                    activeSection: activeSection,
                    title: 'Game settings',
                    collapsedSummary: _SectionSummary(
                      children: [
                        Text('$aiCount AI · ${difficulty.name}'),
                      ],
                    ),
                    onTap: () => setState(() => activeSection = 2),
                    onContinue: null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI airlines: $aiCount'),
                        Slider(
                          value: aiCount.toDouble(),
                          min: 0,
                          max: 25,
                          divisions: 16,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Target market share: ${targetMarketShare.round()}%',
                                      ),
                                      Slider(
                                        value: targetMarketShare.toDouble(),
                                        min: 60,
                                        max: 100,
                                        divisions: 40,
                                        label:
                                            '${targetMarketShare.round()}%',
                                        onChanged: (value) => setState(
                                          () => targetMarketShare =
                                              value.roundToDouble(),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<Difficulty>(
                          initialValue: difficulty,
                          decoration: const InputDecoration(
                            labelText: 'Difficulty',
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
                            if (value != null) {
                              setState(() => difficulty = value);
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
                ],
              ),
            ),
            actions: [
              if (cancellable)
                _AppBtn(
                  variant: _BtnVariant.plain,
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              _AppBtn(
                onPressed: activeSection < 2 ? null : () {
                  final name = nameController.text.trim();
                  final emoji = emojiController.text.trim();
                  GameController.clearAutoSave();
                  game.startNewGame(
                    game.settings.copyWith(
                      playerAirlineName: name.isEmpty ? 'My Airline' : name,
                      playerAirlineColor:
                          _normaliseHexColor(colorController.text) ??
                          '#3b82f6',
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
                  onGameStart?.call();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.flight_takeoff),
                child: const Text('Start'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _NewGameSection extends StatelessWidget {
  const _NewGameSection({
    required this.index,
    required this.activeSection,
    required this.title,
    required this.collapsedSummary,
    required this.onTap,
    required this.child,
    this.onContinue,
  });

  final int index;
  final int activeSection;
  final String title;
  final Widget collapsedSummary;
  final VoidCallback onTap;
  final VoidCallback? onContinue;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isOpen = activeSection == index;
    final isDone = activeSection > index;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = _mutedText(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: isOpen
                        ? const Color(0xff0a84ff)
                        : isDone
                            ? const Color(0xff0a84ff).withValues(alpha: 0.15)
                            : (dark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06)),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isDone
                        ? const Icon(
                            Icons.check_rounded,
                            size: 13,
                            color: Color(0xff0a84ff),
                          )
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isOpen ? Colors.white : muted,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: isOpen ? null : (isDone ? null : muted),
                        ),
                      ),
                      if (!isOpen)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: collapsedSummary,
                        ),
                    ],
                  ),
                ),
                Icon(
                  isOpen
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: muted,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: isOpen
              ? Padding(
                  padding: const EdgeInsets.only(left: 38, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      child,
                      if (onContinue != null) ...[
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _AppBtn(
                            small: true,
                            onPressed: onContinue,
                            child: const Text('Next'),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (index < 2)
          Divider(
            height: 1,
            color: dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.07),
          ),
      ],
    );
  }
}

class _SectionSummary extends StatelessWidget {
  const _SectionSummary({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: children
          .map(
            (child) => DefaultTextStyle.merge(
              style: TextStyle(fontSize: 12, color: _mutedText(context)),
              child: child,
            ),
          )
          .toList(),
    );
  }
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

String _colorToHex(Color color) {
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
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
  mimeTypes: ['application/json', 'text/plain'],
  uniformTypeIdentifiers: ['public.json', 'public.text'],
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

Future<void> _shareProgressFile(
  BuildContext context,
  GameController game,
) async {
  final fileName =
      '${_fileSafeName(game.player.name)}-day-${game.gameDay}-progress.json';
  final bytes = Uint8List.fromList(utf8.encode(game.exportProgressJson()));
  final file = XFile.fromData(
    bytes,
    mimeType: 'application/json',
    name: fileName,
  );
  final box = context.findRenderObject() as RenderBox?;
  await Share.shareXFiles(
    [file],
    subject: fileName,
    sharePositionOrigin: box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size,
  );
}

Future<String?> _openProgressFile() async {
  try {
    final file = await openFile(acceptedTypeGroups: const [_jsonTypeGroup]);
    if (file == null) return null;
    return await file.readAsString();
  } on PlatformException {
    rethrow;
  } catch (_) {
    rethrow;
  }
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
      builder: (dialogContext, setState) => _GlassDialog(
        maxWidth: 660,
        title: const Text('Export progress'),
        content: SizedBox(
          width: 620,
          child: TextField(
            controller: controller,
            readOnly: true,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(),
          ),
        ),
        actions: [
          _AppBtn(
            variant: _BtnVariant.plain,
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          _AppBtn(
            variant: _BtnVariant.ghost,
            onPressed: saving
                ? null
                : () async {
                    setState(() => saving = true);
                    try {
                      if (Platform.isIOS || Platform.isAndroid) {
                        await _shareProgressFile(context, game);
                      } else {
                        await _saveProgressFile(context, game);
                      }
                    } finally {
                      if (dialogContext.mounted) {
                        setState(() => saving = false);
                      }
                    }
                  },
            icon: Icon(
              (Platform.isIOS || Platform.isAndroid)
                  ? Icons.ios_share
                  : Icons.save_alt,
            ),
            child: Text(saving ? 'Saving...' : 'Save file'),
          ),
          _AppBtn(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Progress JSON copied')),
              );
            },
            icon: const Icon(Icons.copy),
            child: const Text('Copy'),
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
      builder: (dialogContext, setState) => _GlassDialog(
        maxWidth: 660,
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
          _AppBtn(
            variant: _BtnVariant.plain,
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          _AppBtn(
            variant: _BtnVariant.ghost,
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
            child: Text(openingFile ? 'Opening...' : 'Open file'),
          ),
          _AppBtn(
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
    final dark = !_isLight(context);
    final textColor = dark ? Colors.white : const Color(0xff1c1c1e);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xcc141414) : const Color(0xddffffff),
        border: Border.all(color: _hairline(context)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: game.mapAnimationTick,
        builder: (context, _, _) {
          final date = DateTime(
            game.settings.startingYear,
            1,
            1,
          ).add(Duration(days: game.gameDay));
          final dayMs = game.gameTimeMs % gameDayMs;
          final hour = (dayMs ~/ 3600000).toString().padLeft(2, '0');
          final minute = ((dayMs % 3600000) ~/ 60000).toString().padLeft(2, '0');
          final day = date.day.toString().padLeft(2, '0');
          final label = compact
              ? '${_monthLabel(date.month)} $day · $hour:$minute'
              : '${_monthLabel(date.month)} $day, ${date.year} · $hour:$minute';
          return Text(
            label,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: textColor,
            ),
          );
        },
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
        prefixIcon: const Icon(Icons.search, size: 18),
        isDense: true,
      ),
    ),
    optionsViewBuilder: (context, onSelected, options) {
      final dark = !_isLight(context);
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Material(
            color: dark ? const Color(0xf2161616) : const Color(0xf5f5f5f5),
            borderRadius: BorderRadius.circular(18),
            elevation: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.07),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.5 : 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 340,
                    maxHeight: 300,
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final a = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        title: Text(
                          '${a.iata} · ${a.city}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        subtitle: Text(
                          '${a.name}, ${a.country}',
                          style: TextStyle(
                            fontSize: 12,
                            color: _mutedText(context),
                          ),
                        ),
                        onTap: () => onSelected(a),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _FloatingSearchRow extends StatelessWidget {
  const _FloatingSearchRow({
    required this.searchOpen,
    required this.onToggle,
    required this.onAirport,
  });
  final bool searchOpen;
  final VoidCallback onToggle;
  final ValueChanged<Airport> onAirport;

  @override
  Widget build(BuildContext context) {
    final dark = !_isLight(context);
    final decoration = BoxDecoration(
      shape: BoxShape.circle,
      color: dark ? const Color(0xf0121212) : const Color(0xf2ffffff),
      border: Border.all(
        color: dark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.07),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.4 : 0.1),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DecoratedBox(
          decoration: decoration,
          child: InkWell(
            borderRadius: BorderRadius.circular(100),
            onTap: onToggle,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                searchOpen ? Icons.close : Icons.search,
                size: 18,
              ),
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          width: searchOpen ? 252 : 0,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: SizedBox(
              width: 244,
              child: Theme(
                data: Theme.of(context).copyWith(
                  inputDecorationTheme:
                      Theme.of(context).inputDecorationTheme.copyWith(
                        fillColor: dark
                            ? const Color(0xf0121212)
                            : const Color(0xf2ffffff),
                      ),
                ),
                child: _SearchBox(onAirport: onAirport),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapToggle extends StatelessWidget {
  const _MapToggle({required this.showAi, required this.onChanged});
  final bool showAi;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final dark = !_isLight(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xf0121212) : const Color(0xf2ffffff),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.4 : 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 2, top: 0, bottom: 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Show AI on map',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: -0.2,
                color: dark ? Colors.white70 : const Color(0xff3c3c43),
              ),
            ),
            Transform.scale(
              scale: 0.72,
              child: Switch(value: showAi, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
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
  var _gameHasStarted = false;
  List<RoutePlan> _cachedDrawableRoutes = const [];

  // ── Map camera-aware culling ────────────────────────────────────────────
  // Tracking the camera lets us draw only the airports actually visible at
  // the current zoom + viewport. Previously the layer rendered all ~4,125
  // airports (×2 markers, visual + hit-target) every rebuild, which made
  // panning at low zoom chug to a few FPS.
  final ValueNotifier<int> _mapCameraVersion = ValueNotifier<int>(0);
  StreamSubscription<MapEvent>? _mapEventsSub;
  double _currentZoom = 2.05;
  int _currentZoomBucket = 0; // 0: <3, 1: <5, 2: ≥5
  LatLngBounds? _currentBounds;
  // Pre-built sets — recomputed on `airportStateVersion` /
  // `routesStructureVersion` changes — let `_airportMeta` skip its
  // per-airport `competitors.any(...)` scan.
  Set<String> _hubIatas = const <String>{};
  Set<String> _routeEndpointIatas = const <String>{};

  @override
  void initState() {
    super.initState();
    widget.game.routesStructureVersion.addListener(_refreshRouteCache);
    widget.game.airportStateVersion.addListener(_rebuildHubIatas);
    _rebuildHubIatas();
    _refreshRouteCache();
  }

  void _refreshRouteCache() {
    _cachedDrawableRoutes = widget.game.routes.values.where((r) {
      if (!r.isActive || r.aircraftId == null) return false;
      // Skip routes whose owning airline no longer exists (dissolved / orphaned).
      if (widget.game.airlines[r.airlineId] == null) return false;
      if (widget.showAiOnMap) return true;
      return widget.game.airlines[r.airlineId]?.isPlayer == true;
    }).toList(growable: false);
    final endpoints = <String>{};
    for (final r in _cachedDrawableRoutes) {
      endpoints.add(r.originIata);
      endpoints.add(r.destinationIata);
    }
    _routeEndpointIatas = endpoints;
  }

  void _rebuildHubIatas() {
    final hubs = <String>{...widget.game.player.hubIatas};
    for (final airline in widget.game.competitors) {
      hubs.addAll(airline.hubIatas);
    }
    _hubIatas = hubs;
  }

  int _zoomBucket(double z) => z < 3.0 ? 0 : z < 5.0 ? 1 : 2;

  void _onMapEvent(MapEvent event) {
    final camera = event.camera;
    _currentZoom = camera.zoom;
    _currentBounds = camera.visibleBounds;
    final bucket = _zoomBucket(camera.zoom);
    // Bump on zoom-bucket change immediately (visible airport set + route
    // detail level change); on pan/zoom *end* we also bump so the new
    // viewport's airports get re-filtered. Continuous-pan events
    // intentionally do NOT bump — we keep the previously-culled marker set
    // visible while panning to avoid per-frame rebuild churn.
    final isEndEvent =
        event is MapEventMoveEnd ||
        event is MapEventDoubleTapZoomEnd ||
        event is MapEventFlingAnimationEnd ||
        event is MapEventScrollWheelZoom;
    if (bucket != _currentZoomBucket || isEndEvent) {
      _currentZoomBucket = bucket;
      _mapCameraVersion.value += 1;
    }
  }

  @override
  void didUpdateWidget(covariant _WorldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedAirport?.iata != widget.selectedAirport?.iata) {
      _focusSelectedAirport();
    }
    final nowStarted = widget.game.hasStarted;
    if (!_gameHasStarted && nowStarted) {
      _gameHasStarted = true;
      _focusHub();
    } else if (_gameHasStarted && !nowStarted) {
      _gameHasStarted = false;
    }
    if (oldWidget.showAiOnMap != widget.showAiOnMap ||
        oldWidget.game != widget.game) {
      if (oldWidget.game != widget.game) {
        oldWidget.game.routesStructureVersion.removeListener(_refreshRouteCache);
        widget.game.routesStructureVersion.addListener(_refreshRouteCache);
      }
      _refreshRouteCache();
    }
  }

  @override
  void dispose() {
    widget.game.routesStructureVersion.removeListener(_refreshRouteCache);
    widget.game.airportStateVersion.removeListener(_rebuildHubIatas);
    _mapEventsSub?.cancel();
    _mapCameraVersion.dispose();
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

  void _focusHub() {
    final hubIata = widget.game.settings.startingHubIata;
    final hub = airportsByIata[hubIata];
    if (hub == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(LatLng(hub.lat, hub.lon), 5.5);
    });
  }

  void _handleMapReady() {
    _mapReady = true;
    _currentZoom = _mapController.camera.zoom;
    _currentZoomBucket = _zoomBucket(_currentZoom);
    _currentBounds = _mapController.camera.visibleBounds;
    _mapEventsSub = _mapController.mapEventStream.listen(_onMapEvent);
    // Force a first cull pass now that we have real bounds.
    _mapCameraVersion.value += 1;
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
              : const Color(0xff0d0d0d),
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
          // 1. Airport dots — visual only, below route lines
          IgnorePointer(
            child: RepaintBoundary(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  widget.game.airportStateVersion,
                  _mapCameraVersion,
                ]),
                builder: (context, _) =>
                    MarkerLayer(markers: _airportVisualMarkers()),
              ),
            ),
          ),
          // 2. Route lines — drawn above airport dots
          MouseRegion(
            hitTestBehavior: HitTestBehavior.deferToChild,
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onTap: () {
                final route = _routeHitNotifier.value?.hitValues.lastOrNull;
                if (route != null) widget.onRouteSelected(route);
              },
              child: RepaintBoundary(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    widget.game.routesStructureVersion,
                    _mapCameraVersion,
                  ]),
                  builder: (context, _) => PolylineLayer<RoutePlan>(
                    hitNotifier: _routeHitNotifier,
                    minimumHitbox: 28,
                    drawInSingleWorld: true,
                    // Disable simplification — arc curvature is already
                    // preserved by controlling pointCount per zoom bucket
                    // below; Douglas-Peucker on sparse points flattens arcs.
                    simplificationTolerance: 0,
                    polylines: _routePolylines(_cachedDrawableRoutes),
                  ),
                ),
              ),
            ),
          ),
          // 3. Invisible airport hit-targets — above route lines so taps
          //    always reach the airport even where routes overlap the dot
          RepaintBoundary(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                widget.game.airportStateVersion,
                _mapCameraVersion,
              ]),
              builder: (context, _) =>
                  MarkerLayer(markers: _airportHitMarkers()),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: widget.game.mapAnimationTick,
            builder: (context, _, _) => _PlaneCanvasLayer(
              routes: _cachedDrawableRoutes,
              game: widget.game,
              mapController: _mapController,
            ),
          ),
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

  List<Polyline<RoutePlan>> _routePolylines(List<RoutePlan> drawableRoutes) {
    // Lower zoom → fewer interpolation points, but keep enough to preserve
    // the great-circle arc's visible curvature. 6 points was too few —
    // with no simplification the arc needs ≥12 to look curved at world zoom.
    final arcPoints = _currentZoomBucket == 0
        ? 12
        : _currentZoomBucket == 1
        ? 14
        : 18;
    final lines = <Polyline<RoutePlan>>[];
    for (final route in drawableRoutes) {
      final origin = airportsByIata[route.originIata];
      final dest = airportsByIata[route.destinationIata];
      if (origin == null || dest == null) continue;
      final airline = widget.game.airlines[route.airlineId];
      final isPlayer = airline?.isPlayer == true;
      final color = _colorFromHex(airline?.color ?? '#2f8cff');
      for (final segment in _routeArcLatLngSegments(
        origin,
        dest,
        pointCount: arcPoints,
      )) {
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

  // ── Airport visibility filter ──────────────────────────────────────────
  // At low zoom we draw only major airports plus everything important
  // (hubs and route endpoints). At medium zoom we additionally include
  // large airports. At high zoom we include everything but cull to a
  // padded version of the current viewport so off-screen markers don't
  // get re-projected per pan frame.
  bool _airportIsImportant(Airport a) =>
      a.size == AirportSize.major ||
      _hubIatas.contains(a.iata) ||
      _routeEndpointIatas.contains(a.iata);

  Iterable<Airport> _visibleAirports() {
    final bucket = _currentZoomBucket;
    final bounds = _currentBounds;
    if (bucket == 0) {
      // <3: only the most important markers, regardless of viewport — the
      // user just zoomed out to see the world, they shouldn't see every
      // small airfield in the visible region.
      return airports.where(_airportIsImportant);
    }
    if (bucket == 1) {
      // <5: importance + large airports, no viewport filter.
      return airports.where(
        (a) => _airportIsImportant(a) || a.size == AirportSize.large,
      );
    }
    // ≥5: everything, but bounds-cull so off-screen markers don't cost
    // anything. Pad the bounds 50 % so light panning stays inside the
    // culled set.
    if (bounds == null) return airports;
    final padLat = (bounds.north - bounds.south).abs() * 0.5;
    final padLon = (bounds.east - bounds.west).abs() * 0.5;
    final minLat = bounds.south - padLat;
    final maxLat = bounds.north + padLat;
    final minLon = bounds.west - padLon;
    final maxLon = bounds.east + padLon;
    return airports.where(
      (a) =>
          a.lat >= minLat &&
          a.lat <= maxLat &&
          a.lon >= minLon &&
          a.lon <= maxLon,
    );
  }

  // ── Shared airport metadata ────────────────────────────────────────────────
  ({Color color, double dotSize, Airport airport}) _airportMeta(Airport a) {
    final airport = widget.game.airportByIata(a.iata) ?? a;
    final closedUntil = airport.closedUntilGameDay;
    final isClosed =
        closedUntil != null && closedUntil >= widget.game.gameDay;
    final selected = widget.selectedAirport?.iata == a.iata;
    final playerHub = widget.game.player.hubIatas.contains(a.iata);
    // Use pre-built `_hubIatas` set rather than scanning all competitors
    // per airport. `_hubIatas` already includes the player so we infer
    // AI-hub status by subtraction.
    final aiHub = !playerHub && _hubIatas.contains(a.iata);
    final radius = switch (a.size) {
      AirportSize.small => 2.2,
      AirportSize.medium => 3.0,
      AirportSize.large => 4.0,
      AirportSize.major => 5.3,
    };
    final playerColor = _MapPainter._colorFromHex(widget.game.player.color);
    final color = selected
        ? const Color(0xffffd166)
        : isClosed
        ? const Color(0xffff6b6b)
        : playerHub
        ? playerColor
        : aiHub
        ? const Color(0xff2dd4bf)
        : const Color(0xff58a6ff);
    return (
      color: color,
      dotSize: selected ? radius * 2 + 8 : radius * 2,
      airport: airport,
    );
  }

  // Visual-only dots — rendered BELOW route lines, not interactive.
  List<Marker> _airportVisualMarkers() {
    final markers = <Marker>[];
    for (final a in _visibleAirports()) {
      final meta = _airportMeta(a);
      final airport = widget.game.airportByIata(a.iata) ?? a;
      final closedUntil = airport.closedUntilGameDay;
      final isClosed =
          closedUntil != null && closedUntil >= widget.game.gameDay;
      final selected = widget.selectedAirport?.iata == a.iata;
      final playerHub = widget.game.player.hubIatas.contains(a.iata);
      final aiHub = !playerHub && _hubIatas.contains(a.iata);
      markers.add(
        Marker(
          point: LatLng(a.lat, a.lon),
          width: 36,
          height: 36,
          child: Center(
            child: Container(
              width: meta.dotSize,
              height: meta.dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: meta.color,
                border: isClosed
                    ? Border.all(color: const Color(0xffffb3b3), width: 2)
                    : selected || playerHub || aiHub
                    ? Border.all(color: Colors.white70, width: 1.2)
                    : null,
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  // Invisible hit-targets — rendered ABOVE route lines so taps reach airports
  // even when a route line overlaps the dot.
  List<Marker> _airportHitMarkers() {
    final markers = <Marker>[];
    for (final a in _visibleAirports()) {
      final meta = _airportMeta(a);
      markers.add(
        Marker(
          point: LatLng(a.lat, a.lon),
          width: 36,
          height: 36,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onAirportSelected(meta.airport),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }
    return markers;
  }

}


// ── SVG icon cache ────────────────────────────────────────────────────────────
// Rasterises each plane-category SVG once at a fixed logical size (64 × 64 px).
// The resulting ui.Image objects are tinted per-airline at draw time using a
// ColorFilter, so we never re-parse the SVG on the paint thread.
class _PlaneIconCache {
  _PlaneIconCache._();

  static const _assets = {
    AircraftCategory.regional:   'assets/map_planes/regional.svg',
    AircraftCategory.narrowbody: 'assets/map_planes/narrowbody.svg',
    AircraftCategory.widebody:   'assets/map_planes/widebody.svg',
    AircraftCategory.sst:        'assets/map_planes/sst.svg',
  };

  static final Map<AircraftCategory, ui.Image> _cache = {};
  static bool _loading = false;

  static bool get isReady => _cache.length == _assets.length;

  static Future<void> ensureLoaded(double devicePixelRatio) async {
    if (isReady || _loading) return;
    _loading = true;
    const logicalSize = 64.0;
    // Add 15% transparent padding on each side so wing-tips that touch the
    // SVG viewBox boundary are never pixel-clipped by the image rect.
    const paddingFraction = 0.15;
    final innerPx = (logicalSize * devicePixelRatio).round().clamp(32, 220);
    final paddingPx = (innerPx * paddingFraction).round();
    final totalPx = innerPx + paddingPx * 2;
    for (final entry in _assets.entries) {
      final info = await vg.loadPicture(SvgAssetLoader(entry.value), null);
      final svgSize = info.size;
      // Render SVG centred inside a padded canvas.
      final recorder = ui.PictureRecorder();
      final padCanvas = ui.Canvas(recorder);
      final scaleX = innerPx / svgSize.width;
      final scaleY = innerPx / svgSize.height;
      padCanvas.translate(paddingPx.toDouble(), paddingPx.toDouble());
      padCanvas.scale(scaleX, scaleY);
      padCanvas.drawPicture(info.picture);
      info.picture.dispose();
      final padded = recorder.endRecording();
      final img = await padded.toImage(totalPx, totalPx);
      padded.dispose();
      _cache[entry.key] = img;
    }
  }

}

// Draws all plane icons on a single canvas — avoids per-plane compositing
// layers and SVG re-rasterisation on every frame (iOS/Impeller bottleneck).
class _PlaneCanvasLayer extends StatefulWidget {
  const _PlaneCanvasLayer({
    required this.routes,
    required this.game,
    required this.mapController,
  });

  final List<RoutePlan> routes;
  final GameController game;
  final MapController mapController;

  @override
  State<_PlaneCanvasLayer> createState() => _PlaneCanvasLayerState();
}

class _PlaneCanvasLayerState extends State<_PlaneCanvasLayer> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_PlaneIconCache.isReady) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      _PlaneIconCache.ensureLoaded(dpr).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return IgnorePointer(
      child: CustomPaint(
        painter: _PlanePainter(
          routes: widget.routes,
          game: widget.game,
          camera: camera,
          icons: _PlaneIconCache._cache,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _PlanePainter extends CustomPainter {
  _PlanePainter({
    required this.routes,
    required this.game,
    required this.camera,
    required this.icons,
  });

  final List<RoutePlan> routes;
  final GameController game;
  final MapCamera camera;
  final Map<AircraftCategory, ui.Image> icons;

  // Reused paint — colorFilter is set per draw call.
  static final _imgPaint = Paint()..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    if (icons.isEmpty) return; // still loading
    final zoom = camera.zoom;
    if (zoom < 2.5) return; // planes are invisible when fully zoomed out
    final zoomScale = (zoom / 6.0).clamp(0.35, 2.0);

    for (final route in routes) {
      final ac = game.aircraft[route.aircraftId];
      if (ac == null ||
          ac.isGrounded ||
          ac.status == AircraftStatus.maintenance ||
          ac.status == AircraftStatus.crashed) continue;

      final origin = airportsByIata[route.originIata];
      final dest = airportsByIata[route.destinationIata];
      if (origin == null || dest == null) continue;

      final vp = roundTripRoutePosition(
        originLat: origin.lat,
        originLon: origin.lon,
        destinationLat: dest.lat,
        destinationLon: dest.lon,
        flightProgress: ac.flightProgress,
      );

      final screenPt = camera.getOffsetFromOrigin(LatLng(vp.lat, vp.lon));

      final airline = game.airlines[route.airlineId];
      final color = _colorFromHex(airline?.color ?? '#ffffff');
      final type = aircraftTypesById[ac.typeId];
      final cat = type?.category;
      final basePx = switch (cat) {
        AircraftCategory.regional => 10.0,
        AircraftCategory.widebody => 14.0,
        AircraftCategory.sst      => 12.0,
        _                         => 12.0,
      };
      final halfPx = basePx * zoomScale;
      // Skip if the plane's worst-case rotated bounding circle falls
      // entirely outside the canvas — avoids partial/clipped silhouettes.
      final reach = halfPx * 1.5; // ≥ half-diagonal of the image square
      if (screenPt.dx < -reach ||
          screenPt.dy < -reach ||
          screenPt.dx > size.width + reach ||
          screenPt.dy > size.height + reach) continue;

      final img = icons[cat ?? AircraftCategory.narrowbody];
      if (img == null) continue;

      _imgPaint.colorFilter = ColorFilter.mode(color, BlendMode.srcIn);

      canvas.save();
      canvas.translate(screenPt.dx, screenPt.dy);
      canvas.rotate(vp.bearingRadians);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: halfPx * 2, height: halfPx * 2),
        _imgPaint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PlanePainter old) =>
      old.routes != routes || old.camera != camera || old.icons != icons;
}

List<List<LatLng>> _routeArcLatLngSegments(
  Airport origin,
  Airport destination, {
  int pointCount = 18,
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
      Paint()..color = const Color(0xff0d0d0d),
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
    final tAhead = t + 0.01;
    final lookBack = tAhead > 1.0;
    final ahead = _visualArcPoint(
      from.lat,
      from.lon,
      to.lat,
      to.lon,
      lookBack ? math.max(0.0, t - 0.01) : math.min(1.0, tAhead),
    );
    final point = _latLonPoint(visualPoint.lat, visualPoint.lon, size);
    final aheadPoint = _latLonPoint(ahead.lat, ahead.lon, size);
    final rawAngle = math.atan2(
      aheadPoint.dy - point.dy,
      aheadPoint.dx - point.dx,
    );
    final angle = lookBack ? rawAngle + math.pi : rawAngle;
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
      ..color = const Color(0xff111111)
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
                        style: const TextStyle(color: Color(0xff9e9e9e)),
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
                              ?.copyWith(color: const Color(0xff9e9e9e)),
                        ),
                        const SizedBox(height: 12),
                        _AppBtn(
                          variant: _BtnVariant.tonal,
                          onPressed:
                              terminalCost == null ||
                                  game.player.cashUSD < terminalCost
                              ? null
                              : () => game.upgradeHubTerminal(airport.iata),
                          icon: const Icon(Icons.apartment),
                          child: Text(
                            terminalCost == null
                                ? 'Terminal maxed'
                                : 'Upgrade terminal ${money(terminalCost, currency)}',
                          )
                        ),
                        const SizedBox(height: 8),
                        _AppBtn(
                          variant: _BtnVariant.tonal,
                          onPressed:
                              loungeCost == null ||
                                  game.player.cashUSD < loungeCost
                              ? null
                              : () =>
                                    game.upgradeFirstClassLounge(airport.iata),
                          icon: const Icon(Icons.airline_seat_recline_extra),
                          child: Text(
                            loungeCost == null
                                ? 'Lounges maxed'
                                : 'Upgrade lounges ${money(loungeCost, currency)}',
                          )
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  initiallyExpanded: true,
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
                  child: _AppBtn(
                    onPressed: () => onCreateRoute(airport, null),
                    icon: const Icon(Icons.add),
                    child: const Text('New Route'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AppBtn(
                    variant: _BtnVariant.ghost,
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
child: Text(isPlayerHub ? 'Remove Hub' : 'Set Hub')
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
                  color: Color(0xff9e9e9e),
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
            backgroundColor: const Color(0xff2e2e2e),
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
    final Color valueColor;
    final String valueLabel;
    if (isLiveRoute) {
      valueColor = value >= 0
          ? const Color(0xff3af083)
          : const Color(0xffff6b6b);
      valueLabel = '${money(value, currency)}/d live';
    } else {
      // potential revenue tier: green > $8k, yellow > $2k, gray otherwise
      valueColor = value >= 8000
          ? const Color(0xff3af083)
          : value >= 2000
          ? const Color(0xffffd166)
          : const Color(0xff8b95a8);
      valueLabel = '~${money(value, currency)}/d est.';
    }
    final valueText = valueLabel;
    return Material(
      color: const Color(0xff1e1e1e),
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
    final activeCount = routes.where((r) => r.isActive).length;
    final inactiveCount = routes.length - activeCount;
    final optimisation = game.previewNetworkOptimisation();
    final canOptimiseAll =
        optimisation.hasChanges && game.player.cashUSD >= optimisation.costUSD;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _AppBtn(
                onPressed: onCreateRoute,
                icon: const Icon(Icons.add_road),
                child: const Text('New Route'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                'Daily route profit',
                money(
                  routes.fold<double>(
                    0,
                    (sum, route) => sum + route.dailyProfit,
                  ),
                  currency,
                ),
                const Color(0xff3af083),
              ),
            ),
            if (routes.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  'Active',
                  '$activeCount / ${routes.length}',
                  activeCount == routes.length
                      ? const Color(0xff3af083)
                      : const Color(0xffffd166),
                ),
              ),
            ],
          ],
        ),
        if (inactiveCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: Color(0xffffd166),
                ),
                const SizedBox(width: 6),
                Text(
                  '$inactiveCount inactive route${inactiveCount > 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: Color(0xffffd166),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
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
                    _AppBtn(
                      onPressed: canOptimiseAll
                          ? game.optimiseAllPlayerRoutes
                          : null,
                      icon: const Icon(Icons.auto_fix_high),
                      child: const Text('Optimise all'),
                    ),
                  ],
                ),
                Text(
                  optimisation.eligibleCount == 0
                      ? 'Assign aircraft to routes before optimising.'
                      : optimisation.optimisableCount == 0
                      ? 'All eligible routes are already optimised.'
                      : '${optimisation.optimisableCount} routes can improve · ${money(optimisation.costUSD, currency)} consulting fee',
                  style: const TextStyle(color: Color(0xff9e9e9e)),
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
      ],
    );

    // Virtualized list: only the cards currently on-screen are built and
    // laid out. With 35+ routes each `_RouteCard` is an `ExpansionTile` that
    // does non-trivial work in build() (incl. an optimiser preview lookup),
    // so eager rendering of all of them used to spike memory and crash the
    // tab on open.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(child: header),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverList.builder(
            itemCount: routes.length,
            itemBuilder: (context, index) {
              final route = routes[index];
              return RepaintBoundary(
                key: ValueKey(route.id),
                child: _RouteCard(
                  game: game,
                  route: route,
                  currency: currency,
                ),
              );
            },
          ),
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
    final optimisation = game.previewRouteOptimisationCached(route.id);
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
    final statusColor = route.isActive
        ? const Color(0xff3af083)
        : const Color(0xff8b95a8);
    final profitColor = route.dailyProfit >= 0
        ? const Color(0xff3af083)
        : const Color(0xffff6b6b);

    return _Card(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${route.originIata} → ${route.destinationIata}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 8),
            if (inactiveReason != null)
              _FleetStatusChip(
                label: inactiveReason.toUpperCase(),
                color: const Color(0xffffd166),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              money(route.dailyProfit, currency),
              style: TextStyle(
                color: profitColor,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            // ExpansionTile draws its own chevron after trailing, so we just
            // leave space for it with a zero-width widget.
            const SizedBox.shrink(),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            type == null
                ? 'No aircraft · ${route.flightsPerWeek}/wk'
                : '${type.displayName} · ${route.flightsPerWeek}/wk',
            style: const TextStyle(color: Color(0xff9e9e9e), fontSize: 12),
          ),
        ),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RouteMiniStat('Eco fare', money(route.priceEconomy, currency)),
              if (route.priceBusiness > 0)
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
              _AppBtn(
                variant: _BtnVariant.ghost,
                onPressed: optimisation == null
                    ? null
                    : () => game.optimiseRoute(route.id),
                icon: const Icon(Icons.auto_fix_high),
                child: Text(optimisation == null ? 'Optimised' : 'Optimise'),
              ),
              _AppBtn(
                variant: _BtnVariant.ghost,
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => _RouteEditDialog(
                    game: game,
                    route: route,
                    currency: currency,
                  ),
                ),
                icon: const Icon(Icons.tune),
                child: const Text('Details'),
              ),
              confirmingDelete
                  ? _AppBtn(
                      variant: _BtnVariant.tonal,
                      onPressed: () {
                        game.deleteRoute(route.id);
                        setState(() => confirmingDelete = false);
                      },
                      icon: const Icon(Icons.delete_forever),
                      child: const Text('Confirm delete'),
                    )
                  : _AppBtn(
                      variant: _BtnVariant.ghost,
                      onPressed: () =>
                          setState(() => confirmingDelete = true),
                      icon: const Icon(Icons.delete_outline),
                      child: const Text('Delete'),
                    ),
              if (confirmingDelete)
                IconButton(
                  tooltip: 'Cancel delete',
                  onPressed: () =>
                      setState(() => confirmingDelete = false),
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
                : const Color(0xff9e9e9e);
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
          child: Text(label, style: const TextStyle(color: Color(0xff9e9e9e))),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value.clamp(0, 1),
              minHeight: 8,
              color: color,
              backgroundColor: const Color(0xff2e2e2e),
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
              style: TextStyle(color: Color(0xff9e9e9e)),
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
              style: const TextStyle(color: Color(0xff9e9e9e)),
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
                style: const TextStyle(color: Color(0xff9e9e9e)),
              ),
              const SizedBox(height: 6),
              const Text(
                'Terminals raise capacity. First class lounges raise demand.',
                style: TextStyle(color: Color(0xff9e9e9e)),
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
                            style: const TextStyle(color: Color(0xff9e9e9e)),
                          ),
                          Text(
                            '${money(hubAnnualFeeUsd / 365, currency)}/day',
                            style: const TextStyle(color: Color(0xffffd166)),
                          ),
                        ],
                      ),
                    ),
                    _AppBtn(
                      variant: _BtnVariant.ghost,
                      onPressed: hubs.length <= 1
                          ? null
                          : () => game.removePlayerHub(airport.iata),
                      icon: const Icon(Icons.remove_circle_outline),
                      child: const Text('Remove'),
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
                Text(detail, style: const TextStyle(color: Color(0xff9e9e9e))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _AppBtn(
            variant: _BtnVariant.ghost,
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
              _AppBtn(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) =>
                      _BuyAircraftDialog(game: game, currency: currency),
                ),
                icon: const Icon(Icons.add),
                child: const Text('Buy Aircraft'),
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
                        style: const TextStyle(color: Color(0xff9e9e9e)),
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
              : 'Route ${route.originIata} →${route.destinationIata}';
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
                      color: Color(0xff9e9e9e),
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
                            backgroundColor: const Color(0xff2e2e2e),
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
                  if (_aircraftImageAsset(ac.typeId) != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: double.infinity,
                        height: 110,
                        color: const Color(0xff1a1f2e),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Image.asset(
                          _aircraftImageAsset(ac.typeId)!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
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
                          style: const TextStyle(color: Color(0xff9e9e9e)),
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
                      style: const TextStyle(color: Color(0xff9e9e9e)),
                    ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: ac.condition / 100,
                    color: conditionColor,
                    backgroundColor: const Color(0xff2e2e2e),
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
                    style: const TextStyle(color: Color(0xff9e9e9e)),
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
                          child: _AppBtn(
                            variant: _BtnVariant.ghost,
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (context) => _RouteEditDialog(
                                game: game,
                                route: route,
                                currency: currency,
                              ),
                            ),
                            icon: const Icon(Icons.alt_route),
                            child: const Text('View Route'),
                          ),
                        ),
                      if (route != null) const SizedBox(width: 8),
                      Expanded(
                        child: isConfirmingSale
                            ? Row(
                                children: [
                                  Expanded(
                                    child: _AppBtn(
                                      variant: _BtnVariant.tonal,
                                      onPressed: canSell
                                          ? () {
                                              game.sellAircraft(ac.id);
                                              setState(
                                                () => confirmingSaleId = null,
                                              );
                                            }
                                          : null,
                                      icon: const Icon(Icons.check),
                                      child: Text(
                                        isCrashed ? 'Write off' : 'Confirm',
                                      )
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
                            : _AppBtn(
                                variant: _BtnVariant.ghost,
                                onPressed: canSell
                                    ? () => setState(
                                        () => confirmingSaleId = ac.id,
                                      )
                                    : null,
                                icon: Icon(
                                  isCrashed ? Icons.delete_forever : Icons.sell,
                                ),
                                child: Text(
                                  isCrashed ? 'Write Off' : 'Sell Aircraft',
                                )
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (type != null) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 4, bottom: 6),
                      child: Text(
                        'Manual Maintenance',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Color(0xff9e9e9e),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
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
                        return _AppBtn(
                          variant: _BtnVariant.ghost,
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
                  ],
                  if (!ac.excludedFromPolicy)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Fleet policy ${policy.enabled ? 'ON' : 'OFF'}',
                        style: const TextStyle(color: Color(0xff9e9e9e)),
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
                                          color: Color(0xff9e9e9e),
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
                      child: _AppBtn(
                        variant: _BtnVariant.ghost,
                        onPressed: () => game.completeMaintenance(ac.id),
                        icon: const Icon(Icons.build_circle),
                        child: const Text('Complete now'),
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
                    : const Color(0xff9e9e9e),
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
              clipBehavior: Clip.antiAlias,
              child: _aircraftImageAsset(type.id) != null
                  ? Opacity(
                      opacity: unavailable ? 0.5 : 1,
                      child: Image.asset(
                        _aircraftImageAsset(type.id)!,
                        fit: BoxFit.contain,
                        width: 112,
                        height: 58,
                      ),
                    )
                  : Icon(
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    type.model,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                if (unavailable)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: _FleetStatusChip(
                                      label: 'AVAIL. ${type.yearIntroduced}',
                                      color: const Color(0xffffd166),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _aircraftCategoryLabel(type.category),
                              style: const TextStyle(
                                color: Color(0xff8b95a8),
                                fontSize: 12,
                              ),
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
                            _AppBtn(
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

const _aircraftImageAssets = <String, String>{
  // ── Concorde ──────────────────────────────────────────────────────────────
  'concorde':     'assets/planes/Concorde.png',

  // ── Airbus narrow-body ────────────────────────────────────────────────────
  'a220-100':     'assets/planes/A220-200.png',
  'a220-300':     'assets/planes/A220-300.png',
  'a319':         'assets/planes/A319.png',
  'a319neo':      'assets/planes/A319neo.png',
  'a320':         'assets/planes/A320.png',
  'a320neo':      'assets/planes/A320neo.png',
  'a321':         'assets/planes/A321.png',
  'a321neo':      'assets/planes/A321neo.png',
  'a321xlr':      'assets/planes/A321xlr.png',

  // ── Airbus wide-body ──────────────────────────────────────────────────────
  'a300-600':     'assets/planes/A300-600.png',
  'a330-200':     'assets/planes/A330-200.png',
  'a330-300':     'assets/planes/A330-300.png',
  'a330-800neo':  'assets/planes/A330-800neo.png',
  'a330-900neo':  'assets/planes/A330-900neo.png',
  'a340-300':     'assets/planes/A340-300.png',
  'a340-600':     'assets/planes/A340-600.png',
  'a350-900':     'assets/planes/A350-900.png',
  'a350-1000':    'assets/planes/A350-1000.png',
  'a380-800':     'assets/planes/A380-800.png',

  // ── ATR turboprops ────────────────────────────────────────────────────────
  'atr42-300':    'assets/planes/ATR42-300.png',
  'atr42-600':    'assets/planes/ATR42-600.png',
  'atr72-200':    'assets/planes/ATR72-200.png',
  'atr72-500':    'assets/planes/ATR72-500.png',
  'atr72-600':    'assets/planes/ATR72-600.png',

  // ── Avro / BAe regional jets ──────────────────────────────────────────────
  'avrorj100':    'assets/planes/AvroRJ100.png',
  'avrorj85':     'assets/planes/AvroRJ85.png',
  'bae146-100':   'assets/planes/BAe146-100.png',
  'bae146-200':   'assets/planes/BAe146-200.png',
  'bae146-300':   'assets/planes/BAe146-300.png',

  // ── BAC One-Eleven ────────────────────────────────────────────────────────
  'bac111-200':   'assets/planes/BAC111-200.png',
  'bac111-500':   'assets/planes/BAC111-500.png',

  // ── Boeing narrow-body ────────────────────────────────────────────────────
  'b707-120':     'assets/planes/B707-120.png',
  'b707-320':     'assets/planes/B707-320.png',
  'b717-200':     'assets/planes/B717-200.png',
  'b727-100':     'assets/planes/B727-100.png',
  'b727-200':     'assets/planes/B727-200.png',
  'b737-100':     'assets/planes/B737-100.png',
  'b737-200':     'assets/planes/B737-200.png',
  'b737-600':     'assets/planes/B737-600.png',
  'b737-700':     'assets/planes/B737-700.png',
  'b737-800':     'assets/planes/B737-800.png',
  'b737-900er':   'assets/planes/B737-900er.png',
  'b737max7':     'assets/planes/B737Max7.png',
  'b737max8':     'assets/planes/B737Max8.png',
  'b737max9':     'assets/planes/B737Max9.png',
  'b737max10':    'assets/planes/B737Max10.png',
  'b757-200':     'assets/planes/B757-200.png',
  'b757-300':     'assets/planes/B757-300.png',

  // ── Boeing wide-body ──────────────────────────────────────────────────────
  'b747-100':     'assets/planes/B747-100.png',
  'b747-200':     'assets/planes/B747-200.png',
  'b747-300':     'assets/planes/B747-300.png',
  'b747-400':     'assets/planes/B747-400.png',
  'b747-8i':      'assets/planes/B747-8i.png',
  'b767-200er':   'assets/planes/B767-200er.png',
  'b767-300er':   'assets/planes/B767-300er.png',
  'b767-400er':   'assets/planes/B767-400er.png',
  'b777-200':     'assets/planes/B777-200.png',
  'b777-200er':   'assets/planes/B777-200er.png',
  'b777-200lr':   'assets/planes/B777-200lr.png',
  'b777-300er':   'assets/planes/B777-300er.png',
  'b777-9':       'assets/planes/B777-9.png',
  'b787-8':       'assets/planes/B787-8.png',
  'b787-9':       'assets/planes/B787-9.png',
  'b787-10':      'assets/planes/B787-10.png',

  // ── Bombardier CRJ ────────────────────────────────────────────────────────
  'crj200':       'assets/planes/CRJ200.png',
  'crj700':       'assets/planes/CRJ700.png',
  'crj900':       'assets/planes/CRJ900.png',
  'crj1000':      'assets/planes/CRJ1000.png',

  // ── Bombardier Q Series ───────────────────────────────────────────────────
  'q400':         'assets/planes/Q400.png',

  // ── Cessna ───────────────────────────────────────────────────────────────
  'c208':         'assets/planes/C208.png',
  'c208b':        'assets/planes/C208b.png',

  // ── COMAC ─────────────────────────────────────────────────────────────────
  'c919':         'assets/planes/C919.png',
  'arj21-700':    'assets/planes/ARJ21-700.png',
  'arj21-900':    'assets/planes/ARJ21-900.png',

  // ── Antonov turboprops ────────────────────────────────────────────────────
  'an24':         'assets/planes/An24.png',

  // ── Ilyushin ─────────────────────────────────────────────────────────────
  'il18':         'assets/planes/IL18.png',
  'il62':         'assets/planes/IL62.png',
  'il-62m':       'assets/planes/IL62.png',
  'il-86':        'assets/planes/IL86.png',
  'il-96-300':    'assets/planes/IL96.png',
  'il-96-400':    'assets/planes/IL96.png',

  // ── Tupolev ───────────────────────────────────────────────────────────────
  'tu104a':       'assets/planes/Tu104.png',
  'tu124':        'assets/planes/Tu124.png',
  'tu-134a':      'assets/planes/Tu134.png',
  'tu-144':       'assets/planes/Tu144.png',
  'tu-154b':      'assets/planes/Tu154.png',
  'tu-154m':      'assets/planes/Tu154.png',
  'tu-204-100':   'assets/planes/Tu204.png',
  'tu-204-300':   'assets/planes/Tu204.png',
  'tu-214':       'assets/planes/Tu214.png',

  // ── Yakovlev ──────────────────────────────────────────────────────────────
  'yak40':        'assets/planes/Yak40.png',
  'yak-42d':      'assets/planes/Yak42.png',

  // ── Sukhoi / SSJ ─────────────────────────────────────────────────────────
  'ssj-100':      'assets/planes/SSJ-100.png',

  // ── Irkut MC-21 ───────────────────────────────────────────────────────────
  'mc-21-300':    'assets/planes/MC-21-300.png',
  'mc-21-310':    'assets/planes/MC-21-310.png',

  // ── Ilyushin (additional) ────────────────────────────────────────────────
  'il14':         'assets/planes/il14.png',

  // ── Douglas ──────────────────────────────────────────────────────────────
  'dc8-50':       'assets/planes/DC8-50.png',
  'dc9-10':       'assets/planes/DC9-10.png',
  'dc9-30':       'assets/planes/DC9-30.png',
  'dc10-10':      'assets/planes/DC10-10.png',
  'dc10-30':      'assets/planes/DC10-30.png',
  'dc10-40':      'assets/planes/DC10-40.png',

  // ── McDonnell Douglas ─────────────────────────────────────────────────────
  'md11':         'assets/planes/MD11.png',
  'md80':         'assets/planes/MD80.png',

  // ── Lockheed L-1011 ──────────────────────────────────────────────────────
  'l1011-1':      'assets/planes/l1011-1.png',
  'l1011-100':    'assets/planes/l1011-100.png',
  'l1011-200':    'assets/planes/l1011-200.png',
  'l1011-500':    'assets/planes/l1011-500.png',

  // ── de Havilland Canada ──────────────────────────────────────────────────
  'dhc7':         'assets/planes/DHC7.png',
  'dhc8-100':     'assets/planes/DHC8-100.png',
  'dhc8-200':     'assets/planes/DHC8-200.png',
  'dhc8-300':     'assets/planes/DHC8-300.png',
  'dhc8-400':     'assets/planes/DHC8-400.png',

  // ── Embraer ───────────────────────────────────────────────────────────────
  'e170':         'assets/planes/E170.png',
  'e175':         'assets/planes/E175.png',
  'e190':         'assets/planes/E190.png',
  'e190-e2':      'assets/planes/E190-E2.png',
  'e195':         'assets/planes/E195.png',
  'e195-e2':      'assets/planes/E195-E2.png',
  'emb120':       'assets/planes/EMB120.png',
  'erj135':       'assets/planes/ERJ135.png',
  'erj145':       'assets/planes/ERJ145.png',

  // ── Fokker ────────────────────────────────────────────────────────────────
  'fokker100':    'assets/planes/Fokker100.png',
  'fokker50':     'assets/planes/Fokker50.png',
  'fokker70':     'assets/planes/Fokker70.png',

  // ── Fokker originals ──────────────────────────────────────────────────────
  'f27-200':      'assets/planes/F27-200.png',
  'f28-1000':     'assets/planes/F28-1000.png',
  'f28-4000':     'assets/planes/F28-4000.png',

  // ── Saab ──────────────────────────────────────────────────────────────────
  'saab2000':     'assets/planes/Saab2000.png',
  'saab340':      'assets/planes/Saab340.png',

  // ── Dassault Falcon ───────────────────────────────────────────────────────
  'falcon20':     'assets/planes/Falcon20.png',
  'falcon2000':   'assets/planes/Falcon2000.png',
  'falcon50':     'assets/planes/Falcon50.png',
  'falcon7x':     'assets/planes/Falcon7x.png',
  'falcon8x':     'assets/planes/Falcon8x.png',
  'falcon900':    'assets/planes/Falcon900.png',

  // ── Sud Aviation ─────────────────────────────────────────────────────────
  'caravelle':    'assets/planes/Caravelle.png',

  // ── Dassault Mercure ─────────────────────────────────────────────────────
  'mercure':      'assets/planes/Mercure.png',

  // ── COMAC C929 ────────────────────────────────────────────────────────────
  'c929':         'assets/planes/C929.png',

  // ── Piper ─────────────────────────────────────────────────────────────────
  'pa31':         'assets/planes/PA31.png',
  'pa42':         'assets/planes/PA42.png',
};

String? _aircraftImageAsset(String typeId) => _aircraftImageAssets[typeId];

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
    // Single-pass snapshot — replaces ~10 separate folds + a sort that used to
    // run on every Finance-tab build and crashed at 35+ routes.
    final snapshot = game.playerFinanceSnapshot;
    final profitableRoutes = snapshot.profitableRoutes;
    final losingRoutes = snapshot.losingRoutes;
    final averageLoadFactor = snapshot.averageLoadFactor;
    final averageCondition = snapshot.averageCondition;
    final groundedAircraft = snapshot.groundedAircraft;
    final dailyPassengers = last?.passengers ?? 0;
    final totalDailyRevenue = snapshot.totalDailyRevenue;
    final totalDailyCost = snapshot.totalDailyCost;
    final exactCostTotal = snapshot.fuelCost +
        snapshot.maintenanceCost +
        snapshot.crewCost +
        snapshot.airportFees;
    // Same fallback as before: prefer the exact per-component figures if the
    // route engine has populated them, otherwise pro-rate the total cost.
    final fuelCost = exactCostTotal > 0
        ? snapshot.fuelCost
        : totalDailyCost * 0.35;
    final maintenanceCost = exactCostTotal > 0
        ? snapshot.maintenanceCost
        : totalDailyCost * 0.25;
    final crewCost = exactCostTotal > 0
        ? snapshot.crewCost
        : totalDailyCost * 0.25;
    final airportFees = exactCostTotal > 0
        ? snapshot.airportFees
        : totalDailyCost * 0.15;
    final topRoutes = snapshot.topRoutesByProfit;
    final shareholdingsValue = snapshot.shareholdingsValue;
    final projectedDividends = snapshot.projectedDividends;
    final dividendSources = snapshot.dividendSources;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _FinanceMetric(
                label: 'Cash',
                value: money(player.cashUSD, currency),
                accent: const Color(0xff3af083),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FinanceMetric(
                label: 'Last daily profit',
                value: money(lastProfit, currency),
                accent: lastProfit >= 0
                    ? const Color(0xff3af083)
                    : const Color(0xffff6b6b),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _FinanceMetric(
                label: 'Company value',
                value: money(companyValue, currency),
                accent: const Color(0xff77c9ff),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FinanceMetric(
                label: 'Debt',
                value: money(player.totalDebt, currency),
                accent: const Color(0xffffd166),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
                          style: TextStyle(color: Color(0xff9e9e9e)),
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
                'Daily breakdown',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final totalCost = fuelCost +
                      maintenanceCost +
                      crewCost +
                      airportFees +
                      debtService;
                  final segments = [
                    (label: 'Fuel', value: fuelCost, color: const Color(0xffff6b6b)),
                    (label: 'Maint', value: maintenanceCost, color: const Color(0xffffa94d)),
                    (label: 'Crew', value: crewCost, color: const Color(0xffffd166)),
                    (label: 'Airport', value: airportFees, color: const Color(0xff77c9ff)),
                    (label: 'Debt', value: debtService, color: const Color(0xffff8fab)),
                  ].where((s) => s.value > 0).toList();
                  if (totalCost <= 0) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          height: 14,
                          child: Row(
                            children: segments.map((seg) => Flexible(
                              flex: (seg.value / totalCost * 1000).round(),
                              child: Container(color: seg.color),
                            )).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: segments.map((seg) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: seg.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${seg.label} ${(seg.value / totalCost * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 11, color: Color(0xff9e9e9e)),
                            ),
                          ],
                        )).toList(),
                      ),
                      const SizedBox(height: 10),
                    ],
                  );
                },
              ),
              _FinanceBreakdownRow(label: 'Revenue', value: totalDailyRevenue, color: const Color(0xff3af083), currency: currency),
              _FinanceBreakdownRow(label: 'Fuel', value: -fuelCost, color: const Color(0xffff6b6b), currency: currency),
              _FinanceBreakdownRow(label: 'Maintenance', value: -maintenanceCost, color: const Color(0xffffa94d), currency: currency),
              _FinanceBreakdownRow(label: 'Crew', value: -crewCost, color: const Color(0xffffd166), currency: currency),
              _FinanceBreakdownRow(label: 'Airport fees', value: -airportFees, color: const Color(0xff77c9ff), currency: currency),
              _FinanceBreakdownRow(label: 'Debt service', value: -debtService, color: const Color(0xffff8fab), currency: currency),
              if (projectedDividends > 0)
                _FinanceBreakdownRow(label: 'Dividends', value: projectedDividends, color: const Color(0xff2dd4bf), currency: currency),
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
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Operating performance',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              _InfoRow('Routes', '${snapshot.activeRouteCount} active'),
              _InfoRow(
                'Route health',
                '$profitableRoutes profitable · $losingRoutes losing',
              ),
              _InfoRow('Fleet', '${game.playerFleet.length} aircraft'),
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
              _InfoRow(
                'Reputation',
                '${player.reputationScore.toStringAsFixed(0)}/100',
              ),
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
              Builder(
                builder: (context) {
                  final float = game.marketFloatForAirline(player.id);
                  final playerOwned = (100 - float).clamp(0, 100);
                  final aiOwned = player.shareholders.entries
                      .where((e) => e.key != 'player' && e.value > 0)
                      .fold<double>(0, (sum, e) => sum + e.value);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          height: 12,
                          child: Row(
                            children: [
                              Flexible(
                                flex: playerOwned.round(),
                                child: Container(
                                  color: const Color(0xff2dd4bf),
                                ),
                              ),
                              if (aiOwned > 0)
                                Flexible(
                                  flex: aiOwned.round(),
                                  child: Container(
                                    color: const Color(0xffffd166),
                                  ),
                                ),
                              if (float > 0)
                                Flexible(
                                  flex: float.round(),
                                  child: Container(
                                    color: const Color(0xff64748b),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _OwnershipChip(
                            label: 'You ${playerOwned.toStringAsFixed(1)}%',
                            accent: const Color(0xff2dd4bf),
                          ),
                          if (aiOwned > 0)
                            _OwnershipChip(
                              label: 'AI ${aiOwned.toStringAsFixed(1)}%',
                              accent: const Color(0xffffd166),
                            ),
                          if (float > 0)
                            _OwnershipChip(
                              label: 'Float ${float.toStringAsFixed(1)}%',
                              accent: const Color(0xff64748b),
                            ),
                        ],
                      ),
                    ],
                  );
                },
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
                      ? '${origin.city} →${dest.city}'
                      : '${route.originIata} →${route.destinationIata}';
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
                  backgroundColor: const Color(0xff2e2e2e),
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
                  style: TextStyle(color: Color(0xff9e9e9e)),
                ),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 2.6,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: loanOffers.map((offer) {
                  final available = game.canApplyForLoan(offer);
                  final dailyPayment = calculateDailyLoanPayment(
                    offer.amountUSD,
                    offer.annualInterestRate,
                    offer.termYears,
                  );
                  return _AppBtn(
                    variant: _BtnVariant.ghost,
                    onPressed: available
                        ? () => showDialog<void>(
                            context: context,
                            builder: (ctx) => _GlassDialog(
                              title: const Text('Confirm Loan'),
                              content: Text(
                                'Apply for a ${money(offer.amountUSD, currency)} loan at ${formatInterestRate(offer.annualInterestRate)} over ${offer.termYears} ${offer.termYears == 1 ? "year" : "years"}?\n\nDaily repayment: ${money(dailyPayment, currency)}/day',
                              ),
                              actions: [
                                _AppBtn(
                                  variant: _BtnVariant.plain,
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('Cancel'),
                                ),
                                _AppBtn(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    game.applyForLoan(offer);
                                  },
                                  child: const Text('Apply'),
                                ),
                              ],
                            ),
                          )
                        : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
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
                final shortfall = option.amount - cash;
                return Tooltip(
                  message: canPay
                      ? ''
                      : 'Need ${money(shortfall, currency)} more',
                  child: _AppBtn(
                    variant: _BtnVariant.ghost,
                    onPressed: canPay
                        ? () => game.repayLoan(loan.id, option.amount)
                        : null,
                    child: Text(
                      '${option.label} · ${money(option.amount, currency)}',
                    ),
                  ),
                );
              }),
              _AppBtn(
                variant: _BtnVariant.tonal,
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
              color: strong ? const Color(0xffe0e0e0) : const Color(0xff9e9e9e),
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

/// Formats an integer cost with thousands separators, e.g. 809352 → "809,352".
String _formatCost(int value) {
  final s = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return value < 0 ? '-${buf.toString()}' : buf.toString();
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
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xff9e9e9e))),
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
        Text(label, style: const TextStyle(color: Color(0xff9e9e9e))),
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
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween<Offset>(
            begin: child.key == const ValueKey('detail')
                ? const Offset(1, 0)
                : const Offset(-1, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          ),
          child: child,
        ),
        child: selected != null
            ? KeyedSubtree(
                key: const ValueKey('detail'),
                child: _buildDetail(),
              )
            : KeyedSubtree(
                key: const ValueKey('list'),
                child: _buildList(),
              ),
      ),
    );
  }

  Widget _buildDetail() {
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
            child: _AppBtn(
              variant: _BtnVariant.plain,
              onPressed: () => setState(() => selected = null),
              icon: const Icon(Icons.arrow_back),
              child: const Text('Back'),
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
                            style: const TextStyle(color: Color(0xff9e9e9e)),
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
                        ? '${origin.city} →${dest.city}'
                        : '${route.originIata} →${route.destinationIata}';
                    return _FinanceRouteRow(
                      label: label,
                      detail:
                          '${route.originIata} →${route.destinationIata} · ${(route.loadFactorEconomy * 100).round()}% LF',
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
                      _AppBtn(
                        onPressed: marketFloat < 1 && aiShareholders.isEmpty
                            ? null
                            : () => _showShareTradeDialog(
                                context,
                                widget.game,
                                airline.id,
                                widget.currency,
                              ),
                        icon: const Icon(Icons.pie_chart),
                        child: const Text('Buy / sell shares'),
                      ),
                      _AppBtn(
                        variant: _BtnVariant.tonal,
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
                        child: Text(
                          'Takeover ${money(takeoverCost, widget.currency)}',
                        )
                      ),
                    ],
                  ),
                  if (playerStake < 50)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Majority stake required for takeover.',
                        style: TextStyle(color: Color(0xff9e9e9e)),
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
              final isCrashed = ac.status == AircraftStatus.crashed;
              final inMaint = ac.status == AircraftStatus.maintenance;
              final chipLabel = isCrashed
                  ? 'LOST'
                  : inMaint
                  ? 'MAINT'
                  : ac.isGrounded
                  ? 'GROUNDED'
                  : ac.autoMaintenanceEnabled
                  ? 'AUTO'
                  : null;
              final chipColor = isCrashed || ac.isGrounded
                  ? const Color(0xffff6b6b)
                  : inMaint
                  ? const Color(0xffffd166)
                  : const Color(0xff77c9ff);
              return ListTile(
                title: Row(
                  children: [
                    Expanded(child: Text(ac.name)),
                    if (chipLabel != null)
                      _FleetStatusChip(label: chipLabel, color: chipColor),
                  ],
                ),
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
                      '${route.originIata} →${route.destinationIata}',
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
    return const SizedBox.shrink();
  }

  Widget _airlineListTile(Airline airline) {
    final playerStake = airline.shareholders['player'] ?? 0.0;
    final hubLabel = airline.hubIatas.isEmpty
        ? null
        : airline.hubIatas.take(2).join(', ');
    final shareColor = airline.isPlayer
        ? const Color(0xff2dd4bf)
        : const Color(0xffffd166);
    return Opacity(
      opacity: airline.isInsolvent ? 0.55 : 1.0,
      child: _Card(
        child: InkWell(
          onTap: () => setState(() => selected = airline),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                        Builder(builder: (context) {
                          final activeRouteCount = airline.routeIds
                              .where((id) =>
                                  widget.game.routes[id]?.isActive == true)
                              .length;
                          final fleetCount = airline.fleetIds
                              .where((id) =>
                                  widget.game.aircraft[id] != null)
                              .length;
                          return Text(
                            '$activeRouteCount routes · $fleetCount aircraft'
                            '${hubLabel != null ? ' · $hubLabel' : ''}',
                            style: const TextStyle(
                              color: Color(0xff9e9e9e),
                              fontSize: 11,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  if (playerStake > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FleetStatusChip(
                        label: '${playerStake.toStringAsFixed(0)}%',
                        color: const Color(0xff2dd4bf),
                      ),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${airline.marketSharePercent.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: shareColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        money(airline.lastDailyProfit, widget.currency),
                        style: TextStyle(
                          fontSize: 11,
                          color: airline.lastDailyProfit >= 0
                              ? const Color(0xff3af083)
                              : const Color(0xffff6b6b),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (airline.marketSharePercent / 100).clamp(0, 1),
                  minHeight: 4,
                  color: shareColor,
                  backgroundColor: shareColor.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 11,
                    color: Color(0xff9e9e9e),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'Rep ${airline.reputationScore.toStringAsFixed(0)}/100',
                    style: const TextStyle(
                      color: Color(0xff9e9e9e),
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    money(airline.cashUSD, widget.currency),
                    style: TextStyle(
                      fontSize: 11,
                      color: airline.cashUSD >= 0
                          ? const Color(0xff9e9e9e)
                          : const Color(0xffff6b6b),
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

  Widget _buildList() {
    final allCompetitors = [...widget.game.competitors];
    final activeCompetitors = allCompetitors
        .where((a) => !a.isInsolvent)
        .toList()
      ..sort((a, b) => b.marketSharePercent.compareTo(a.marketSharePercent));
    final insolventCompetitors = allCompetitors
        .where((a) => a.isInsolvent)
        .toList();
    final activeAirlines = [widget.game.player, ...activeCompetitors];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetricCard(
          'Active Airlines',
          '${activeAirlines.length}',
          const Color(0xff77c9ff),
        ),
        ...activeAirlines.map(_airlineListTile),
        if (insolventCompetitors.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            title: Text(
              'Insolvent Airlines (${insolventCompetitors.length})',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xffff6b6b),
                fontWeight: FontWeight.w700,
              ),
            ),
            tilePadding: EdgeInsets.zero,
            children: insolventCompetitors.map(_airlineListTile).toList(),
          ),
        ],
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
        return _GlassDialog(
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
                          color: Color(0xff9e9e9e),
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
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [1, 5, 10, 25, 50].map((pct) {
                    final canSelect = pct <= max;
                    return ActionChip(
                      label: Text('$pct%'),
                      onPressed: canSelect
                          ? () => setState(() => percent = pct.toDouble())
                          : null,
                      backgroundColor: clampedPercent.round() == pct
                          ? const Color(0xff2dd4bf).withValues(alpha: 0.2)
                          : null,
                      side: clampedPercent.round() == pct
                          ? const BorderSide(color: Color(0xff2dd4bf))
                          : null,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selling ? 'Proceeds' : 'Cost',
                        style: const TextStyle(color: Color(0xff9e9e9e)),
                      ),
                    ),
                    Text(
                      money(price, currency),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: !selling && game.player.cashUSD < price
                            ? const Color(0xffff6b6b)
                            : null,
                      ),
                    ),
                  ],
                ),
                if (!selling) ...[
                  _InfoRow(
                    'Rival cash after',
                    money(airline.cashUSD + price, currency),
                  ),
                  Builder(
                    builder: (context) {
                      final dividendPerDay = airline.lastDailyProfit > 0
                          ? airline.lastDailyProfit * (clampedPercent / 100)
                          : 0.0;
                      if (dividendPerDay <= 0) return const SizedBox.shrink();
                      return _InfoRow(
                        'Est. dividends',
                        '${money(dividendPerDay, currency)}/day',
                      );
                    },
                  ),
                  if (owned + clampedPercent >= 50 && owned < 50)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xff2dd4bf).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xff2dd4bf).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Color(0xff2dd4bf),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Majority stake — grants takeover eligibility',
                              style: TextStyle(
                                color: Color(0xff2dd4bf),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
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
            _AppBtn(
              variant: _BtnVariant.plain,
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            _AppBtn(
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
        final acquiredFleet = game.fleetForAirline(airlineId);
        final acquiredRoutes = game.routesForAirline(airlineId);
        return _GlassDialog(
          title: Text('Acquire ${airline.name}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  if (acquiredFleet.isNotEmpty || acquiredRoutes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ExpansionTile(
                      title: const Text(
                        'Assets acquired',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      children: [
                        if (acquiredFleet.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.only(top: 6, bottom: 2),
                            child: Text(
                              'Aircraft',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xff9e9e9e),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          ...acquiredFleet.map((ac) {
                            final t = aircraftTypesById[ac.typeId];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      t?.displayName ?? ac.typeId,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Text(
                                    '${ac.condition.toStringAsFixed(0)}% cond',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xff9e9e9e),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        if (acquiredRoutes.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.only(top: 8, bottom: 2),
                            child: Text(
                              'Routes',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xff9e9e9e),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          ...acquiredRoutes.map((r) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${r.originIata} →${r.destinationIata}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Text(
                                    '${money(r.dailyProfit, currency)}/day',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: r.dailyProfit >= 0
                                          ? const Color(0xff3af083)
                                          : const Color(0xffff6b6b),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ],
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
            _AppBtn(
              variant: _BtnVariant.plain,
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            _AppBtn(
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
              child: const Text('Acquire'),
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
    return _GlassDialog(
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
                    ? '${origin.city} →${destination.city}'
                    : '${latestRoute.originIata} →${latestRoute.destinationIata}',
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
                        backgroundColor: const Color(0xff2e2e2e),
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
        _AppBtn(
          variant: _BtnVariant.plain,
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
  String? aircraftError;
  var confirmDelete = false;
  var _showBuyShop = false;
  var _buyShopManufacturer = 'All';
  String? _buyShopError;

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
            index: RouteIndex.build(
              widget.game.routes.values,
              widget.game.airlines.values,
            ),
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
    return _GlassDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${route.originIata} → ${route.destinationIata}'),
          if (origin != null && destination != null)
            Text(
              '${origin.city} → ${destination.city}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: Color(0xff9e9e9e),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── P&L preview (load factors + financials) ──
              _RoutePreviewCard(
                current: route,
                preview: previewEconomics?.route,
                currency: widget.currency,
              ),
              const SizedBox(height: 12),

              // ── Aircraft assignment ──
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
                        style: TextStyle(color: Color(0xff9e9e9e)),
                      )
                    else ...[
                      Text(
                        '${ac.name} · ${type?.displayName ?? ac.typeId}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${ac.condition.toStringAsFixed(0)}% condition · ${type == null ? '' : '${type.rangeKm} km range'}',
                        style: const TextStyle(color: Color(0xff9e9e9e)),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _AppBtn(
                            variant: _BtnVariant.ghost,
                            onPressed: () {
                              widget.game.assignAircraftToRoute(ac.id, null);
                              setState(() => aircraftError = null);
                            },
                            icon: const Icon(Icons.link_off),
                            child: const Text('Unassign'),
                          ),
                          _AppBtn(
                            variant: _BtnVariant.ghost,
                            onPressed: () {
                              try {
                                widget.game.sellAircraft(ac.id);
                                setState(() => aircraftError = null);
                              } catch (e) {
                                setState(() => aircraftError = e.toString());
                              }
                            },
                            icon: const Icon(Icons.sell),
                            child: const Text('Sell aircraft'),
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
                    _AppBtn(
                      variant: _BtnVariant.ghost,
                      onPressed: () => setState(() {
                        _showBuyShop = !_showBuyShop;
                        _buyShopError = null;
                      }),
                      icon: Icon(_showBuyShop ? Icons.close : Icons.add),
                      child: Text(_showBuyShop ? 'Cancel' : 'Buy New Plane'),
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

              // ── Aircraft shop (shown below assignment card) ──
              if (_showBuyShop && origin != null && destination != null) ...[
                const SizedBox(height: 12),
                () {
                  final allShopAircraft = aircraftTypes
                      .where((t) => t.yearIntroduced <= currentYear)
                      .toList()
                    ..sort((a, b) {
                      final aOk = a.rangeKm >= route.distanceKm &&
                          canAirportHandleAircraft(origin, a) &&
                          canAirportHandleAircraft(destination, a);
                      final bOk = b.rangeKm >= route.distanceKm &&
                          canAirportHandleAircraft(origin, b) &&
                          canAirportHandleAircraft(destination, b);
                      if (aOk != bOk) return aOk ? -1 : 1;
                      return a.purchasePrice.compareTo(b.purchasePrice);
                    });
                  final manufacturers = <String>{
                    'All',
                    ...allShopAircraft.map((t) => t.manufacturer),
                  }.toList()
                    ..sort((a, b) {
                      if (a == 'All') return -1;
                      if (b == 'All') return 1;
                      return a.toLowerCase().compareTo(b.toLowerCase());
                    });
                  final shopTypes = _buyShopManufacturer == 'All'
                      ? allShopAircraft
                      : allShopAircraft
                          .where((t) => t.manufacturer == _buyShopManufacturer)
                          .toList();
                  return _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Buy a new aircraft',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        _InlineAircraftShop(
                          types: shopTypes,
                          manufacturers: manufacturers,
                          selectedManufacturer: _buyShopManufacturer,
                          selectedTypeId: null,
                          distanceKm: route.distanceKm,
                          cash: widget.game.player.cashUSD,
                          origin: origin,
                          destination: destination,
                          currency: widget.currency,
                          onManufacturerChanged: (m) =>
                              setState(() => _buyShopManufacturer = m),
                          onSelected: (type) {
                            try {
                              final ac = widget.game.buyAircraft(type.id);
                              widget.game.assignAircraftToRoute(
                                  ac.id, route.id);
                              setState(() {
                                _showBuyShop = false;
                                _buyShopError = null;
                                aircraftError = null;
                              });
                            } catch (e) {
                              setState(() => _buyShopError =
                                  e.toString().replaceFirst('Bad state: ', ''));
                            }
                          },
                        ),
                        if (_buyShopError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _buyShopError!,
                              style:
                                  const TextStyle(color: Color(0xffff6b6b)),
                            ),
                          ),
                      ],
                    ),
                  );
                }(),
              ],

              // ── Pricing section ──
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pricing',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AppBtn(
                        small: true,
                        variant: _BtnVariant.plain,
                        onPressed: () => setState(() {
                          ecoController.text =
                              fareGuide.suggestedEconomy.toString();
                          if (hasBusiness) {
                            bizController.text =
                                fareGuide.suggestedBusiness.toString();
                          }
                        }),
                        icon: const Icon(Icons.refresh),
                        child: const Text('Reset'),
                      ),
                      const SizedBox(width: 6),
                      _AppBtn(
                        small: true,
                        variant: _BtnVariant.ghost,
                        onPressed: optimisationPreview == null
                            ? null
                            : () {
                                final result = widget.game.optimiseRoute(
                                  route.id,
                                );
                                setState(() {
                                  flights = result.flightsPerWeek;
                                  ecoController.text =
                                      result.priceEconomy.toString();
                                  bizController.text =
                                      result.priceBusiness.toString();
                                });
                              },
                        icon: const Icon(Icons.auto_fix_high),
                        child: Text(
                          optimisationPreview == null ? 'Optimised' : 'Optimise',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Flights per week: $flights',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${(flights / 7).toStringAsFixed(1)}/day',
                    style: const TextStyle(color: Color(0xff9e9e9e)),
                  ),
                ],
              ),
              Slider(
                value: flights.toDouble(),
                min: 1,
                max: 21,
                divisions: 20,
                label: '$flights/week',
                onChanged: (value) => setState(() => flights = value.round()),
              ),
              const SizedBox(height: 8),
              _AdaptiveRow(
                gap: 16,
                children: [
                  _FareSliderField(
                    controller: ecoController,
                    label: 'Economy (${widget.currency.code})',
                    suggested: fareGuide.suggestedEconomy,
                    maxFare: fareGuide.maxEconomy,
                    currency: widget.currency,
                    enabled: true,
                    onChanged: () => setState(() {}),
                  ),
                  _FareSliderField(
                    controller: bizController,
                    label: hasBusiness
                        ? 'Business (${widget.currency.code})'
                        : 'No business cabin',
                    suggested: fareGuide.suggestedBusiness,
                    maxFare: fareGuide.maxBusiness,
                    currency: widget.currency,
                    enabled: hasBusiness,
                    onChanged: () => setState(() {}),
                  ),
                ],
              ),
              const Divider(height: 20),

              // ── Route actions ──
              _AppBtn(
                variant: _BtnVariant.ghost,
                onPressed: () => widget.game.updateRouteSettings(
                  route.id,
                  isActive: !route.isActive,
                ),
                icon: Icon(
                  route.isActive ? Icons.pause_circle : Icons.play_circle,
                ),
                child: Text(route.isActive ? 'Suspend' : 'Resume'),
              ),
              const SizedBox(height: 8),
              _AppBtn(
                variant: _BtnVariant.danger,
                onPressed: () {
                  if (!confirmDelete) {
                    setState(() => confirmDelete = true);
                    return;
                  }
                  widget.game.deleteRoute(route.id);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.delete_outline),
                child: Text(
                  confirmDelete ? 'Confirm delete route' : 'Delete route',
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
        _AppBtn(
          variant: _BtnVariant.plain,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        _AppBtn(
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
        ? const Color(0xff9e9e9e)
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
                        color: Color(0xff9e9e9e),
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
        style: const TextStyle(color: Color(0xff9e9e9e), fontSize: 12),
      ),
    ],
  );
}

class _JourneyPill extends StatelessWidget {
  const _JourneyPill({
    required this.icon,
    required this.label,
    this.color = const Color(0xff9e9e9e),
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
    final routeCompatibleAircraft = aircraftTypes
        .where(
          (t) =>
              t.yearIntroduced <= gameYear &&
              t.rangeKm >= distance &&
              canAirportHandleAircraft(origin, t) &&
              canAirportHandleAircraft(destination, t),
        )
        .toList();
    final allShopAircraft = aircraftTypes
        .where((t) => t.yearIntroduced <= gameYear)
        .toList();
    allShopAircraft.sort((a, b) {
      final aCompatible = routeCompatibleAircraft.contains(a);
      final bCompatible = routeCompatibleAircraft.contains(b);
      if (aCompatible != bCompatible) return aCompatible ? -1 : 1;
      return a.purchasePrice.compareTo(b.purchasePrice);
    });
    if (type != null && !routeCompatibleAircraft.contains(type)) {
      type = null;
      buyNewAircraft = false;
    }
    final effectiveType =
        selectedAircraftType ?? (buyNewAircraft ? type : null);
    final guideType =
        effectiveType ?? routeCompatibleAircraft.firstOrNull ?? aircraftTypes.first;
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
            routeCompatibleAircraft.contains(type) &&
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
        <String>{'All', ...allShopAircraft.map((t) => t.manufacturer)}.toList()
          ..sort((a, b) {
            if (a == 'All') return -1;
            if (b == 'All') return 1;
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
    final shopAircraft = buyManufacturer == 'All'
        ? allShopAircraft
        : allShopAircraft
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
            index: RouteIndex.build(
              widget.game.routes.values,
              widget.game.airlines.values,
            ),
            globalFuelPrice: widget.game.globalFuelPrice,
            gameDay: widget.game.gameDay,
          );
    final canOptimise =
        hasAircraftForRoute &&
        pendingPurchaseValid &&
        !(routeCompatibleAircraft.isEmpty &&
            selectedAircraft == null &&
            buyNewAircraft) &&
        !(selectedAircraft != null && !selectedAircraftUsable) &&
        !sameAirport;

    return _GlassDialog(
      maxWidth: 920,
      title: const Text('New Route'),
      content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // ── Airport selection (side-by-side on wide, stacked on mobile) ──
              _AdaptiveRow(
                children: [
                  _AirportDropdown(
                    label: 'Origin',
                    value: origin,
                    onChanged: (a) => setState(() {
                      origin = a;
                      if (destination.iata == a.iata) {
                        destination =
                            _fallbackRouteDestination(a, widget.game);
                      }
                      error = null;
                    }),
                  ),
                  _AirportDropdown(
                    label: 'Destination',
                    value: destination,
                    onChanged: (a) => setState(() {
                      destination = a;
                      error = null;
                    }),
                  ),
                ],
              ),
              if (sameAirport) ...[
                const SizedBox(height: 8),
                const _InlineWarning(
                  'Origin and destination must be different airports.',
                ),
              ],
              const SizedBox(height: 12),

              // ── Route info card ──
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
              const SizedBox(height: 12),

              // ── Aircraft selection ──
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
              Align(
                alignment: Alignment.centerLeft,
                child: _AppBtn(
                  variant: _BtnVariant.plain,
                  onPressed: () =>
                      setState(() => showAircraftShop = !showAircraftShop),
                  icon: Icon(
                    showAircraftShop
                        ? Icons.expand_less
                        : Icons.add_circle_outline,
                  ),
child: Text(
                    showAircraftShop ? 'Hide aircraft shop' : 'Buy new aircraft',
                  )
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
              const SizedBox(height: 8),

              // ── Route optimiser ──
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
                            style: TextStyle(color: Color(0xff9e9e9e)),
                          ),
                        ],
                      ),
                    ),
                    _AppBtn(
                      onPressed: canOptimise ? _optimiseSetup : null,
                      icon: const Icon(Icons.auto_fix_high),
                      child: const Text('Optimise'),
                    ),
                  ],
                ),
              ),

              // ── Pricing section ──
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pricing',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  _AppBtn(
                    small: true,
                    variant: _BtnVariant.plain,
                    onPressed: () => setState(() {
                      ecoController.text =
                          fareGuide.suggestedEconomy.toString();
                      if (guideType.seatsBusiness > 0) {
                        bizController.text =
                            fareGuide.suggestedBusiness.toString();
                      }
                    }),
                    icon: const Icon(Icons.refresh),
                    child: Text(
                      'Reset  ${money(fareGuide.suggestedEconomy.toDouble(), widget.currency)} / ${guideType.seatsBusiness > 0 ? money(fareGuide.suggestedBusiness.toDouble(), widget.currency) : 'n/a'}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Flights per week slider
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Flights per week: $flights',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${(flights / 7).toStringAsFixed(1)}/day',
                    style: const TextStyle(color: Color(0xff9e9e9e)),
                  ),
                ],
              ),
              Slider(
                value: flights.toDouble(),
                min: 1,
                max: 21,
                divisions: 20,
                label: '$flights/week',
                onChanged: (v) => setState(() => flights = v.round()),
              ),
              const SizedBox(height: 8),

              // Economy + Business fares (side-by-side on wide, stacked on mobile)
              _AdaptiveRow(
                gap: 16,
                children: [
                  _FareSliderField(
                    controller: ecoController,
                    label: 'Economy (${widget.currency.code})',
                    suggested: fareGuide.suggestedEconomy,
                    maxFare: fareGuide.maxEconomy,
                    currency: widget.currency,
                    enabled: true,
                    onChanged: () => setState(() {}),
                  ),
                  _FareSliderField(
                    controller: bizController,
                    label: guideType.seatsBusiness > 0
                        ? 'Business (${widget.currency.code})'
                        : 'No business cabin',
                    suggested: fareGuide.suggestedBusiness,
                    maxFare: fareGuide.maxBusiness,
                    currency: widget.currency,
                    enabled: guideType.seatsBusiness > 0,
                    onChanged: () => setState(() {}),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── P&L preview ──
              _RoutePreviewCard(
                current: previewRoute,
                preview: previewEconomics?.route,
                currency: widget.currency,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: optimise,
                onChanged: (v) => setState(() => optimise = v ?? true),
                title: const Text('Auto-optimise after creation'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xffff6b6b)),
                  ),
                ),
            ],
          ),
        ),
      actions: [
        _AppBtn(
          variant: _BtnVariant.plain,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        _AppBtn(
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
            style: const TextStyle(color: Color(0xff9e9e9e)),
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
                style: const TextStyle(color: Color(0xff9e9e9e)),
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
                final hasRange = type.rangeKm >= distanceKm;
                final runwayOk =
                    canAirportHandleAircraft(origin, type) &&
                    canAirportHandleAircraft(destination, type);
                final enabled = canAfford && hasRange && runwayOk;
                final String? trailing;
                final Color? trailingColor;
                if (!hasRange) {
                  trailing = 'Short range';
                  trailingColor = const Color(0xffff9944);
                } else if (!runwayOk) {
                  trailing = 'Runway too short';
                  trailingColor = const Color(0xffff9944);
                } else if (!canAfford) {
                  trailing = "Can't afford";
                  trailingColor = const Color(0xffff7a7a);
                } else if (selectedTypeId == type.id) {
                  trailing = 'selected';
                  trailingColor = const Color(0xff7dd3fc);
                } else {
                  trailing = null;
                  trailingColor = null;
                }
                final imgAsset = _aircraftImageAsset(type.id);
                final isDesktop = MediaQuery.sizeOf(context).width >= 600;
                final Widget? leadingWidget = isDesktop
                    ? Container(
                        width: 76,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xff1a1a1a),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: imgAsset != null
                            ? Opacity(
                                opacity: enabled ? 1.0 : 0.35,
                                child: Image.asset(
                                  imgAsset,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Icon(
                                _aircraftCategoryIcon(type.category),
                                color: enabled
                                    ? const Color(0xff77c9ff)
                                    : const Color(0xff3a4252),
                                size: 22,
                              ),
                      )
                    : null;
                return _SelectableInfoRow(
                  selected: selectedTypeId == type.id,
                  enabled: enabled,
                  title: type.displayName,
                  subtitle:
                      '${_aircraftCategoryLabel(type.category)} · '
                      '${type.seatsEconomy}Y'
                      '${type.seatsBusiness > 0 ? '/${type.seatsBusiness}J' : ''}'
                      ' · ${type.rangeKm.toStringAsFixed(0)} km'
                      ' · ${type.minRunwayM} m rwy'
                      ' · ${type.cruiseSpeedKmh} km/h',
                  priceLabel: money(type.purchasePrice, currency),
                  trailing: trailing,
                  trailingColor: trailingColor,
                  leading: leadingWidget,
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
    this.priceLabel,
    this.trailing,
    this.trailingColor,
    this.leading,
  });

  final bool selected;
  final bool enabled;
  final String title;
  final String subtitle;
  final String? priceLabel;
  final String? trailing;
  final Color? trailingColor;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final border = selected ? const Color(0xff5db4ff) : const Color(0xff333333);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xff1c4268)
              : enabled
              ? const Color(0xff252525)
              : const Color(0xff1a1a1a),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 10),
            ] else ...[
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.airplanemode_active,
                color: enabled
                    ? selected
                          ? const Color(0xff74c0fc)
                          : const Color(0xff9e9e9e)
                    : const Color(0xff4a5263),
                size: 20,
              ),
              const SizedBox(width: 10),
            ],
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
                          ? const Color(0xff9e9e9e)
                          : const Color(0xff4f586a),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (priceLabel != null || trailing != null) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (priceLabel != null)
                    Text(
                      priceLabel!,
                      style: TextStyle(
                        color: enabled
                            ? Colors.white
                            : const Color(0xff5d6678),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (trailing != null)
                    Text(
                      trailing!,
                      style: TextStyle(
                        color: trailingColor ??
                            (enabled
                                ? const Color(0xff7dd3fc)
                                : const Color(0xffff7a7a)),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
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
        Text(title, style: const TextStyle(color: Color(0xff9e9e9e))),
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
  const _Card({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _cardSurface(context),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _hairline(context)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: _isLight(context) ? 0.04 : 0.20),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );
}

/// Renders children side-by-side on wide screens, stacked vertically on narrow.
class _AdaptiveRow extends StatelessWidget {
  const _AdaptiveRow({required this.children, this.gap = 12.0});
  final List<Widget> children;
  final double gap;

  static const double _breakpoint = 400.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _breakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                Expanded(child: children[i]),
                if (i < children.length - 1) SizedBox(width: gap),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1) SizedBox(height: gap),
            ],
          ],
        );
      },
    );
  }
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
      style: const TextStyle(color: Color(0xff9e9e9e)),
    ),
  );
}

class _RainbowCircleButton extends StatelessWidget {
  const _RainbowCircleButton({required this.currentColor, required this.onColorSelected, this.size = 36});
  final Color currentColor;
  final ValueChanged<Color> onColorSelected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Custom colour',
      child: InkWell(
        borderRadius: BorderRadius.circular(size),
        onTap: () => _showPicker(context),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const SweepGradient(
              colors: [
                Color(0xFFFF0000),
                Color(0xFFFFFF00),
                Color(0xFF00FF00),
                Color(0xFF00FFFF),
                Color(0xFF0000FF),
                Color(0xFFFF00FF),
                Color(0xFFFF0000),
              ],
            ),
            border: Border.all(color: const Color(0xff383838), width: 1),
          ),
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    Color pickerColor = currentColor;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff252525),
        title: const Text('Pick a colour', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (c) => pickerColor = c,
            enableAlpha: false,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onColorSelected(pickerColor);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }
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
          child: Text(label, style: const TextStyle(color: Color(0xff9e9e9e))),
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
  Widget build(BuildContext context) {
    final dark = !_isLight(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xf0121212) : const Color(0xf8ffffff),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.60 : 0.18),
            blurRadius: 40,
            spreadRadius: -4,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: child,
      ),
    );
  }
}

bool _isLight(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light;

Color _chromeSurface(BuildContext context) =>
    _isLight(context) ? const Color(0xeaffffff) : const Color(0xd4141414);


Color _cardSurface(BuildContext context) =>
    _isLight(context) ? const Color(0xfff8fafc) : const Color(0xff1e1e1e);

Color _subtleSurface(BuildContext context) => _isLight(context)
    ? const Color(0xffeef2f7)
    : Colors.white.withValues(alpha: 0.04);

Color _hairline(BuildContext context) => _isLight(context)
    ? const Color(0xffd3dce8)
    : Colors.white.withValues(alpha: 0.12);

Color _mutedText(BuildContext context) =>
    _isLight(context) ? const Color(0xff64748b) : const Color(0xff9e9e9e);

/// Glass-effect dialog wrapper.
///
/// Use instead of [AlertDialog] directly. Adds BackdropFilter blur and
/// frosted-glass surface decoration.
class _GlassDialog extends StatelessWidget {
  const _GlassDialog({this.title, this.content, this.actions, this.maxWidth, this.onClose});
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final double? maxWidth;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final dark = !_isLight(context);
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? 560),
        child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark ? const Color(0xec1c1c1c) : const Color(0xf5f8faff),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.07),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.60 : 0.18),
                  blurRadius: 48,
                  spreadRadius: -4,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, 22, onClose != null ? 8 : 24, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: DefaultTextStyle(
                            style: theme.dialogTheme.titleTextStyle ??
                                theme.textTheme.titleLarge!,
                            child: title!,
                          ),
                        ),
                        if (onClose != null)
                          IconButton(
                            onPressed: onClose,
                            icon: const Icon(Icons.close),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Cancel',
                          ),
                      ],
                    ),
                  ),
                if (content != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: content,
                    ),
                  ),
                if (actions != null && actions!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions!
                          .map((a) => Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: a,
                              ))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _Ticker extends StatefulWidget {
  const _Ticker({required this.game});
  final GameController game;

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> with SingleTickerProviderStateMixin {
  // Frame-driven approach: a Ticker fires every vsync, moves _xOffset by
  // (pxPerSec × dt) pixels.  Speed changes take effect on the very next frame.
  late final Ticker _frameTicker;
  late final ValueNotifier<double> _xNotifier;

  double _xOffset = double.nan; // nan = not yet laid out
  double _viewWidth = 0;
  double _textWidth = 0;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _xNotifier = ValueNotifier(9999); // start off-screen until layout fires
    _frameTicker = createTicker(_onFrameTick)..start();
  }

  @override
  void dispose() {
    _frameTicker.dispose();
    _xNotifier.dispose();
    super.dispose();
  }

  void _onFrameTick(Duration elapsed) {
    if (!mounted || _viewWidth == 0) return;

    final dt = _lastElapsed == Duration.zero
        ? 0.0
        : math.min(0.1, (elapsed - _lastElapsed).inMicroseconds / 1e6);
    _lastElapsed = elapsed;

    // First tick after layout: position text just off the right edge
    if (_xOffset.isNaN) {
      _xOffset = _viewWidth;
      _xNotifier.value = _xOffset;
      return;
    }

    final pxPerSec = _tickerPixelsPerSecond(widget.game.speed);
    _xOffset -= pxPerSec * dt;

    // Seamless loop: when the last character exits left, wrap back to right
    if (_textWidth > 0 && _xOffset < -_textWidth) {
      _xOffset += _viewWidth + _textWidth;
    }

    _xNotifier.value = _xOffset;
  }

  List<NewsTickerItem> get _items => widget.game.newsTicker.isEmpty
      ? const [
          NewsTickerItem(
            id: 'fallback',
            text: 'Welcome to Mighty Airline Empire!',
          ),
        ]
      : widget.game.newsTicker.take(10).toList(growable: false);

  void _openFeed() {
    final items = _items;
    final game = widget.game;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff151922),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Text(
                    'NEWS TICKER',
                    style: TextStyle(
                      color: Color(0xffffd166),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${items.length} items',
                    style: const TextStyle(
                      color: Color(0xff6b7280),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: Color(0xff6b7280),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xff2a2f3a), height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length,
                separatorBuilder: (_, idx) =>
                    const Divider(color: Color(0xff1e2330), height: 1),
                itemBuilder: (ctx, i) {
                  final item = items[i];
                  final isAlert =
                      item.playerRelated ||
                      item.severity == 'fleet' ||
                      item.severity == 'breaking';
                  final article = item.articleId == null
                      ? null
                      : game.newsArticles[item.articleId!];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isAlert
                            ? const Color(0xffff8c42)
                            : const Color(0xff4a90d9),
                      ),
                    ),
                    title: Text(
                      item.text,
                      style: TextStyle(
                        color: isAlert
                            ? const Color(0xffffd166)
                            : const Color(0xffc7d2e5),
                        fontSize: 13,
                        fontWeight: isAlert ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    trailing: article == null
                        ? null
                        : TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showHeraldArticle(
                                context,
                                game,
                                article,
                                readOnly: true,
                              );
                            },
                            child: const Text(
                              'Read →',
                              style: TextStyle(
                                color: Color(0xff4a90d9),
                                fontSize: 12,
                              ),
                            ),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    // Determine badge severity from the most urgent item
    final hasBreaking = items.any((i) => i.severity == 'breaking');
    final hasAlert = items.any(
      (i) => i.playerRelated || i.severity == 'fleet',
    );
    final tagText = hasBreaking
        ? 'BREAKING'
        : hasAlert
        ? 'FLEET ALERT'
        : 'NEWS';
    final tagColor = (hasBreaking || hasAlert)
        ? const Color(0xffff8c42)
        : const Color(0xffffd166);
    final tagBg = (hasBreaking || hasAlert)
        ? const Color(0xffffd166).withValues(alpha: 0.08)
        : Colors.transparent;

    // Build list of spans for the combined scrolling strip
    const separatorStyle = TextStyle(
      color: Color(0xff3a4252),
      fontSize: 13,
      fontWeight: FontWeight.w400,
    );
    final normalStyle = TextStyle(
      color: const Color(0xffc7d2e5).withValues(alpha: 0.85),
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    const alertStyle = TextStyle(
      color: Color(0xffffd166),
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );
    const articleSuffix = TextStyle(
      color: Color(0xff4a90d9),
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );

    List<InlineSpan> buildSpans() {
      final spans = <InlineSpan>[];
      for (var i = 0; i < items.length; i++) {
        if (i > 0) {
          spans.add(
            const TextSpan(text: '     ◆     ', style: separatorStyle),
          );
        }
        final item = items[i];
        final isAlert =
            item.playerRelated ||
            item.severity == 'fleet' ||
            item.severity == 'breaking';
        final hasArticle = item.articleId != null &&
            widget.game.newsArticles.containsKey(item.articleId);
        spans.add(
          TextSpan(
            text: isAlert ? '‼ ${item.text}' : item.text,
            style: isAlert ? alertStyle : normalStyle,
          ),
        );
        if (hasArticle) {
          spans.add(
            const TextSpan(text: '  [Read →]', style: articleSuffix),
          );
        }
      }
      // Pad end so the last item scrolls fully off before loop
      spans.add(const TextSpan(text: '          ', style: separatorStyle));
      return spans;
    }

    return GestureDetector(
      onTap: _openFeed,
      child: Container(
        height: 42,
        color: const Color(0xff111111),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            GestureDetector(
              onTap: _openFeed,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tagBg,
                  border: Border.all(color: tagColor.withValues(alpha: 0.45)),
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
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewWidth = constraints.maxWidth;
                    final spans = buildSpans();
                    final combinedSpan = TextSpan(children: spans);
                    final tp = TextPainter(
                      text: combinedSpan,
                      maxLines: 1,
                      textDirection: TextDirection.ltr,
                    )..layout();
                    final textWidth = tp.width;
                    tp.dispose();
                    // Update frame-ticker dimensions (safe to mutate in build —
                    // no setState, just feeding numbers to the ticker loop).
                    _viewWidth = viewWidth;
                    _textWidth = textWidth;
                    return AnimatedBuilder(
                      animation: _xNotifier,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(_xNotifier.value, 0),
                        child: child,
                      ),
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        maxWidth: double.infinity,
                        child: RichText(
                          text: combinedSpan,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _tickerPixelsPerSecond(int speed) {
    if (speed >= 14400) return 1200;
    if (speed >= 3600) return 700;
    if (speed >= 1200) return 400;
    if (speed >= 300) return 250;
    return 160;
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
    builder: (dialogContext) => Theme(
      // Herald dialog is always a cream/parchment surface — force light
      // brightness so adaptive buttons (ghost etc.) pick dark text/border.
      data: Theme.of(dialogContext).copyWith(brightness: Brightness.light),
      child: AlertDialog(
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
                              _AppBtn(
                                onPressed: () {
                                  game.startMaintenance(
                                    article.actionAircraftId!,
                                    MaintenanceTier.standard,
                                  );
                                  dismiss(dialogContext);
                                },
                                icon: const Icon(Icons.build),
                                child: Text(
                                  'Send to maintenance (\$${_formatCost(article.actionMaintenanceCost ?? 0)} USD)',
                                )
                              ),
                              const SizedBox(height: 8),
                              _AppBtn(
                                variant: _BtnVariant.ghost,
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
                                child: const Text(
                                  'Always maintain aircraft with issues',
                                )
                              ),
                              const SizedBox(height: 8),
                              _AppBtn(
                                variant: _BtnVariant.danger,
                                onPressed: () {
                                  game.keepIssueAircraftFlying(
                                    article.actionAircraftId!,
                                  );
                                  dismiss(dialogContext);
                                },
                                icon: const Icon(Icons.warning_amber),
                                child: const Text('Keep flying'),
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
        _AppBtn(
          variant: _BtnVariant.plain,
          onPressed: () => dismiss(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
    ),
  );
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}

// ════════════════════════════════════════════════════════════
//  Design system
// ════════════════════════════════════════════════════════════

enum _BtnVariant { primary, ghost, tonal, plain, danger }

/// Fully custom button — no Material ripple, Apple-style press animation.
class _AppBtn extends StatefulWidget {
  const _AppBtn({
    required this.child,
    required this.onPressed,
    this.icon,
    this.variant = _BtnVariant.primary,
    this.small = false,
  });

  final Widget child;
  final Widget? icon;
  final VoidCallback? onPressed;
  final _BtnVariant variant;
  final bool small;

  @override
  State<_AppBtn> createState() => _AppBtnState();
}

class _AppBtnState extends State<_AppBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final dark = !_isLight(context);
    final disabled = widget.onPressed == null;
    final small = widget.small;

    Color bg;
    Color fg;
    List<BoxShadow> shadows = const [];
    BoxBorder? border;

    switch (widget.variant) {
      case _BtnVariant.primary:
        const base = Color(0xff0a84ff);
        bg = disabled
            ? (dark ? const Color(0xff2a2a2a) : const Color(0xffd0d0d0))
            : _pressed
            ? const Color(0xff006ed6)
            : base;
        fg = disabled
            ? (dark ? const Color(0xff555555) : const Color(0xff888888))
            : Colors.white;
        if (!disabled)
          shadows = [
            BoxShadow(
              color: const Color(0xff0a84ff).withValues(alpha: 0.32),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ];

      case _BtnVariant.ghost:
        bg = _pressed
            ? (dark
                  ? Colors.white.withValues(alpha: 0.11)
                  : Colors.black.withValues(alpha: 0.07))
            : (dark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.04));
        fg = disabled
            ? _mutedText(context)
            : (dark ? Colors.white : const Color(0xff1c1c1e));
        border = Border.all(
          color: dark
              ? Colors.white.withValues(alpha: disabled ? 0.07 : 0.14)
              : Colors.black.withValues(alpha: disabled ? 0.06 : 0.11),
        );

      case _BtnVariant.tonal:
        const accent = Color(0xff0a84ff);
        bg = _pressed
            ? accent.withValues(alpha: 0.22)
            : accent.withValues(alpha: 0.14);
        fg = disabled ? _mutedText(context) : accent;

      case _BtnVariant.plain:
        bg = _pressed
            ? (dark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.04))
            : Colors.transparent;
        fg = disabled ? _mutedText(context) : const Color(0xff0a84ff);

      case _BtnVariant.danger:
        const base = Color(0xffff453a);
        bg = disabled
            ? (dark ? const Color(0xff3a1a1a) : const Color(0xfff0c0bc))
            : _pressed
            ? const Color(0xffdc2626)
            : base;
        fg = disabled
            ? (dark ? const Color(0xff5a2828) : const Color(0xffb07070))
            : Colors.white;
        if (!disabled)
          shadows = [
            BoxShadow(
              color: const Color(0xffff453a).withValues(alpha: 0.30),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ];
    }

    final hPad = small ? 13.0 : 20.0;
    final vPad = small ? 8.0 : 12.0;
    final textSize = small ? 13.0 : 15.0;
    final iconSize = small ? 15.0 : 17.0;
    final gap = small ? 5.0 : 7.0;

    Widget content = DefaultTextStyle.merge(
      style: TextStyle(
        color: fg,
        fontSize: textSize,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.2,
      ),
      child: widget.child,
    );

    if (widget.icon != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme(
            data: IconThemeData(color: fg, size: iconSize),
            child: widget.icon!,
          ),
          SizedBox(width: gap),
          content,
        ],
      );
    }

    return MouseRegion(
      cursor: disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
        onTapUp: disabled
            ? null
            : (_) {
                setState(() => _pressed = false);
                widget.onPressed!();
              },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: (_pressed && !disabled) ? 0.965 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: border,
              boxShadow: _pressed ? const [] : shadows,
            ),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}
