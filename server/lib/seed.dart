import 'package:shared/shared.dart';

import 'auth.dart';
import 'json_file.dart';
import 'store.dart';

/// Seeds the store on first boot with demo users, faculties, challenges and a
/// starter history for the demo account. Seeding runs server-side only; the
/// app never mutates this data directly.
Future<void> seedStore(DataStore store) async {
  final faculties = [
    ('f-eng', 'Engineering'),
    ('f-sci', 'Science'),
    ('f-com', 'Commerce'),
    ('f-med', 'Medicine'),
    ('f-art', 'Arts'),
  ];
  store.faculties
    ..clear()
    ..addAll(faculties.map((f) => Faculty(id: f.$1, name: f.$2)));

  await store.saveAll();

  // Demo leaderboard students (visual baseline from the original prototype).
  final demoUsers = [
    ('Maya Chen', 'f-eng', 9240),
    ('Alex Morgan', 'f-eng', 8420),
    ('Samira Patel', 'f-sci', 7910),
    ('Jordan Lee', 'f-com', 6850),
    ('Taylor Kim', 'f-med', 6120),
  ];

  for (var i = 0; i < demoUsers.length; i++) {
    final item = demoUsers[i];
    final id = 'u-seed${i + 1}';
    final code = 'S${(10000 + i * 73).toString()}';
    final record = UserRecord(
      user: AppUser(
        id: id,
        studentCode: code,
        name: item.$1,
        facultyId: item.$2,
        facultyName: store.facultyById(item.$2)!.name,
        points: item.$3,
      ),
      email: '${item.$1.toLowerCase().replaceAll(' ', '.')}@demo.recycle',
      passwordHash: pbkdf2Hash('not-a-real-password-${item.$1}', 'seed'),
      passwordSalt: 'seed',
      completedChallengeIds: const [],
    );
    store.users[record.user.id] = record;
    store.emailIndex[record.email.toLowerCase()] = record.user.id;
  }

  // The demo account a tester can actually log in with.
  final demoId = 'u-demo';
  final demoRecord = UserRecord(
    user: AppUser(
      id: demoId,
      studentCode: 'S-2024-171',
      name: 'Alex Morgan',
      facultyId: 'f-eng',
      facultyName: 'Engineering',
      points: 0,
    ),
    email: 'demo@recycle.vision',
    passwordHash: pbkdf2Hash('demo123', 'demo-salt'),
    passwordSalt: 'demo-salt',
    completedChallengeIds: const [],
  );
  store.users[demoRecord.user.id] = demoRecord;
  store.emailIndex[demoRecord.email.toLowerCase()] = demoRecord.user.id;

  // Starter history for the demo account so impact/history are not empty.
  final now = DateTime.now().toUtc();
  final starter = [
    (WasteClass.plastic, 18.4, 5, Duration(hours: 1)),
    (WasteClass.metal, 22.1, 10, Duration(hours: 2)),
    (WasteClass.paper, 45.3, 5, Duration(hours: 3)),
    (WasteClass.plastic, 12.7, 5, Duration(hours: 26)),
    (WasteClass.plastic, 8.5, 5, Duration(hours: 48)),
    (WasteClass.other, 362.0, 0, Duration(hours: 72)),
    (WasteClass.paper, 30.2, 5, Duration(hours: 96)),
    (WasteClass.metal, 15.9, 10, Duration(hours: 120)),
  ];
  var bonus = 0;
  for (final (cls, g, pts, ago) in starter) {
    bonus += pts;
    store.history.add(HistoryRow(
      userId: demoId,
      event: WasteHistoryEvent(
        id: Ids.record(),
        operationId: Ids.operation(),
        stationId: 'st-001',
        predictedClass: cls,
        weightGrams: g,
        pointsAwarded: pts,
        createdAt: now.subtract(ago),
      ),
    ));
  }
  await store.upsertUser(demoRecord.copyWith(points: bonus));

  // Challenges.
  store.challenges
    ..clear()
    ..addAll([
      const Challenge(
        id: 'c-plastic-week',
        title: 'Plastic Week',
        description: 'Collect 10 kg of plastic',
        themeEmoji: '♻️',
        targetKg: 10,
        currentKg: 0,
        rewardPoints: 500,
        completed: false,
        active: true,
      ),
      const Challenge(
        id: 'c-metal-may',
        title: 'Metal May',
        description: 'Collect 3 kg of metal',
        themeEmoji: '🟨',
        targetKg: 3,
        currentKg: 0,
        rewardPoints: 250,
        completed: false,
        active: true,
      ),
      const Challenge(
        id: 'c-cardboard-craft',
        title: 'Cardboard Craft',
        description: 'Collect 5 kg of paper',
        themeEmoji: '📦',
        targetKg: 5,
        currentKg: 0,
        rewardPoints: 200,
        completed: false,
        active: true,
      ),
    ]);

  store.isSeeded = true;
  await store.saveAll();
}