import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Compact horizontal progress showing the two mechanical steps of a deposit
/// session: verify weight → confirm drop. Refreshed from backend state only.
class DepositSteps extends StatelessWidget {
  final bool weightChecked;
  final bool deposited;
  final bool rewardGiven;
  final bool failed;

  const DepositSteps({
    super.key,
    this.weightChecked = false,
    this.deposited = false,
    this.rewardGiven = false,
    this.failed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(
          label: 'Weight checked',
          state: failed
              ? _ChipState.failed
              : weightChecked
                  ? _ChipState.done
                  : _ChipState.pending,
        ),
        const SizedBox(width: 8),
        _Chip(
          label: 'Deposited',
          state: failed
              ? _ChipState.failed
              : deposited
                  ? _ChipState.done
                  : _ChipState.pending,
        ),
        const SizedBox(width: 8),
        _Chip(
          label: 'Points',
          state: failed
              ? _ChipState.failed
              : rewardGiven
                  ? _ChipState.done
                  : _ChipState.pending,
        ),
      ],
    );
  }
}

enum _ChipState { pending, done, failed }

class _Chip extends StatelessWidget {
  final String label;
  final _ChipState state;

  const _Chip({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (state) {
      _ChipState.done => (AppColors.green, Icons.check_circle),
      _ChipState.failed => (AppColors.danger, Icons.cancel),
      _ChipState.pending => (AppColors.line, Icons.schedule),
    };
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: state == _ChipState.pending ? 0.14 : 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: state == _ChipState.pending
                      ? AppColors.muted
                      : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}