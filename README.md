# Mighty Airline Empire App

Native Flutter port of the existing React/Vite game in `pauljwhite/Game`.

The web app remains the canonical reference while this repository moves the game toward native iOS, iPadOS, Android, and macOS builds. This is intentionally a native Flutter/Dart app, not a WebView wrapper.

## Current milestone

- Flutter project scaffolded for iOS, Android, and macOS.
- Airport and aircraft catalogues imported from the web game into Dart fixtures.
- Core helper parity added for airport search, currency formatting, geodesic distance, and first-pass destination demand.
- Native shell started with matching dark UI language, top-bar airport search, currency selector, speed selector with icon pause, map airport hit testing, animated panels, passenger destination accordion, and ticker placement above the map but below panels.
- Dart tests cover imported data, airport search, distance, demand ordering, and currency formatting.

## Verification

```sh
flutter analyze
flutter test
flutter build macos --debug
```

## Reference source

The gameplay/UI reference remains the web app in `pauljwhite/Game`. Future work should continue porting the engines, state model, route optimiser, AI, persistence/import/export, finance, fleet, route creation/editing, and map rendering from that source into Dart with parity tests.
