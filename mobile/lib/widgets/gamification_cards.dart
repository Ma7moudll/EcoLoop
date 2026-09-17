import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../core/app_theme.dart';
import 'ecoloop_logo.dart';

/// Hero card showing the user's current points and level.
class PointsCard extends StatelessWidget {
  final int points;
  final VoidCallback? onTap;

  const PointsCard({super.key, required this.points, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.deepGreen, Color(0xFF066D3B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              EcoLoopMark(size: 13, color: AppColors.mint),
              SizedBox(width: 6),
              Text(
                'ECOLOOP',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.mint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$points',
                style: const TextStyle(
                  fontSize: 40,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'pts',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.mint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Keep recycling to earn more rewards',
            style: TextStyle(fontSize: 11, color: AppColors.mint),
          ),
        ],
      ),
    );
  }
}

/// Stat tile used on Home / Impact.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String suffix;
  final Color accent;
  final IconData icon;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.suffix = '',
    this.accent = AppColors.green,
    this.icon = Icons.star_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: AppColors.line.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  if (suffix.isNotEmpty)
                    TextSpan(
                      text: ' $suffix',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// Horizontal row card for a leaderboard entry with rank badge.
class LeaderRow extends StatelessWidget {
  final int rank;
  final LeaderEntry entry;
  final bool isYou;
  final VoidCallback? onTap;

  const LeaderRow({
    super.key,
    required this.rank,
    required this.entry,
    this.isYou = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rankColor = rank == 1
        ? AppColors.yellow
        : rank == 2
            ? const Color(0xFF9AA3A0)
            : rank == 3
                ? AppColors.orange
                : AppColors.line;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isYou ? AppColors.mint : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(
            color: isYou ? AppColors.green : AppColors.line.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rankColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: rankColor == AppColors.line
                      ? AppColors.muted
                      : AppColors.foreground,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isYou ? FontWeight.w800 : FontWeight.w700,
                      color: AppColors.foreground,
                    ),
                  ),
                  Text(
                    entry.detail,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            if (isYou)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.green,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'YOU',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            Text(
              '${entry.points} pts',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Challenge card with progress bar and reward chip.
class ChallengeCard extends StatelessWidget {
  final Challenge challenge;
  final VoidCallback? onTap;

  const ChallengeCard({super.key, required this.challenge, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = challenge.progress;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
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
                Text(challenge.themeEmoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    challenge.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.foreground,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: challenge.completed
                        ? AppColors.green.withValues(alpha: 0.12)
                        : AppColors.yellow.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    challenge.completed
                        ? 'Completed'
                        : '+${challenge.rewardPoints} pts',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: challenge.completed ? AppColors.green : const Color(0xFF8a5a00),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              challenge.description,
              style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: p,
                minHeight: 7,
                backgroundColor: AppColors.line,
                color: AppColors.green,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${challenge.currentKg.toStringAsFixed(1)} kg',
                  style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
                ),
                Text(
                  '${challenge.targetKg.toStringAsFixed(1)} kg target',
                  style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}