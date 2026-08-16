import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../core/app_theme.dart';

/// Visual identity per waste class (icon + color + soft background).
class ClassStyle {
  final IconData icon;
  final Color color;
  final Color soft;
  const ClassStyle(this.icon, this.color, this.soft);
}

ClassStyle styleForClass(WasteClass cls) => switch (cls) {
      WasteClass.plastic => ClassStyle(Icons.water_drop, AppColors.blue, AppColors.blue.withValues(alpha: 0.12)),
      WasteClass.metal => ClassStyle(Icons.square_rounded, AppColors.yellow, AppColors.yellow.withValues(alpha: 0.16)),
      WasteClass.paper => ClassStyle(Icons.description_outlined, AppColors.green, AppColors.mint),
      WasteClass.other => ClassStyle(Icons.delete_outline, AppColors.muted, AppColors.line),
    };

/// Confidence-to-color used across scans, results, and history.
class ConfidenceStyle {
  final Color color;
  final String label;
  const ConfidenceStyle(this.color, this.label);

  static ConfidenceStyle of(ConfidenceLevel level) => switch (level) {
        ConfidenceLevel.high =>
          const ConfidenceStyle(AppColors.green, 'HIGH CONFIDENCE'),
        ConfidenceLevel.medium =>
          const ConfidenceStyle(AppColors.yellow, 'MEDIUM CONFIDENCE'),
        ConfidenceLevel.low => const ConfidenceStyle(AppColors.orange, 'LOW CONFIDENCE'),
      };
}

String percent(double value) => '${(value * 100).round()}%';

/// Nice icon for a stat row (points, kg, CO2, items).
IconData iconForKind(String kind) => switch (kind) {
      'points' => Icons.star_rounded,
      'kg' => Icons.scale_outlined,
      'co2' => Icons.cloud_outlined,
      'items' => Icons.inventory_2_outlined,
      _ => Icons.circle,
    };