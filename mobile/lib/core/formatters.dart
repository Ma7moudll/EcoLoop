/// User-facing display helpers shared across screens.
abstract final class Fmt {
  static String grams(double g) {
    if (g >= 1000) {
      final kg = g / 1000;
      return '${kg.toStringAsFixed(kg >= 10 ? 0 : 1)} kg';
    }
    return '${g.toStringAsFixed(g.truncateToDouble() == g ? 0 : 1)} g';
  }

  static String kilo(double kg) =>
      '${kg.toStringAsFixed(kg >= 10 ? 0 : 1)} kg';

  static String co2(double kg) => '${kg.toStringAsFixed(2)} kg';

  static String points(int pts) => '+$pts pts';

  static String shortDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${_month(local.month)} ${local.day}, ${_time(local)}';
  }

  static String _month(int m) =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];

  static String _time(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:$minute $suffix';
  }

  /// Percentage from a confidence value in [0, 1].
  static String confidencePercent(double c) => '${(c * 100).round()}%';

  static bool isFresh(DateTime at, {int withinHours = 24}) =>
      DateTime.now().difference(at) <= Duration(hours: withinHours);
}

/// Greeting based on time of day.
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}