import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Recycle Vision brand mark (Recycle icon + wordmark).
class AppLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;

  const AppLogo({super.key, this.size = 25, this.showWordmark = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.recycling, size: size, color: AppColors.green),
        if (showWordmark)
          Padding(
            padding: const EdgeInsets.only(left: 7),
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: size * 0.56,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green,
                ),
                children: const [
                  TextSpan(text: 'Recycle'),
                  TextSpan(
                    text: 'Vision',
                    style: TextStyle(color: AppColors.deepGreen),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Subtle DEMO chip shown whenever a mocked/simulated result could be confused
/// with real AI or hardware output.
class DemoBadge extends StatelessWidget {
  final bool visible;
  const DemoBadge({super.key, this.visible = true});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.yellow.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.yellow.withValues(alpha: 0.5)),
      ),
      child: Text(
        'DEMO',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Color(0xFF8a5a00),
        ),
      ),
    );
  }
}