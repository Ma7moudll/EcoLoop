import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'ecoloop_logo.dart';

/// EcoLoop brand mark (loop icon + wordmark).
class AppLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;

  const AppLogo({super.key, this.size = 25, this.showWordmark = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        EcoLoopMark(size: size, color: AppColors.green),
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
                  TextSpan(text: 'Eco'),
                  TextSpan(
                    text: 'Loop',
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