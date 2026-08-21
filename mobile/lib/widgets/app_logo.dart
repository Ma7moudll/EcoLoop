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