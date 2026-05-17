import '../models/models.dart';

const currencyOptions = <CurrencyOption>[
  CurrencyOption(code: 'USD', symbol: r'$', name: 'US Dollar', rateFromUsd: 1),
  CurrencyOption(code: 'GBP', symbol: '£', name: 'Sterling', rateFromUsd: 0.79),
  CurrencyOption(code: 'EUR', symbol: '€', name: 'Euro', rateFromUsd: 0.92),
  CurrencyOption(
    code: 'RUB',
    symbol: '₽',
    name: 'Russian Ruble',
    rateFromUsd: 91,
  ),
  CurrencyOption(
    code: 'JPY',
    symbol: '¥',
    name: 'Japanese Yen',
    rateFromUsd: 151,
  ),
  CurrencyOption(
    code: 'CAD',
    symbol: r'C$',
    name: 'Canadian Dollar',
    rateFromUsd: 1.37,
  ),
  CurrencyOption(
    code: 'AUD',
    symbol: r'A$',
    name: 'Australian Dollar',
    rateFromUsd: 1.52,
  ),
  CurrencyOption(
    code: 'CHF',
    symbol: 'CHF ',
    name: 'Swiss Franc',
    rateFromUsd: 0.9,
  ),
  CurrencyOption(
    code: 'CNY',
    symbol: '¥',
    name: 'Chinese Yuan',
    rateFromUsd: 7.22,
  ),
];

/// Inserts thousands separators into the integer part of a numeric string,
/// e.g. "7164196.0" → "7,164,196.0".
String _addCommas(String s) {
  final dot = s.indexOf('.');
  final intPart = dot >= 0 ? s.substring(0, dot) : s;
  final decPart = dot >= 0 ? s.substring(dot) : '';
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0 && intPart[i - 1] != '-') {
      buf.write(',');
    }
    buf.write(intPart[i]);
  }
  return buf.toString() + decPart;
}

String money(num usd, CurrencyOption currency, {bool compact = true}) {
  final value = usd * currency.rateFromUsd;
  final abs = value.abs();
  var suffix = '';
  var shown = value.toDouble();
  if (compact && abs >= 1000000000) {
    shown = value / 1000000000;
    suffix = 'B';
  } else if (compact && abs >= 1000000) {
    shown = value / 1000000;
    suffix = 'M';
  } else if (compact && abs >= 1000) {
    shown = value / 1000;
    suffix = 'K';
  }
  final decimals = shown.abs() >= 100 || shown == shown.roundToDouble() ? 0 : 1;
  final formatted = _addCommas(shown.toStringAsFixed(decimals));
  return currency.symbol + formatted + suffix;
}
