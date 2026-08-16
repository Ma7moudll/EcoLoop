import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/app_theme.dart';
import '../../providers/data_providers.dart';
import '../../widgets/class_style.dart';
import '../../widgets/history_row.dart';
import '../../widgets/state_views.dart';

/// Full recycling history (spec §13). Each row opens a detail journey.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Recycling history',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: historyAsync.when(
        loading: () => const LoadingView(message: 'Loading history…'),
        error: (e, _) => ErrorView(
          message: 'Could not load your history.',
          onRetry: () => ref.invalidate(historyProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              icon: Icons.recycling,
              title: 'No recycling yet',
              subtitle: 'Scan an item at the EcoLoop station to get started.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final event = items[i];
              return HistoryRow(
                event: event,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => HistoryDetailScreen(event: event),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Detail page for one deposit with its recycling journey stages.
class HistoryDetailScreen extends StatelessWidget {
  final WasteHistoryEvent event;

  const HistoryDetailScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final style = styleForClass(event.predictedClass);
    final compartment = compartmentForClass(event.predictedClass);

    return Scaffold(
      appBar: AppBar(title: const Text('Recycling journey')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Head
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: style.soft, width: 1.4),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: style.soft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(style.icon, size: 26, color: style.color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.predictedClass.probableLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Compart. #${compartment.position}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.fromHex(compartment.colorHex),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: event.pointsAwarded > 0
                        ? AppColors.rewardBg
                        : AppColors.line,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    event.pointsAwarded > 0
                        ? '+${event.pointsAwarded} pts'
                        : '0 pts',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: event.pointsAwarded > 0
                          ? AppColors.green
                          : AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Stats
          Row(
            children: [
              _InfoTile(icon: Icons.scale_outlined, label: 'Weight', value: '${event.weightGrams.toStringAsFixed(1)} g'),
              const SizedBox(width: 10),
              _InfoTile(icon: Icons.tag, label: 'Operation', value: event.operationId),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Journey',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.foreground,
            ),
          ),
          const SizedBox(height: 8),
          _JourneyStage(
            icon: Icons.center_focus_strong,
            title: 'Scanned & identified',
            subtitle: 'AI identified this as ${event.predictedClass.label.toLowerCase()}.',
            done: true,
          ),
          _JourneyStage(
            icon: Icons.scale,
            title: 'Sorted at the station',
            subtitle: 'Weighed and routed to compartment #${compartment.position}.',
            done: true,
          ),
          _JourneyStage(
            icon: Icons.recycling,
            title: 'Transported for recycling',
            subtitle: 'Collected for processing.',
            done: false,
            comingSoon: true,
          ),
          _JourneyStage(
            icon: Icons.inventory_2_outlined,
            title: 'Recycled into new products',
            subtitle: 'Final impact demonstrated.',
            done: false,
            comingSoon: true,
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.green),
            const SizedBox(height: 4),
            Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AppColors.foreground,
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 9, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _JourneyStage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final bool comingSoon;

  const _JourneyStage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.done = false,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.green : AppColors.line;
    return Container(
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
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: done ? 0.16 : 0.35),
              shape: BoxShape.circle,
            ),
            child: done
                ? const Icon(Icons.check, size: 18, color: AppColors.green)
                : Icon(icon, size: 16, color: AppColors.muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: done ? AppColors.foreground : AppColors.muted,
                        ),
                      ),
                    ),
                    if (comingSoon) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.yellow.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Coming soon',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF8a5a00),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: done ? AppColors.muted : AppColors.muted.withValues(alpha: 0.7),
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