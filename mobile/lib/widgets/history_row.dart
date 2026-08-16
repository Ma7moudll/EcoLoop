import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../core/app_theme.dart';
import 'class_style.dart';

/// One row in the recycling history list.
class HistoryRow extends StatelessWidget {
  final WasteHistoryEvent event;
  final VoidCallback? onTap;

  const HistoryRow({super.key, required this.event, this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = styleForClass(event.predictedClass);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: AppColors.line.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: style.soft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(style.icon, size: 20, color: style.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.predictedClass.probableLabel,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${event.weightGrams.toStringAsFixed(1)} g',
                    style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _DateChip(date: event.createdAt),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: event.pointsAwarded > 0
                    ? AppColors.rewardBg
                    : AppColors.line.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                event.pointsAwarded > 0
                    ? '+${event.pointsAwarded} pts'
                    : '0 pts',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: event.pointsAwarded > 0 ? AppColors.green : AppColors.muted,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final DateTime date;

  const _DateChip({required this.date});

  String get relative {
    final now = DateTime.now();
    final local = date.toLocal();
    final diff = now.difference(local);
    if (diff.inDays >= 1) {
      return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    }
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      relative,
      style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
    );
  }
}