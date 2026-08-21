/// Typed domain models shared between the Recycle Vision app and backend.
///
/// The server is authoritative for points; these models are the contract.
library;

import 'confidence_policy.dart';
import 'waste_class.dart';

/// Authenticated application user.
class AppUser {
  final String id;
  final String studentCode;
  final String name;
  final String facultyId;
  final String facultyName;
  final int points;

  const AppUser({
    required this.id,
    required this.studentCode,
    required this.name,
    required this.facultyId,
    required this.facultyName,
    required this.points,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        studentCode: json['studentCode'] as String,
        name: json['name'] as String,
        facultyId: json['facultyId'] as String,
        facultyName: json['facultyName'] as String,
        points: json['points'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'studentCode': studentCode,
        'name': name,
        'facultyId': facultyId,
        'facultyName': facultyName,
        'points': points,
      };

  AppUser copyWith({int? points}) => AppUser(
        id: id,
        studentCode: studentCode,
        name: name,
        facultyId: facultyId,
        facultyName: facultyName,
        points: points ?? this.points,
      );
}

/// AI prediction result. Mirrors `POST /api/v1/ai/predict`.
class Prediction {
  final String predictionId;
  final String operationId;
  final WasteClass predictedClass;
  final double confidence;
  final ConfidenceLevel confidenceLevel;
  final bool recyclable;
  final int destinationPosition;
  final int potentialPoints;
  final DateTime expiresAt;

  /// Reported by the server: `ai` when a real trained model ran, `demo` only
  /// if the backend explicitly served a development-fixture prediction.
  final String source;

  const Prediction({
    required this.predictionId,
    required this.operationId,
    required this.predictedClass,
    required this.confidence,
    required this.confidenceLevel,
    required this.recyclable,
    required this.destinationPosition,
    required this.potentialPoints,
    required this.expiresAt,
    required this.source,
  });

  factory Prediction.fromJson(Map<String, dynamic> json) => Prediction(
        predictionId: json['prediction_id'] as String,
        operationId: json['operation_id'] as String,
        predictedClass: WasteClassX.fromApi(json['predicted_class'] as String),
        confidence: (json['confidence'] as num).toDouble(),
        confidenceLevel:
            ConfidenceLevel.fromApi(json['confidence_level'] as String),
        recyclable: json['recyclable'] as bool,
        destinationPosition: json['destination_position'] as int,
        potentialPoints: json['potential_points'] as int,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        source: json['source'] as String? ?? 'ai',
      );

  Map<String, dynamic> toJson() => {
        'prediction_id': predictionId,
        'operation_id': operationId,
        'predicted_class': predictedClass.apiValue,
        'confidence': confidence,
        'confidence_level': confidenceLevel.apiValue,
        'recyclable': recyclable,
        'destination_position': destinationPosition,
        'potential_points': potentialPoints,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'source': source,
      };
}

/// A physical EcoLoop station (one unit, four internal compartments).
class Station {
  final String id;
  final String stationCode;
  final String name;
  final String status;

  const Station({
    required this.id,
    required this.stationCode,
    required this.name,
    required this.status,
  });

  static const defaultStation =
      Station(id: 'st-001', stationCode: 'ST-001', name: 'EcoLoop Station', status: 'online');

  factory Station.fromJson(Map<String, dynamic> json) => Station(
        id: json['id'] as String,
        stationCode: json['station_code'] as String,
        name: json['name'] as String,
        status: json['status'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'station_code': stationCode,
        'name': name,
        'status': status,
      };
}

/// Deposit lifecycle status. `capture`/`analyzing` are the FINAL station-camera
/// phases (awaiting the frame / classifying it server-side); the machine
/// phases (`routing` → `moving` → `ready` → `detecting` → `measuring`) mirror
/// the physical stream over WebSocket; the last four values are terminal
/// outcomes the backend persists after the authoritative sensor event.
enum DepositStatus {
  capture('capture'),
  analyzing('analyzing'),
  pending('pending'),
  routing('routing'),
  moving('moving'),
  ready('ready'),
  detecting('detecting'),
  measuring('measuring'),
  confirmed('confirmed'),
  rejected('rejected'),
  cancelled('cancelled'),
  expired('expired');

  final String apiValue;
  const DepositStatus(this.apiValue);

  /// A terminal outcome: points were either awarded (confirmed) or the
  /// session closed without awarding anything.
  bool get isTerminal =>
      this == confirmed ||
      this == rejected ||
      this == cancelled ||
      this == expired;

  /// A live phase the machine is still working through (not yet terminal).
  bool get isLive => !isTerminal;

  /// A phase where the session is still waiting on the station camera / AI
  /// before any routing happened.
  bool get isCapturePhase => this == capture || this == analyzing;

  static DepositStatus fromApi(String value) {
    for (final status in DepositStatus.values) {
      if (status.apiValue == value) return status;
    }
    throw ArgumentError.value(value, 'status', 'Unknown deposit status');
  }
}

/// Deposit session + result, created & validated server-side.
class Deposit {
  final String operationId;
  final String predictionId;
  final String stationId;
  final WasteClass predictedClass;
  final int expectedPosition;
  final int actualPosition;
  final double weightGrams;
  final bool mechanicalConfirmed;
  final int potentialPoints;
  final int pointsAwarded;
  final DepositStatus status;
  final String? rejectReason;
  final DateTime expiresAt;

  /// AI classification confidence [0..1]; 0 until the station camera frame is
  /// classified (capture/analyzing phases). Backend-provided, UI-only display.
  final double confidence;

  /// Classification band (`high`/`medium`/`low`); empty until classified.
  final ConfidenceLevel? confidenceLevel;

  const Deposit({
    required this.operationId,
    required this.predictionId,
    required this.stationId,
    required this.predictedClass,
    required this.expectedPosition,
    required this.actualPosition,
    required this.weightGrams,
    required this.mechanicalConfirmed,
    required this.potentialPoints,
    required this.pointsAwarded,
    required this.status,
    required this.expiresAt,
    this.rejectReason,
    this.confidence = 0,
    this.confidenceLevel,
  });

  factory Deposit.fromJson(Map<String, dynamic> json) => Deposit(
        operationId: json['operation_id'] as String,
        predictionId: json['prediction_id'] as String,
        stationId: json['station_id'] as String,
        predictedClass:
            WasteClassX.fromApi(json['predicted_class'] as String),
        expectedPosition: json['expected_position'] as int,
        actualPosition: json['actual_position'] as int,
        weightGrams: (json['weight_g'] as num).toDouble(),
        mechanicalConfirmed: json['mechanical_confirmed'] as bool,
        potentialPoints: json['potential_points'] as int,
        pointsAwarded: json['points_awarded'] as int,
        status: DepositStatus.fromApi(json['status'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
        rejectReason: json['reject_reason'] as String?,
        confidence: (json['confidence'] as num? ?? 0).toDouble(),
        confidenceLevel: json['confidence_level'] == null ||
                (json['confidence_level'] as String).isEmpty
            ? null
            : ConfidenceLevel.fromApi(json['confidence_level'] as String),
      );

  Map<String, dynamic> toJson() => {
        'operation_id': operationId,
        'prediction_id': predictionId,
        'station_id': stationId,
        'predicted_class': predictedClass.apiValue,
        'expected_position': expectedPosition,
        'actual_position': actualPosition,
        'weight_g': weightGrams,
        'mechanical_confirmed': mechanicalConfirmed,
        'potential_points': potentialPoints,
        'points_awarded': pointsAwarded,
        'status': status.apiValue,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        if (rejectReason != null) 'reject_reason': rejectReason,
        'confidence': confidence,
        if (confidenceLevel != null)
          'confidence_level': confidenceLevel!.apiValue,
      };
}

/// One line in the user's recycling history.
class WasteHistoryEvent {
  final String id;
  final String operationId;
  final String stationId;
  final WasteClass predictedClass;
  final double weightGrams;
  final int pointsAwarded;
  final DateTime createdAt;

  const WasteHistoryEvent({
    required this.id,
    required this.operationId,
    required this.stationId,
    required this.predictedClass,
    required this.weightGrams,
    required this.pointsAwarded,
    required this.createdAt,
  });

  factory WasteHistoryEvent.fromJson(Map<String, dynamic> json) =>
      WasteHistoryEvent(
        id: json['id'] as String,
        operationId: json['operation_id'] as String,
        stationId: json['station_id'] as String,
        predictedClass: WasteClassX.fromApi(json['predicted_class'] as String),
        weightGrams: (json['weight_g'] as num).toDouble(),
        pointsAwarded: json['points_awarded'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'operation_id': operationId,
        'station_id': stationId,
        'predicted_class': predictedClass.apiValue,
        'weight_g': weightGrams,
        'points_awarded': pointsAwarded,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}

/// Material breakdown for the impact screen.
class WasteBreakdown {
  final WasteClass wasteClass;
  final double kg;
  final int count;

  const WasteBreakdown({
    required this.wasteClass,
    required this.kg,
    required this.count,
  });

  factory WasteBreakdown.fromJson(Map<String, dynamic> json) => WasteBreakdown(
        wasteClass: WasteClassX.fromApi(json['waste_class'] as String),
        kg: (json['kg'] as num).toDouble(),
        count: json['count'] as int,
      );

  Map<String, dynamic> toJson() => {
        'waste_class': wasteClass.apiValue,
        'kg': kg,
        'count': count,
      };
}

/// Aggregate impact statistics.
class Impact {
  final int totalPoints;
  final double recycledKg;
  final int itemsRecycled;
  final double co2SavedKg;
  final List<WasteBreakdown> breakdown;

  const Impact({
    required this.totalPoints,
    required this.recycledKg,
    required this.itemsRecycled,
    required this.co2SavedKg,
    required this.breakdown,
  });

  factory Impact.fromJson(Map<String, dynamic> json) => Impact(
        totalPoints: json['total_points'] as int,
        recycledKg: (json['recycled_kg'] as num).toDouble(),
        itemsRecycled: json['items_recycled'] as int,
        co2SavedKg: (json['co2_saved_kg'] as num).toDouble(),
        breakdown: (json['breakdown'] as List<dynamic>)
            .map((e) => WasteBreakdown.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'total_points': totalPoints,
        'recycled_kg': recycledKg,
        'items_recycled': itemsRecycled,
        'co2_saved_kg': co2SavedKg,
        'breakdown': breakdown.map((e) => e.toJson()).toList(),
      };
}

/// One leaderboard entry (student or faculty).
class LeaderEntry {
  final String id;
  final String name;
  final String detail;
  final int points;

  const LeaderEntry({
    required this.id,
    required this.name,
    required this.detail,
    required this.points,
  });

  factory LeaderEntry.fromJson(Map<String, dynamic> json) => LeaderEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        detail: json['detail'] as String,
        points: json['points'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'detail': detail,
        'points': points,
      };
}

/// Active or completed recycling challenge.
class Challenge {
  final String id;
  final String title;
  final String description;
  final String themeEmoji;
  final double targetKg;
  final double currentKg;
  final int rewardPoints;
  final bool completed;
  final bool active;

  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.themeEmoji,
    required this.targetKg,
    required this.currentKg,
    required this.rewardPoints,
    required this.completed,
    required this.active,
  });

  double get progress => targetKg <= 0 ? 0 : (currentKg / targetKg).clamp(0, 1);

  factory Challenge.fromJson(Map<String, dynamic> json) => Challenge(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        themeEmoji: json['theme_emoji'] as String? ?? '♻️',
        targetKg: (json['target_kg'] as num).toDouble(),
        currentKg: (json['current_kg'] as num).toDouble(),
        rewardPoints: json['reward_points'] as int,
        completed: json['completed'] as bool,
        active: json['active'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'theme_emoji': themeEmoji,
        'target_kg': targetKg,
        'current_kg': currentKg,
        'reward_points': rewardPoints,
        'completed': completed,
        'active': active,
      };
}