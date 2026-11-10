/// Formats a coin amount the Bangladeshi way: 500, 1K, 50K, 1 Lac, 2.5 Crore.
String formatCoins(int n) {
  String trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  if (n >= 10000000) return '${trim(n / 10000000)} Crore';
  if (n >= 100000) return '${trim(n / 100000)} Lac';
  if (n >= 1000) return '${trim(n / 1000)}K';
  return '$n';
}

/// Keeps long player names from breaking the layout.
String shortName(String name, [int max = 9]) =>
    name.length <= max ? name : '${name.substring(0, max - 1)}…';
