import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mighty_airline_empire_app/main.dart';

void main() {
  testWidgets('routes panel new route creates an active journey', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MightyAirlineEmpireApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Start new airline'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('1x'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'New Route').first);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Create route'), findsOneWidget);
    expect(find.text('Origin'), findsWidgets);
    expect(find.text('Destination'), findsWidgets);
    expect(find.text('No aircraft selected'), findsOneWidget);
    expect(find.text('Create inactive route'), findsOneWidget);
    expect(find.textContaining('Create + buy'), findsNothing);

    final buyAircraftButton = find.widgetWithText(
      TextButton,
      'Buy new aircraft',
    );
    await tester.ensureVisible(buyAircraftButton);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(buyAircraftButton);
    await tester.pump(const Duration(milliseconds: 300));

    final aircraftChoice = find.textContaining('707-120').first;
    await tester.ensureVisible(aircraftChoice);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(
      find.ancestor(of: aircraftChoice, matching: find.byType(InkWell)).first,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Aircraft compatible'), findsOneWidget);
    expect(find.textContaining('Create + buy'), findsOneWidget);

    final createButtonText = find.textContaining('Create + buy').first;
    final createButton = find
        .ancestor(of: createButtonText, matching: find.byType(FilledButton))
        .first;
    await tester.ensureVisible(createButtonText);
    await tester.pump(const Duration(milliseconds: 100));
    final filledButton = tester.widget<FilledButton>(createButton);
    expect(filledButton.onPressed, isNotNull);
    await tester.tap(createButtonText, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 800));
    if (find.text('Create route').evaluate().isNotEmpty) {
      await tester.tap(
        find.widgetWithText(TextButton, 'Cancel'),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tester.tap(find.byTooltip('Routes'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('LHR ->'), findsWidgets);
    expect(find.text('No aircraft'), findsNothing);
  });
}
