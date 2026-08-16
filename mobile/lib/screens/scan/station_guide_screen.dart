import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/app_theme.dart';
import '../../../widgets/class_style.dart';
import '../../../widgets/station/compartment_status.dart';
import 'deposit_screen.dart';

/// Tells the student exactly where to go: the single EcoLoop station, the
/// highlighted internal compartment, and the steps at the physical unit.
class StationGuideScreen extends ConsumerWidget {
  final Prediction prediction;

  const StationGuideScreen({super.key, required this.prediction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clsStyle = styleForClass(prediction.predictedClass);
    final compartment = compartmentForClass(prediction.predictedClass);

    return Scaffold(
      appBar: AppBar(title: const Text('Take it to the station')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // Station identity
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.deepGreen,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      color: AppColors.mint, size: 30),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EcoLoop Station',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'ST-001 · Ground floor · Near the entrance',
                          style: TextStyle(color: AppColors.mint, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.near_me, color: AppColors.mint, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: clsStyle.soft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(clsStyle.icon, size: 18, color: clsStyle.color),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Your item belongs in',
                          style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                        ),
                      ),
                      Text(
                        'Compart. #${compartment.position}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.fromHex(compartment.colorHex),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CompartmentRack(openClass: prediction.predictedClass),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 13, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Show the code to the station — the carriage moves '
                          'the item to its compartment automatically.',
                          style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.rewardBg,
                borderRadius: BorderRadius.circular(AppRadii.medium),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: AppColors.green, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      prediction.potentialPoints > 0
                          ? 'Worth ${prediction.potentialPoints} pts when deposited correctly.'
                          : 'Not worth points, but every item counts for impact.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.deepGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DepositScreen(prediction: prediction),
                  ),
                );
              },
              child: const Text("I'm at the station"),
            ),
          ],
        ),
      ),
    );
  }
}