import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'ecoloop_logo.dart';

/// Shared, branded auth layout: a green gradient hero with the EcoLoop mark on
/// top, and a white rounded card that overlaps it holding the form. An optional
/// sticky bottom bar (e.g. a primary call-to-action) sits above the card.
class AuthLayout extends StatelessWidget {
  final String heading;
  final String subheading;
  final List<Widget> children;
  final List<Widget>? bottomBar;
  final Widget? leading;
  final Widget? banner;

  const AuthLayout({
    super.key,
    required this.heading,
    required this.subheading,
    required this.children,
    this.bottomBar,
    this.leading,
    this.banner,
  });

  @override
  Widget build(BuildContext context) {
    final formCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(heading, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(subheading, style: Theme.of(context).textTheme.bodySmall),
          if (banner != null) ...[const SizedBox(height: 16), banner!],
          const SizedBox(height: 22),
          ...children,
        ],
      ),
    );

    final brand = Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.green.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: EcoLoopMark(size: 36, color: AppColors.green),
        ),
        const SizedBox(height: 14),
        const Text('EcoLoop',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.green,
                letterSpacing: -0.4)),
        const SizedBox(height: 6),
        const Text('Sort. Scan. Earn.',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.muted)),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.background, AppColors.mint],
              ),
            ),
          ),
          if (leading != null)
            Positioned(
              top: 6,
              left: 6,
              child: leading!,
            ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          children: [
                            brand,
                            const SizedBox(height: 24),
                            formCard,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (bottomBar != null)
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      border: Border(
                        top: BorderSide(
                            color: AppColors.line.withValues(alpha: 0.8)),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 16,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: bottomBar!,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gradient primary button used by the auth screens — gives the form a more
/// premium, on-brand call-to-action than the default solid button.
class AuthButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final double height;

  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.green, AppColors.deepGreen],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.green.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: busy ? null : onPressed,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
