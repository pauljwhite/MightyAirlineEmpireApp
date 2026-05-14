import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mighty_airline_empire_app/main.dart';

void main() {
  testWidgets('routes panel new route creates an active journey', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
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
    expect(find.text('Aircraft compatible'), findsOneWidget);
    expect(find.textContaining('Create + buy'), findsOneWidget);
    expect(find.text('Create inactive route'), findsNothing);

    await tester.tap(find.textContaining('Create + buy'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Create route'), findsNothing);

    await tester.tap(find.byTooltip('Routes'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('LHR ->'), findsWidgets);
    expect(find.text('No aircraft'), findsNothing);
  });
}
