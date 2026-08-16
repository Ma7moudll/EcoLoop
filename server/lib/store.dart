import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared/shared.dart';

import 'config.dart';
import 'json_file.dart';

/// A persisted user record. Password is stored as a salted PBKDF2 hash —
/// never as plaintext, never the session token.
class UserRecord {
  final AppUser user;
  final String email;
  final String passwordHash;
  final String passwordSalt;
  final List<String> completedChallengeIds;

  const UserRecord({
    required this.user,
    required this.email,
    required this.passwordHash,
    required this.passwordSalt,
    required this.completedChallengeIds,
  });

  factory UserRecord.fromJson(Map<String, dynamic> json) => UserRecord(
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
        email: json['email'] as String,
        passwordHash: json['password_hash'] as String,
        passwordSalt: json['password_salt'] as String,
        completedChallengeIds: (json['completed_challenges'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'email': email,
        'password_hash': passwordHash,
        'password_salt': passwordSalt,
        'completed_challenges': completedChallengeIds,
      };

  UserRecord copyWith({int? points, List<String>? completedChallengeIds}) =>
      UserRecord(
        user: user.copyWith(points: points),
        email: email,
        passwordHash: passwordHash,
        passwordSalt: passwordSalt,
        completedChallengeIds:
            completedChallengeIds ?? this.completedChallengeIds,
      );
}

/// A history row tied to a specific user.
class HistoryRow {
  final String userId;
  final WasteHistoryEvent event;

  const HistoryRow({required this.userId, required this.event});

  factory HistoryRow.fromJson(Map<String, dynamic> json) => HistoryRow(
        userId: json['user_id'] as String,
        event: WasteHistoryEvent.fromJson(json['event'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {'user_id': userId, 'event': event.toJson()};
}

/// Faculty definition used by the leaderboard and user registration.
class Faculty {
  final String id;
  final String name;

  const Faculty({required this.id, required this.name});

  factory Faculty.fromJson(Map<String, dynamic> json) => Faculty(
        id: json['id'] as String,
        name: json['name'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// Source of truth for all runtime state. Persisted as JSON files that are
/// written atomically. Not thread-safe by design — the shelf server is
/// single-isolate, tests call methods sequentially.
class DataStore {
  final String directory;
  ServerConfig? config;

  final Map<String, UserRecord> users = {};
  final Map<String, String> emailIndex = {};
  final Map<String, Prediction> predictions = {};
  final Map<String, Deposit> deposits = {};
  final Map<String, String> depositByPrediction = {};
  final List<HistoryRow> history = [];
  final List<Challenge> challenges = [];
  final List<Faculty> faculties = [];

  bool isSeeded = false;

  DataStore(this.directory);

  static Future<DataStore> create(String directory) async {
    final store = DataStore(directory);
    await store.load();
    return store;
  }

  void setConfig(ServerConfig c) {
    config = c;
  }

  String get _usersPath => p.join(directory, 'users.json');
  String get _predictionsPath => p.join(directory, 'predictions.json');
  String get _depositsPath => p.join(directory, 'deposits.json');
  String get _historyPath => p.join(directory, 'history.json');
  String get _challengesPath => p.join(directory, 'challenges.json');
  String get _facultiesPath => p.join(directory, 'faculties.json');
  String get _statePath => p.join(directory, 'state.json');

  Future<void> load() async {
    _loadJson(_usersPath, (data) {
      for (final entry in data.listOf('users')) {
        final record = UserRecord.fromJson(entry as Map<String, dynamic>);
        users[record.user.id] = record;
        emailIndex[record.email.toLowerCase()] = record.user.id;
      }
    });
    _loadJson(_predictionsPath, (data) {
      for (final entry in data.listOf('predictions')) {
        final pred = Prediction.fromJson(entry as Map<String, dynamic>);
        predictions[pred.predictionId] = pred;
      }
    });
    _loadJson(_depositsPath, (data) {
      for (final entry in data.listOf('deposits')) {
        final dep = Deposit.fromJson(entry as Map<String, dynamic>);
        deposits[dep.operationId] = dep;
        depositByPrediction[dep.predictionId] = dep.operationId;
      }
    });
    _loadJson(_historyPath, (data) {
      for (final entry in data.listOf('history')) {
        history.add(HistoryRow.fromJson(entry as Map<String, dynamic>));
      }
    });
    _loadJson(_challengesPath, (data) {
      for (final entry in data.listOf('challenges')) {
        challenges.add(Challenge.fromJson(entry as Map<String, dynamic>));
      }
    });
    _loadJson(_facultiesPath, (data) {
      for (final entry in data.listOf('faculties')) {
        faculties.add(Faculty.fromJson(entry as Map<String, dynamic>));
      }
    });
    _loadJson(_statePath, (data) {
      isSeeded = data['seeded'] as bool? ?? false;
    });
  }

  void _loadJson(String path, void Function(Map<String, dynamic>) apply) {
    final file = File(path);
    if (!file.existsSync()) return;
    try {
      apply(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt/unreadable store file: start from the (seeded) baseline and
      // overwrite on next save rather than crashing the server.
    }
  }

  Future<void> saveAll() async {
    final dir = directory;
    if (!dir.endsWith('/') && !Directory(dir).existsSync()) {
      Directory(dir).createSync(recursive: true);
    }
    await JsonFile(_usersPath).write({
      'users': users.values.map((e) => e.toJson()).toList(),
    });
    await JsonFile(_predictionsPath).write({
      'predictions': predictions.values.map((e) => e.toJson()).toList(),
    });
    await JsonFile(_depositsPath).write({
      'deposits': deposits.values.map((e) => e.toJson()).toList(),
    });
    await JsonFile(_historyPath).write({
      'history': history.map((e) => e.toJson()).toList(),
    });
    await JsonFile(_challengesPath).write({
      'challenges': challenges.map((e) => e.toJson()).toList(),
    });
    await JsonFile(_facultiesPath).write({
      'faculties': faculties.map((e) => e.toJson()).toList(),
    });
    await JsonFile(_statePath).write({'seeded': isSeeded});
  }

  // ---- lookups -----------------------------------------------------------

  UserRecord? userById(String id) => users[id];

  UserRecord? userByEmail(String email) {
    final id = emailIndex[email.toLowerCase()];
    return id == null ? null : users[id];
  }

  Faculty? facultyById(String id) =>
      faculties.where((f) => f.id == id).firstOrNull;

  List<HistoryRow> historyFor(String userId) =>
      history.where((h) => h.userId == userId).toList()
        ..sort((a, b) => b.event.createdAt.compareTo(a.event.createdAt));

  Challenge? challengeById(String id) =>
      challenges.where((c) => c.id == id).firstOrNull;

  // ---- mutations (persist immediately; the server is authoritative) ------

  Future<void> upsertUser(UserRecord record) async {
    users[record.user.id] = record;
    emailIndex[record.email.toLowerCase()] = record.user.id;
    await saveAll();
  }

  Future<void> addPrediction(Prediction prediction) async {
    predictions[prediction.predictionId] = prediction;
    await saveAll();
  }

  Future<void> addDeposit(Deposit deposit) async {
    deposits[deposit.operationId] = deposit;
    depositByPrediction[deposit.predictionId] = deposit.operationId;
    await saveAll();
  }

  Future<void> updateDeposit(Deposit deposit) async {
    deposits[deposit.operationId] = deposit;
    await saveAll();
  }

  Future<void> addHistory(HistoryRow row) async {
    history.add(row);
    await saveAll();
  }

  Future<void> completeChallenge(String userId, String challengeId) async {
    final record = users[userId];
    if (record == null) return;
    final ids = {...record.completedChallengeIds, challengeId}.toList();
    await upsertUser(record.copyWith(completedChallengeIds: ids));
  }

  /// Total points for a faculty (sum over its members).
  int facultyPoints(String facultyId) => users.values
      .where((r) => r.user.facultyId == facultyId)
      .fold(0, (sum, r) => sum + r.user.points);

  /// Completes a user's challenge if its target has been reached and returns
  /// the bonus points awarded (0 if already completed).
  Future<int> awardChallengeBonuses(String userId) async {
    final record = users[userId];
    if (record == null) return 0;
    final rows = historyFor(userId);
    var bonus = 0;
    final newlyCompleted = <String>[];

    for (final challenge in challenges) {
      if (record.completedChallengeIds.contains(challenge.id)) continue;
      if (!challenge.active) continue;
      final kg = _kgForClass(rows, _classFor(challenge));
      if (kg >= challenge.targetKg) {
        bonus += challenge.rewardPoints;
        newlyCompleted.add(challenge.id);
      }
    }

    if (newlyCompleted.isNotEmpty) {
      final ids = {...record.completedChallengeIds, ...newlyCompleted}.toList();
      await upsertUser(record.copyWith(
          points: record.user.points + bonus,
          completedChallengeIds: ids));
    }
    return bonus;
  }

  static double _kgForClass(List<HistoryRow> rows, WasteClass cls) {
    final grams = rows
        .where((h) => h.event.predictedClass == cls)
        .fold<double>(0, (sum, h) => sum + h.event.weightGrams);
    return round2(grams / 1000);
  }

  static WasteClass _classFor(Challenge challenge) {
    final title = challenge.title.toLowerCase();
    if (title.contains('plastic')) return WasteClass.plastic;
    if (title.contains('metal')) return WasteClass.metal;
    if (title.contains('paper')) return WasteClass.paper;
    return WasteClass.other;
  }

  /// Live view of a challenge with per-user progress.
  Challenge challengeViewFor(Challenge challenge, UserRecord user) {
    final rows = historyFor(user.user.id);
    final currentKg = _kgForClass(rows, _classFor(challenge));
    final completed = user.completedChallengeIds.contains(challenge.id) ||
        currentKg >= challenge.targetKg;
    return Challenge(
      id: challenge.id,
      title: challenge.title,
      description: challenge.description,
      themeEmoji: challenge.themeEmoji,
      targetKg: challenge.targetKg,
      currentKg: currentKg,
      rewardPoints: challenge.rewardPoints,
      completed: completed,
      active: challenge.active,
    );
  }
}