import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../../core/app_theme.dart';

/// Visualizes the EcoLoop station's four internal compartments and which one is
/// the routing target for the current prediction. The station is ONE physical
/// unit with a moving carriage, so compartments are shown side by side with the
/// target highlighted.
class CompartmentRack extends StatelessWidget {
  final WasteClass? openClass;
  final bool interactive;

  /// Called with the compartment position when [interactive] is true (manual
  /// confirm path / "something else" choice is NOT allowed here — routing stays
  /// purely AI-driven for the MVP, so this is informational).
  const CompartmentRack({
    super.key,
    this.openClass,
    this.interactive = false,
  });

  @override
  Widget build(BuildContext context) {
    final compartments = compartmentByPosition.values.toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    return Semantics(
      container: true,
      label: 'EcoLoop station compartments',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final c in compartments)
            CompartmentTile(
              spec: c,
              open: c.wasteClass == openClass,
              interactive: interactive,
            ),
        ],
      ),
    );
  }
}

class CompartmentTile extends StatelessWidget {
  final CompartmentSpec spec;
  final bool open;
  final bool interactive;

  const CompartmentTile({
    super.key,
    required this.spec,
    this.open = false,
    this.interactive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.fromHex(spec.colorHex);
    final bg = open ? color.withValues(alpha: 0.18) : AppColors.line;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          width: 58,
          height: 62,
          decoration: BoxDecoration(
            color: _cardBackground(context),
            borderRadius: BorderRadius.circular(AppRadii.small),
            border: Border.all(
              color: open ? color : AppColors.line,
              width: open ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  open ? Icons.arrow_outward : Icons.unfold_more,
                  size: 14,
                  color: open ? color : AppColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                spec.emoji,
                style: const TextStyle(fontSize: 14),
                semanticsLabel: spec.label,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '#${spec.position}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.foreground,
          ),
        ),
        Text(
          spec.label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: open ? color : AppColors.muted,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Color _cardBackground(BuildContext context) {
    final theme = Theme.of(context).brightness;
    return theme == Brightness.dark
        ? const Color(0xFF12261F)
        : AppColors.card;
  }
}