import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/app_theme.dart';
import '../../../providers/shell_tab_provider.dart';
import '../../../widgets/class_style.dart';

/// Shown after a successfully confirmed deposit. Points + challenge bonus come
/// ONLY from the backend response; this screen never fabricates them.
class DepositSuccessScreen extends ConsumerWidget {
  final ({Deposit deposit, int pointsAwarded, int challengeBonus}) result;
  final Prediction prediction;

  const DepositSuccessScreen({
    super.key,
    required this.result,
    required this.prediction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deposit = result.deposit;
    final total = result.pointsAwarded + result.challengeBonus;
    final clsStyle = styleForClass(deposit.predictedClass);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Center(
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 700),
                  tween: Tween(begin: 0.0, end: 1.0),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    child: child,
                  ),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppColors.green,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.green.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 52),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'Deposit complete!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${deposit.weightGrams.toStringAsFixed(1)} g of '
                '${deposit.predictedClass.label} routed to compartment '
                '#${deposit.expectedPosition}.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 26),
              // Points panel
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(color: clsStyle.soft, width: 1.4),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(clsStyle.icon, size: 22, color: clsStyle.color),
                        const SizedBox(width: 10),
                        Text(
                          '+$total pts',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Points awarded by the station',
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Pill(
                          label: 'Recycling',
                          value: result.pointsAwarded,
                          accent: AppColors.green,
                        ),
                        if (result.challengeBonus > 0) ...[
                          const SizedBox(width: 10),
                          _Pill(
                            label: 'Challenge bonus',
                            value: result.challengeBonus,
                            accent: AppColors.yellow,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 3),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Done'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  ref.read(shellTabProvider.notifier).select(1);
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text('View my impact'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final int value;
  final Color accent;

  const _Pill({required this.label, required this.value, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 14, color: accent),
          const SizedBox(width: 4),
          Text(
            '+$value $label',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}