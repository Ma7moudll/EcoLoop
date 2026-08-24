import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../providers/data_providers.dart';
import '../../widgets/class_style.dart';
import '../../widgets/gamification_cards.dart';
import '../../widgets/state_views.dart';

/// Impact: aggregate CO2, weight, items + material breakdown from the backend.
class ImpactScreen extends ConsumerWidget {
  const ImpactScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final impactAsync = ref.watch(impactProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'My Impact',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: impactAsync.when(
        loading: () => const LoadingView(message: 'Loading your impact…'),
        error: (e, _) => ErrorView(
          message: 'Could not load impact data.',
          onRetry: () => ref.invalidate(impactProvider),
        ),
        data: (impact) {
          if (impact == null) return const EmptyView(icon: Icons.eco, title: 'Impact unavailable');
          final totalKg = impact.breakdown.fold<double>(0, (m, b) => m + b.kg);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              // Hero — total points (mockup 08)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.green, Color(0xFF0C7A69)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.green.withValues(alpha: 0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      'Your Total Impact',
                      style: TextStyle(fontSize: 12.5, color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${impact.totalPoints}',
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    const Text(
                      'Total Points',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // 3-stat row (StatTile expands itself — never wrap it)
              Row(
                children: [
                  StatTile(
                    label: 'Recycled',
                    value: Fmt.kilo(impact.recycledKg),
                    accent: AppColors.green,
                    icon: Icons.scale_outlined,
                  ),
                  const SizedBox(width: 10),
                  StatTile(
                    label: 'Items',
                    value: '${impact.itemsRecycled}',
                    icon: Icons.inventory_2_outlined,
                    accent: AppColors.blue,
                  ),
                  const SizedBox(width: 10),
                  StatTile(
                    label: 'CO₂ saved',
                    value: Fmt.co2(impact.co2SavedKg),
                    accent: AppColors.deepGreen,
                    icon: Icons.cloud_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Text(
                    'Waste Breakdown',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.foreground,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${impact.breakdown.length} materials',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final row in impact.breakdown)
                _BreakdownRow(
                  row: row,
                  totalKg: totalKg,
                ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.mint,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.emoji_objects_outlined, size: 18, color: AppColors.green),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Every item you recycle keeps waste out of landfill '
                        'and earns rewards. Keep it up!',
                        style: TextStyle(fontSize: 11.5, color: AppColors.deepGreen),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final WasteBreakdown row;
  final double totalKg;
  const _BreakdownRow({required this.row, required this.totalKg});

  @override
  Widget build(BuildContext context) {
    final style = styleForClass(row.wasteClass);
    final fraction = totalKg <= 0 ? 0.0 : (row.kg / totalKg).clamp(0.0, 1.0);
    final percent = totalKg <= 0 ? 0 : ((row.kg / totalKg) * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: style.soft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(style.icon, size: 14, color: style.color),
              ),
              const SizedBox(width: 8),
              Text(
                row.wasteClass.label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.foreground,
                ),
              ),
              const Spacer(),
              Text(
                '${row.count} items · $percent%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 7,
              backgroundColor: style.soft,
              color: style.color,
            ),
          ),
        ],
      ),
    );
  }
}