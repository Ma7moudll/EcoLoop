/// # Recycle Vision — Shared Domain
///
/// Single source of truth for the domain models and policies used by both the
/// [server] backend and the [mobile] Flutter app:
///
/// - `WasteClass` (+ extension): the four coarse classes (`plastic`, `metal`,
///   `paper`, `other`). The AI prediction is the *only* source of the detected
///   class; no duplicate `material` concept exists.
/// - Confidence policy: exact thresholds 0.80 / 0.50 → HIGH / MEDIUM / LOW.
/// - Routing policy: the EcoLoop station is ONE unit with four internal
///   compartments (Blue/Yellow/Green/Grey) served by a movable mechanism
///   (carriage V1 / rotary chute V2). Routing maps
///   a predicted class → internal compartment position (1..4).
/// - Typed models: `AppUser`, `Prediction`, `Station`, `Deposit`,
///   `WasteHistoryEvent`, `Impact`, `LeaderEntry`, `Challenge`.
library;

export 'src/confidence_policy.dart';
export 'src/models.dart';
export 'src/routing_policy.dart';
export 'src/waste_class.dart';