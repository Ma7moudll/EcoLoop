import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/app_theme.dart';
import '../../../widgets/class_style.dart';
import '../../../widgets/station/compartment_status.dart';
import 'station_guide_screen.dart';

/// Prediction result for one scanned frame. Behavior is bounded by the exact
/// confidence policy (0.80 / 0.50):
///   HIGH   → auto-continue to the station.
///   MEDIUM → offer both "Retake" and "Manual confirm" (still requires the
///            physical drop, so no points are invented client-side).
///   LOW    → retake only; the AI could not be sure enough to route.
class PredictionResultScreen extends ConsumerWidget {
  final Prediction prediction;

  const PredictionResultScreen({super.key, required this.prediction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clsStyle = styleForClass(prediction.predictedClass);
    final conf = ConfidenceStyle.of(prediction.confidenceLevel);
    final compartment = compartmentForClass(prediction.predictedClass);
    final isHigh = prediction.confidenceLevel == ConfidenceLevel.high;
    final isMedium = prediction.confidenceLevel == ConfidenceLevel.medium;

    return Scaffold(
      backgroundColor: const Color(0xFFEDF4F0),
      appBar: AppBar(
        title: const Text('Result'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // Confidence banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: conf.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    isHigh
                        ? Icons.check_circle
                        : isMedium
                            ? Icons.info_outline
                            : Icons.warning_amber_rounded,
                    size: 18,
                    color: conf.color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      conf.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: conf.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Class card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: clsStyle.soft, width: 1.4),
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: clsStyle.soft,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(clsStyle.icon, size: 30, color: clsStyle.color),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    prediction.predictedClass.probableLabel,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${percent(prediction.confidence)} confidence',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Compartment insight
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.appSurface,
                borderRadius: BorderRadius.circular(AppRadii.medium),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  Text(
                    compartment.isRecyclable
                        ? 'This item routes to Compartment #${compartment.position}'
                        : 'Not recyclable — routes to Compartment #${compartment.position}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 10),
                  CompartmentRack(openClass: prediction.predictedClass),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (prediction.confidenceLevel == ConfidenceLevel.medium) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.yellow.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lightbulb_outline,
                        size: 16, color: Color(0xFF8a5a00)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Medium confidence — re-scan in good lighting, or '
                        'continue with manual confirmation at the station.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF6b4a00)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (prediction.confidenceLevel == ConfidenceLevel.low) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: AppColors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Low confidence — please retake the photo. The item '
                        'cannot be routed reliably.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (isHigh)
              ElevatedButton(
                onPressed: () => _next(context),
                child: const Text('Continue to station'),
              )
            else if (isMedium) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _retake(context),
                      child: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _next(context),
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              ),
            ] else
              ElevatedButton(
                onPressed: () => _retake(context),
                child: const Text('Retake photo'),
              ),
          ],
        ),
      ),
    );
  }

  void _next(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StationGuideScreen(prediction: prediction),
      ),
    );
  }

  void _retake(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}