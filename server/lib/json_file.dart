import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Minimal atomic JSON persistence: writes to a temp file then renames, so a
/// crash can never leave a half-written store file behind.
class JsonFile {
  final String path;

  JsonFile(this.path);

  Map<String, dynamic> read({Map<String, dynamic> fallback = const {}}) {
    final file = File(path);
    if (!file.existsSync()) return fallback;
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> write(Map<String, dynamic> data) async {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    if (file.existsSync()) await file.delete();
    await tmp.rename(path);
  }

  Future<void> deleteIfExists() async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
    final tmp = File('$path.tmp');
    if (tmp.existsSync()) await tmp.delete();
  }
}

/// Secure ID generator for predictions / operations / records.
class Ids {
  static const _chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  static final _rand = Random.secure();
  static final _unix = Random();

  static String _random(int length) =>
      List.generate(length, (_) => _chars[_rand.nextInt(_chars.length)]).join();

  static String prediction() => 'pred_${DateTime.now().millisecondsSinceEpoch}_${_random(6)}';

  static String operation() =>
      'OP-${(10000 + _unix.nextInt(90000))}${DateTime.now().millisecondsSinceEpoch % 1000}';

  static String record() => '${DateTime.now().millisecondsSinceEpoch}_${_random(6)}';

  static String login() => 'lt_${_random(24)}';
}

double round2(double v) => (v * 100).roundToDouble() / 100;

extension MapCursorX on Map<String, dynamic> {
  List<dynamic> listOf(String key) => this[key] as List<dynamic>? ?? const [];
}