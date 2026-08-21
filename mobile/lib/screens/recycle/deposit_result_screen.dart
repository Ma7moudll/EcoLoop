import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/app_theme.dart';
import '../../../providers/shell_tab_provider.dart';
import '../../../widgets/class_style.dart';

/// Terminal deposit outcome, rendered straight from the server snapshot.
/// Points values are 100% backend-computed; this screen only displays them.
class DepositResultScreen extends ConsumerWidget {
  final ({Deposit deposit, int pointsAwarded, int challengeBonus}) result;

  const DepositResultScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deposit = result.deposit;
    final confirmed = deposit.status == DepositStatus.confirmed;
    final total = result.pointsAwarded + result.challengeBonus;

    if (confirmed) return _Confirmed(result: result, total: total, deposit: deposit);
    return _Failed(deposit: deposit);
  }
}

class _Confirmed extends ConsumerWidget {
  final ({Deposit deposit, int pointsAwarded, int challengeBonus}) result;
  final int total;
  final Deposit deposit;

  const _Confirmed({
    required this.result,
    required this.total,
    required this.deposit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  builder: (context, value, child) =>
                      Transform.scale(scale: value, child: child),
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
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 26),
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
                    const Text(
                      'Points awarded by the station',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                    if (result.challengeBonus > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.yellow.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '+${result.challengeBonus} challenge bonus',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF8a5a00),
                          ),
                        ),
                      ),
                    ],
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

/// Rejected / expired / cancelled outcome — surface the server's reason
/// verbatim; never invent a success. A retry restarts from the station picker.
class _Failed extends StatelessWidget {
  final Deposit deposit;

  const _Failed({required this.deposit});

  @override
  Widget build(BuildContext context) {
    final (icon, accent, title, body) = switch (deposit.status) {
      DepositStatus.expired => (
          Icons.timer_off_outlined,
          AppColors.orange,
          'Deposit expired',
          'The session timed out before the station could complete the drop. '
              'Place the item and start a new session.',
        ),
      DepositStatus.cancelled => (
          Icons.cancel_outlined,
          AppColors.muted,
          'Deposit cancelled',
          'The session was cancelled. Nothing was awarded.',
        ),
      _ => (
          Icons.report_problem_outlined,
          AppColors.danger,
          'Deposit rejected',
          'The station could not accept the item.',
        ),
    };
    final reason = deposit.rejectReason;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(automaticallyImplyLeading: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Center(
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 44, color: accent),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              if (reason != null && reason.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
              ],
              const Spacer(flex: 3),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}